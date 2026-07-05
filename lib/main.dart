import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:scheduling/core/adaptive/app_scroll_behavior.dart';
import 'package:scheduling/core/connectivity/offline_banner.dart';
import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/core/notices/notice_listener.dart';
import 'package:scheduling/core/providers/firebase_providers.dart';
import 'package:scheduling/core/security/app_lock.dart';
import 'package:scheduling/core/theme/theme_notifier.dart';
import 'package:scheduling/core/theme/themes.dart';
import 'package:scheduling/core/utils/app_language.dart';
import 'package:scheduling/features/auth/application/account_status_provider.dart';
import 'package:scheduling/features/auth/data/auth_cache.dart';
import 'package:scheduling/features/auth/services/auth_service.dart';
import 'package:scheduling/features/onboarding/screens/onboarding_gate.dart';
import 'package:scheduling/features/settings/application/settings_providers.dart';
import 'package:scheduling/features/settings/data/shared_prefs_settings_repository.dart';
import 'package:scheduling/features/settings/domain/models/app_settings.dart';
import 'package:scheduling/firebase_options.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/routes/app_routes.dart';
import 'package:scheduling/shared/widgets/feedback/error_snack_bar.dart';

const bool _useFirebaseEmulator = bool.fromEnvironment('USE_FIREBASE_EMULATOR');
const String _emulatorHost = String.fromEnvironment(
  'EMULATOR_HOST',
  defaultValue: '10.0.2.2',
);

Future<void> _wireFirebaseEmulator() async {
  FirebaseFirestore.instance.useFirestoreEmulator(_emulatorHost, 8080);
  FirebaseFunctions.instance.useFunctionsEmulator(_emulatorHost, 5001);
  await Future.wait<void>([
    FirebaseAuth.instance.useAuthEmulator(_emulatorHost, 9099),
    FirebaseStorage.instance.useStorageEmulator(_emulatorHost, 9199),
  ]);
}

Future<void> main() async {
  await runZonedGuarded<Future<void>>(
    () async {
      final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
      // Inter is bundled (assets/fonts/) — never fetch fonts from the CDN.
      GoogleFonts.config.allowRuntimeFetching = false;
      FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

      final settingsFuture = SharedPrefsSettingsRepository().load();

      await Future.wait([
        initializeDateFormatting('en_CA'),
        initializeDateFormatting('fr_CA'),
        dotenv.load(fileName: 'dev/.env'),
      ]);

      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );

      Future<void> firebaseReady;
      if (_useFirebaseEmulator) {
        await _wireFirebaseEmulator();
        firebaseReady = Future<void>.value();
      } else {
        // Error handlers are plain assignments: wire them synchronously so
        // nothing is missed while the activation futures are in flight.
        final crashlytics = FirebaseCrashlytics.instance;
        FlutterError.onError = crashlytics.recordFlutterFatalError;
        PlatformDispatcher.instance.onError = (error, stack) {
          crashlytics.recordError(error, stack, fatal: true);
          return true;
        };

        // Deliberately not awaited. If activation fails before anything
        // subscribes to firebaseReadyProvider, the zone handler below
        // records it; subscribers observe the same error via the provider.
        firebaseReady = Future.wait([
          crashlytics.setCrashlyticsCollectionEnabled(!kDebugMode),
          FirebaseAppCheck.instance.activate(
            providerAndroid: kDebugMode
                ? const AndroidDebugProvider()
                : const AndroidPlayIntegrityProvider(),
            providerApple: kDebugMode
                ? const AppleDebugProvider()
                : const AppleDeviceCheckProvider(),
          ),
        ]);
      }

      final settings = await settingsFuture;

      runApp(
        ProviderScope(
          retry: (retryCount, error) => null,
          overrides: [
            firebaseReadyProvider.overrideWith((ref) => firebaseReady),
          ],
          child: PaulApp(settings: settings),
        ),
      );
    },
    (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    },
  );
}

class PaulApp extends ConsumerStatefulWidget {
  const PaulApp({required this.settings, super.key});

  final AppSettings settings;

  @override
  ConsumerState<PaulApp> createState() => _PaulAppState();
}

class _PaulAppState extends ConsumerState<PaulApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  final _scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
  final _settingsRepository = SharedPrefsSettingsRepository();
  final _settingsSaveDebouncer = SettingsSaveDebouncer();
  late ThemeMode _themeMode;
  late double _textScale;
  late AppLanguageController _languageController;
  bool _isHandlingAccountExit = false;

  @override
  void initState() {
    super.initState();
    _themeMode = widget.settings.themeMode;
    _textScale = widget.settings.textScale;
    _languageController = AppLanguageController.instance;
    _languageController.setLanguage(widget.settings.language);
  }

  @override
  void dispose() {
    _settingsSaveDebouncer.dispose();
    super.dispose();
  }

  void toggleTheme() {
    setState(() {
      _themeMode = _themeMode == ThemeMode.dark
          ? ThemeMode.light
          : ThemeMode.dark;
    });
    _settingsRepository.save(themeMode: _themeMode);
  }

  void setTextScale(double value) {
    setState(() {
      _textScale = value;
    });
    _settingsSaveDebouncer.run(
      () => _settingsRepository.save(textScale: value),
    );
  }

  void setLanguage(String code) {
    _languageController.setLanguage(code);
    _settingsRepository.save(language: code);
  }

  Future<void> _handleAccountDisabled(
    String Function(AppLocalizations) selectMessage,
  ) async {
    if (_isHandlingAccountExit) return;
    if (FirebaseAuth.instance.currentUser == null) return;

    final navContext = _navigatorKey.currentContext;
    if (navContext == null) return;
    _isHandlingAccountExit = true;

    var exitScheduled = false;
    try {
      final message = selectMessage(AppLocalizations.of(navContext));
      await ref.read(authServiceProvider).signOut();

      WidgetsBinding.instance.addPostFrameCallback((_) {
        _navigatorKey.currentState?.pushNamedAndRemoveUntil(
          AppRoutes.login,
          (_) => false,
        );
        _scaffoldMessengerKey.currentState?.showSnackBar(
          errorSnackBar(navContext, message),
        );
        _isHandlingAccountExit = false;
      });
      exitScheduled = true;
    } catch (e, st) {
      // Sign-out failed (network/plugin) — the next signal retries.
      ref.read(loggerProvider).warn('ACCOUNT-EXIT sign-out failed', e, st);
    } finally {
      // Reset on failure too, or every later disabled/deleted signal is muted.
      if (!exitScheduled) _isHandlingAccountExit = false;
    }
  }

  void _listenForAccountDisabled() {
    ref.listen<AsyncValue<bool>>(accountDisabledProvider, (prev, next) {
      final wasDisabled = prev?.value ?? false;
      final isDisabled = next.value ?? false;
      if (!wasDisabled && isDisabled) {
        _handleAccountDisabled((l10n) => l10n.error_thisAccountHasBeenDisabled);
      }
    });
  }

  void _listenForRoleRevocation() {
    ref.listen<AsyncValue<String>>(userRoleProvider, (prev, next) {
      final prevRole = prev?.value;
      final nextRole = next.value;
      if (prevRole == 'admin' && nextRole != null && nextRole != 'admin') {
        _handleAccountDisabled((l10n) => l10n.error_yourAdminAccessWasRevoked);
      }
    });
  }

  void _listenForDeletedAccount() {
    ref.listen<AsyncValue<Map<String, dynamic>>>(currentUserDocProvider, (
      prev,
      next,
    ) {
      final isSignedIn = FirebaseAuth.instance.currentUser != null;
      final resolvedUid = ref.read(authUidProvider).value;
      // Kick-out: populated→empty = runtime delete; cold start handled below.
      if (isAccountDeletionSignal(
        isSignedIn: isSignedIn,
        resolvedUid: resolvedUid,
        previous: prev,
        docState: next,
      )) {
        _handleAccountDisabled((l10n) => l10n.error_thisAccountHasBeenDisabled);
        return;
      }
      unawaited(
        confirmColdStartDeletion(
          isSignedIn: isSignedIn,
          resolvedUid: resolvedUid,
          previous: prev,
          docState: next,
          loadWarmCache: ref.read(authCacheProvider).loadIfMatch,
        ).then((deleted) {
          if (deleted && mounted) {
            _handleAccountDisabled(
              (l10n) => l10n.error_thisAccountHasBeenDisabled,
            );
          }
        }),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    _listenForAccountDisabled();
    _listenForRoleRevocation();
    _listenForDeletedAccount();
    return AppLanguageScope(
      controller: _languageController,
      child: ThemeNotifier(
        themeMode: _themeMode,
        toggleTheme: toggleTheme,
        textScale: _textScale,
        setTextScale: setTextScale,
        setLanguage: setLanguage,
        child: ValueListenableBuilder<String>(
          valueListenable: _languageController,
          builder: (context, languageCode, _) {
            final locale = Locale(languageCode, 'CA');
            return MaterialApp(
              navigatorKey: _navigatorKey,
              scaffoldMessengerKey: _scaffoldMessengerKey,
              debugShowCheckedModeBanner: false,
              locale: locale,
              supportedLocales: AppLocalizations.supportedLocales,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              theme: lightTheme(),
              darkTheme: darkTheme(),
              themeMode: _themeMode,
              scrollBehavior: const AppScrollBehavior(),
              home: const OnboardingGate(),
              onGenerateRoute: AppRoutes.onGenerateRoute,
              builder: (context, child) {
                final media = MediaQuery.of(context);
                // Compose in-app text scale with the OS scale, capped at 2.2.
                final systemFactor = media.textScaler.scale(14) / 14;
                final effectiveScale = math.min(
                  _textScale * systemFactor,
                  2.2,
                );
                return MediaQuery(
                  data: media.copyWith(
                    textScaler: TextScaler.linear(effectiveScale),
                  ),
                  child: AppLock(
                    child: NoticeListener(
                      navigatorKey: _navigatorKey,
                      child: Column(
                        children: [
                          Expanded(child: child ?? const SizedBox.shrink()),
                          const OfflineBanner(),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

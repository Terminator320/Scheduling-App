import 'dart:async';
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
import 'package:intl/date_symbol_data_local.dart';
import 'package:scheduling/core/notices/notice_listener.dart';
import 'package:scheduling/core/providers/firebase_providers.dart';
import 'package:scheduling/core/security/app_lock.dart';
import 'package:scheduling/core/theme/theme_notifier.dart';
import 'package:scheduling/core/theme/themes.dart';
import 'package:scheduling/core/utils/app_language.dart';
import 'package:scheduling/features/auth/application/account_status_provider.dart';
import 'package:scheduling/features/auth/services/auth_service.dart';
import 'package:scheduling/features/onboarding/screens/onboarding_gate.dart';
import 'package:scheduling/features/settings/application/settings_providers.dart';
import 'package:scheduling/features/settings/data/shared_prefs_settings_repository.dart';
import 'package:scheduling/features/settings/domain/models/app_settings.dart';
import 'package:scheduling/firebase_options.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/routes/app_routes.dart';

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
      FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

      final settingsFuture = SharedPrefsSettingsRepository().load();

      await Future.wait([
        initializeDateFormatting('en_CA'),
        initializeDateFormatting('fr_CA'),
        dotenv.load(fileName: 'dev/.env'),
      ]);

      // TODO(ios): On Mac run `flutterfire configure` to populate iOS fields in firebase_options.dart, then swap DefaultFirebaseOptions.android -> DefaultFirebaseOptions.currentPlatform.
      await Firebase.initializeApp(options: DefaultFirebaseOptions.android);

      if (_useFirebaseEmulator) {
        await _wireFirebaseEmulator();
      } else {
        final crashlytics = FirebaseCrashlytics.instance;
        FlutterError.onError = crashlytics.recordFlutterFatalError;
        PlatformDispatcher.instance.onError = (error, stack) {
          crashlytics.recordError(error, stack, fatal: true);
          return true;
        };

        await Future.wait([
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
    final scheme = Theme.of(navContext).colorScheme;
    final message = selectMessage(AppLocalizations.of(navContext));
    await AuthService().signOut();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _navigatorKey.currentState?.pushNamedAndRemoveUntil(
        AppRoutes.login,
        (_) => false,
      );
      _scaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(
          backgroundColor: scheme.errorContainer,
          content: Row(
            children: [
              Icon(Icons.error_outline, color: scheme.onErrorContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(color: scheme.onErrorContainer),
                ),
              ),
            ],
          ),
        ),
      );
      _isHandlingAccountExit = false;
    });
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
      if (isAccountDeletionSignal(
        isSignedIn: FirebaseAuth.instance.currentUser != null,
        resolvedUid: ref.read(authUidProvider).value,
        docState: next,
      )) {
        _handleAccountDisabled((l10n) => l10n.error_thisAccountHasBeenDisabled);
      }
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
              home: const OnboardingGate(),
              onGenerateRoute: AppRoutes.onGenerateRoute,
              builder: (context, child) {
                return MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(_textScale)),
                  child: AppLock(
                    child: NoticeListener(
                      navigatorKey: _navigatorKey,
                      child: child ?? const SizedBox.shrink(),
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

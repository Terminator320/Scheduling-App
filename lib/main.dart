import 'dart:async';
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/core/notices/notice_listener.dart';
import 'package:scheduling/core/utils/retry.dart';
import 'package:scheduling/core/theme/theme_notifier.dart';
import 'package:scheduling/core/theme/themes.dart';
import 'package:scheduling/core/utils/app_language.dart';
import 'package:scheduling/core/utils/l10n_extensions.dart';
import 'package:scheduling/features/auth/application/account_status_provider.dart';
import 'package:scheduling/features/auth/data/auth_cache.dart';
import 'package:scheduling/features/auth/services/auth_service.dart';
import 'package:scheduling/features/calendar/screens/main_calendar_screen.dart';
import 'package:scheduling/features/employees/data/firebase_employees_repository.dart';
import 'package:scheduling/features/employees/domain/employees_repository.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';
import 'package:scheduling/features/settings/application/settings_providers.dart';
import 'package:scheduling/features/settings/data/shared_prefs_settings_repository.dart';
import 'package:scheduling/features/settings/domain/models/app_settings.dart';
import 'package:scheduling/features/splash/screens/splash_screen.dart';
import 'package:scheduling/firebase_options.dart';
import 'package:scheduling/l10n/app_localizations.dart';
import 'package:scheduling/routes/app_routes.dart';

const _kLocalizationsDelegates = <LocalizationsDelegate<dynamic>>[
  AppLocalizations.delegate,
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];

const bool _useFirebaseEmulator = bool.fromEnvironment('USE_FIREBASE_EMULATOR');
// Android emulator can't reach the host's loopback at 127.0.0.1 — 10.0.2.2 is
// the special alias for the host. iOS simulator and desktop builds use 127.0.0.1.
const String _emulatorHost = String.fromEnvironment(
  'EMULATOR_HOST',
  defaultValue: '10.0.2.2',
);

Future<void> _wireFirebaseEmulator() async {
  FirebaseAuth.instance.useAuthEmulator(_emulatorHost, 9099);
  FirebaseFirestore.instance.useFirestoreEmulator(_emulatorHost, 8080);
  await FirebaseStorage.instance.useStorageEmulator(_emulatorHost, 9199);
}

Future<void> main() async {
  await runZonedGuarded<Future<void>>(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      await initializeDateFormatting('en_CA');
      await initializeDateFormatting('fr_CA');

      await dotenv.load(fileName: 'dev/.env');

      // TODO(restructure): swap to DefaultFirebaseOptions.currentPlatform once
      // `flutterfire configure` has been run on a Mac to add iOS values.
      await Firebase.initializeApp(options: DefaultFirebaseOptions.android);

      // Emulator-only path: wire SDKs to localhost before any reads/writes,
      // and skip Crashlytics + App Check (they call prod endpoints). Toggled
      // by `flutter run --dart-define=USE_FIREBASE_EMULATOR=true`.
      if (_useFirebaseEmulator) {
        await _wireFirebaseEmulator();
      } else {
        await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(
          kReleaseMode,
        );
        FlutterError.onError =
            FirebaseCrashlytics.instance.recordFlutterFatalError;
        PlatformDispatcher.instance.onError = (error, stack) {
          FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
          return true;
        };

        await FirebaseAppCheck.instance.activate(
          providerAndroid: kDebugMode
              ? const AndroidDebugProvider()
              : const AndroidPlayIntegrityProvider(),
          providerApple: kDebugMode
              ? const AppleDebugProvider()
              : const AppleDeviceCheckProvider(),
        );
      }

      final settings = await SharedPrefsSettingsRepository().load();
      final home = await _resolveHome();

      runApp(
        ProviderScope(
          child: PaulApp(settings: settings, home: home),
        ),
      );
    },
    (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    },
  );
}

/// Determines the first screen to show.
/// - Logged-in user with a valid cache → skip the 3-second splash, verify role
///   from Firestore (fast — SDK serves from local cache when offline), then go
///   straight to MainCalendar.
/// - Otherwise → SplashScreen handles auth resolution as before.
///
/// isAdmin is never read from the local cache. The local cache only tells us
/// whether a Firestore lookup is worth attempting (uid match). The role always
/// comes from Firestore so that role changes and deactivations take effect on
/// the very next launch.
Future<Widget> _resolveHome() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return const SplashScreen();

  final cached = await AuthCache().loadIfMatch(user.uid);
  if (cached == null) return const SplashScreen();

  // Transient errors (network, Firestore unavailable) shouldn't sign the user
  // out — silent retry with bounded backoff before falling through to
  // SplashScreen, which has its own resolution path as a last resort.
  final repo = FirebaseEmployeesRepository(FirebaseFirestore.instance);
  final logger = AppLogger();
  final UserUidMatch? userDoc;
  try {
    userDoc = await retryAsync(
      () => repo.findUserByUid(user.uid),
      delays: const [Duration(milliseconds: 500), Duration(milliseconds: 1500)],
      onRetry: (attempt, e, st) =>
          logger.warn('_resolveHome findUserByUid retry $attempt', e, st),
    );
  } catch (e, st) {
    logger.warn('_resolveHome findUserByUid failed after retries', e, st);
    return const SplashScreen();
  }
  if (userDoc == null) return _signOutToSplash();

  final employee = EmployeeRecord.fromMap(userDoc.id, userDoc.data);
  // CLAUDE.md invariant: only `status == 'active'` may enter the app. Any
  // other status (disabled, invited, empty, future values) bounces back to
  // SplashScreen so a single source of truth handles re-auth or sign-out.
  if (!employee.isActive) return _signOutToSplash();

  unawaited(AuthCache().save(employee));
  return MainCalendar(isAdmin: employee.isAdmin, employeeId: employee.id);
}

Future<Widget> _signOutToSplash() async {
  await FirebaseAuth.instance.signOut();
  await AuthCache().clear();
  return const SplashScreen();
}

class PaulApp extends ConsumerStatefulWidget {
  const PaulApp({required this.settings, required this.home, super.key});

  final AppSettings settings;
  final Widget home;

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

  Future<void> _handleAccountDisabled(String message) async {
    if (FirebaseAuth.instance.currentUser == null) return;
    await AuthService().signOut();
    final nav = _navigatorKey.currentState;
    if (nav != null) {
      unawaited(nav.pushNamedAndRemoveUntil(AppRoutes.login, (_) => false));
    }
    _scaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _listenForAccountDisabled(BuildContext context) {
    ref.listen<AsyncValue<bool>>(accountDisabledProvider, (prev, next) {
      final wasDisabled = prev?.valueOrNull ?? false;
      final isDisabled = next.valueOrNull ?? false;
      if (!wasDisabled && isDisabled) {
        _handleAccountDisabled(context.l10n.thisAccountHasBeenDisabled);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    _listenForAccountDisabled(context);
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
              localizationsDelegates: _kLocalizationsDelegates,
              theme: lightTheme(),
              darkTheme: darkTheme(),
              themeMode: _themeMode,
              home: widget.home,
              onGenerateRoute: AppRoutes.onGenerateRoute,
              builder: (context, child) {
                return MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(_textScale)),
                  child: NoticeListener(
                    child: child ?? const SizedBox.shrink(),
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

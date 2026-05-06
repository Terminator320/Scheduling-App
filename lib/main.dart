import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:scheduling/l10n/app_localizations.dart';

import 'package:scheduling/core/services/settings_service.dart';
import 'package:scheduling/core/services/user_cache_service.dart';
import 'package:scheduling/core/theme/theme_notifier.dart';
import 'package:scheduling/core/theme/themes.dart';
import 'package:scheduling/core/utils/app_language.dart';
import 'package:scheduling/features/calendar/screens/main_calendar_screen.dart';
import 'package:scheduling/features/employees/models/employee_record.dart';
import 'package:scheduling/features/employees/services/user_service.dart';
import 'package:scheduling/features/splash/screens/splash_screen.dart';
import 'package:scheduling/firebase_options.dart';
import 'package:scheduling/routes/app_routes.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await initializeDateFormatting('en_CA');
  await initializeDateFormatting('fr_CA');

  await dotenv.load(fileName: "dev/.env");

  await Firebase.initializeApp(options: DefaultFirebaseOptions.android);

  final settings = await SettingsService().load();
  final home = await _resolveHome();

  runApp(PaulApp(settings: settings, home: home));
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

  final cached = await UserCacheService().loadIfMatch(user.uid);
  if (cached == null) return const SplashScreen();

  // Cache hit: skip the splash delay but still verify role from Firestore.
  final userDoc = await UserService().findUserByUid(user.uid);
  if (userDoc == null) {
    await FirebaseAuth.instance.signOut();
    await UserCacheService().clear();
    return const SplashScreen();
  }

  final employee = EmployeeRecord.fromMap(userDoc.id, userDoc.data());
  unawaited(UserCacheService().save(employee));
  return MainCalendar(isAdmin: employee.isAdmin, employeeId: employee.id);
}

class PaulApp extends StatefulWidget {
  final AppSettings settings;
  final Widget home;

  const PaulApp({super.key, required this.settings, required this.home});

  @override
  State<PaulApp> createState() => _PaulAppState();
}

class _PaulAppState extends State<PaulApp> {
  final SettingsService _settingsService = SettingsService();
  final SettingsSaveDebouncer _settingsSaveDebouncer = SettingsSaveDebouncer();
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
    _settingsService.save(themeMode: _themeMode);
  }

  void setTextScale(double value) {
    setState(() {
      _textScale = value;
    });
    _settingsSaveDebouncer.run(() => _settingsService.save(textScale: value));
  }

  void setLanguage(String code) {
    _languageController.setLanguage(code);
    _settingsService.save(language: code);
  }

  @override
  Widget build(BuildContext context) {
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
              debugShowCheckedModeBanner: false,
              locale: locale,
              supportedLocales: AppLocalizations.supportedLocales,
              localizationsDelegates: const [
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              theme: Themes.light,
              darkTheme: Themes.dark,
              themeMode: _themeMode,
              home: widget.home,
              onGenerateRoute: AppRoutes.onGenerateRoute,
              builder: (context, child) {
                return MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: TextScaler.linear(_textScale),
                  ),
                  child: child ?? const SizedBox.shrink(),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

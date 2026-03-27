import 'package:flutter/material.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

import 'screens/auth/auth_screens.dart';
import 'screens/admin/calendar_screens.dart';
import 'screens/admin/employees_screens.dart';
import 'screens/admin/clients_screens.dart';
import 'screens/admin/appointments_screens.dart';
import 'screens/admin/settings_screens.dart';
import 'screens/employee/settings_screens.dart';
import 'utils/app_font_scale.dart';
import 'utils/app_language.dart';
import 'utils/app_theme_mode.dart';
import 'utils/app_text.dart';




void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: "dev/.env");

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.android,
  );

  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AppLanguageScope(
      controller: AppLanguageController.instance,
      child: AppThemeModeScope(
        controller: AppThemeModeController.instance,
        child: AppFontScaleScope(
          controller: AppFontScaleController.instance,
          child: Builder(
            builder: (context) {
              final isDark = AppThemeModeScope.of(context).isDark;

              return MaterialApp(
                debugShowCheckedModeBanner: false,
                title: tr(context, 'Scheduling App'),
                theme: ThemeData(
                  useMaterial3: true,
                  fontFamily: 'Roboto',
                  brightness: Brightness.light,
                ),
                darkTheme: ThemeData(
                  useMaterial3: true,
                  fontFamily: 'Roboto',
                  brightness: Brightness.dark,
                ),
                themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
                builder: (context, child) {
                  final mediaQuery = MediaQuery.of(context);
                  final fontScale = AppFontScaleScope.of(context).value;
                  return MediaQuery(
                    data: mediaQuery.copyWith(
                      textScaler: TextScaler.linear(fontScale),
                    ),
                    child: child ?? const SizedBox.shrink(),
                  );
                },
                home: isDark ? LoginDarkScreen() : LoginLightScreen(),
                routes: {
                  '/admin/calendar/light': (context) => AdminCalendarPage(),
                  '/admin/calendar/dark': (context) => AdminCalendarDarkPage(),
                  '/admin/employees/light': (context) => AdminEmployeesPage(),
                  '/admin/employees/dark': (context) => AdminEmployeesDarkPage(),
                  '/admin/clients/light': (context) => AdminClientsPage(),
                  '/admin/clients/dark': (context) => AdminClientsDarkPage(),
                  '/admin/appointments/light': (context) => AdminAppointmentsPage(),
                  '/admin/appointments/dark': (context) => AdminAppointmentsDarkPage(),
                  '/admin/settings/light': (context) => AdminSettingsPage(),
                  '/admin/settings/dark': (context) => AdminSettingsDarkPage(),

                },
              );
            },
          ),
        ),
      ),
    );
  }
}

/* ---------------- LOGIN LIGHT ---------------- */
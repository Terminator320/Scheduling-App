import 'package:flutter/material.dart';

import 'screens/auth/auth_screens.dart';
import 'screens/admin/calendar_screens.dart';
import 'screens/admin/employees_screens.dart';
import 'screens/admin/clients_screens.dart';
import 'screens/admin/appointments_screens.dart';
import 'screens/admin/settings_screens.dart';
import 'screens/employee/employee_calendar.dart';
import 'screens/employee/settings_screens.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  static _MyAppState of(BuildContext context) {
    final state = context.findAncestorStateOfType<_MyAppState>();
    if (state == null) {
      throw Exception('MyApp state not found');
    }
    return state;
  }

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  double _fontScale = 1.0;

  double get fontScale => _fontScale;

  void setFontScale(double value) {
    setState(() {
      _fontScale = value.clamp(0.8, 1.4);
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Scheduling App',
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Roboto',
      ),
      builder: (context, child) {
        final mediaQuery = MediaQuery.of(context);

        return MediaQuery(
          data: mediaQuery.copyWith(
            textScaler: TextScaler.linear(_fontScale),
          ),
          child: child!,
        );
      },
      home: LoginLightScreen(),
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
        '/employee/calendar/light': (context) => EmployeeCalendarPage(),
        '/employee/calendar/dark': (context) => EmployeeCalendarDarkPage(),
        '/employee/settings/light': (context) => EmployeeSettingsPage(),
        '/employee/settings/dark': (context) => EmployeeSettingsDarkPage(),
      },
    );
  }
}


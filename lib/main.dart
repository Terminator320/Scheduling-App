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
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Scheduling App',
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Roboto',
      ),
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

/* ---------------- LOGIN LIGHT ---------------- */

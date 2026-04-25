import 'package:flutter/material.dart';

import 'package:scheduling/features/auth/screens/forgot_password_screen.dart';
import 'package:scheduling/features/auth/screens/login_screen.dart';
import 'package:scheduling/features/calendar/screens/main_calendar_screen.dart';
import 'package:scheduling/features/clients/screens/clients_screen.dart';
import 'package:scheduling/features/employees/screens/employees_screen.dart';
import 'package:scheduling/features/splash/screens/splash_screen.dart';

class AppRoutes {
  AppRoutes._();

  static const String splash = '/';
  static const String login = '/login';
  static const String forgotPassword = '/forgot-password';
  static const String mainCalendar = '/calendar';
  static const String employees = '/employees';
  static const String clients = '/clients';

  static Route<dynamic>? onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case splash:
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => const SplashScreen(),
        );

      case login:
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => const Login(),
        );

      case forgotPassword:
        final args = settings.arguments as ForgotPasswordArgs?;
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => ForgotPassword(initialEmail: args?.initialEmail),
        );

      case mainCalendar:
        final args = settings.arguments as MainCalendarArgs;
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => MainCalendar(
            isAdmin: args.isAdmin,
            employeeId: args.employeeId,
          ),
        );

      case employees:
        final args = settings.arguments as MainCalendarArgs;
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => AddEmployeePage(isAdmin: args.isAdmin, employeeId: args.employeeId),
        );

      case clients:
        final args = settings.arguments as ClientsListArgs;
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => ListInformation(
            mode: args.mode,
            isAdmin: args.isAdmin,
            employeeId: args.employeeId,
          ),
        );

      default:
        return null;
    }
  }
}

class ForgotPasswordArgs {
  final String? initialEmail;
  const ForgotPasswordArgs({this.initialEmail});
}

class MainCalendarArgs {
  final bool isAdmin;
  final String employeeId;
  const MainCalendarArgs({required this.isAdmin, required this.employeeId});
}

class ClientsListArgs {
  final String mode;
  final bool isAdmin;
  final String employeeId;
  const ClientsListArgs({
    required this.mode,
    required this.isAdmin,
    required this.employeeId,
  });
}

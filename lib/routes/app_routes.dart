import 'package:flutter/material.dart';

import 'package:scheduling/features/auth/screens/forgot_password_screen.dart';
import 'package:scheduling/features/auth/screens/login_screen.dart';
import 'package:scheduling/features/calendar/screens/main_calendar_screen.dart';
import 'package:scheduling/features/clients/screens/clients_screen.dart';
import 'package:scheduling/features/clients/screens/history_screen.dart';
import 'package:scheduling/features/employees/screens/employees_screen.dart';
import 'package:scheduling/features/settings/screens/settings_screen.dart';
import 'package:scheduling/features/splash/screens/splash_screen.dart';

class AppRoutes {
  AppRoutes._();

  static const String splash = '/';
  static const String login = '/login';
  static const String forgotPassword = '/forgot-password';
  static const String mainCalendar = '/calendar';
  static const String employees = '/employees';
  static const String clients = '/clients';
  static const String history = '/history';
  static const String settings = '/settings';

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
          builder: (_) =>
              ForgotPasswordScreen(initialEmail: args?.initialEmail),
        );

      case mainCalendar:
        final args = settings.arguments! as MainCalendarArgs;
        return _fadeRoute(
          settings,
          MainCalendar(isAdmin: args.isAdmin, employeeId: args.employeeId),
        );

      case employees:
        final args = settings.arguments! as MainCalendarArgs;
        return _fadeRoute(
          settings,
          AddEmployeePage(isAdmin: args.isAdmin, employeeId: args.employeeId),
        );

      case clients:
        final args = settings.arguments! as ClientsListArgs;
        return _fadeRoute(
          settings,
          ListInformation(isAdmin: args.isAdmin, employeeId: args.employeeId),
        );

      case history:
        final args = settings.arguments! as HistoryArgs;
        return _fadeRoute(
          settings,
          HistoryScreen(isAdmin: args.isAdmin, employeeId: args.employeeId),
        );

      case AppRoutes.settings:
        // Settings is only reachable post-login, so args are always present.
        final args = settings.arguments! as SettingsArgs;
        return _fadeRoute(
          settings,
          SettingsScreen(
            name: args.name,
            email: args.email,
            role: args.role,
            employeeId: args.employeeId,
          ),
        );

      default:
        return null;
    }
  }

  /// A clean cross-fade between hub destinations. The chrome (top bar + nav
  /// rail) sits in the same place on every hub screen, so fading — with no
  /// scale or slide — reads as just the body and the rail's selected highlight
  /// changing, with the frame staying put. Collapses to an instant cut when the
  /// platform requests reduced motion.
  static PageRouteBuilder<T> _fadeRoute<T>(
    RouteSettings settings,
    Widget page,
  ) {
    return PageRouteBuilder<T>(
      settings: settings,
      reverseTransitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (_, _, _) => page,
      transitionsBuilder: (context, animation, _, child) {
        if (MediaQuery.disableAnimationsOf(context)) return child;
        return FadeTransition(
          opacity: animation.drive(CurveTween(curve: Curves.easeInOut)),
          child: child,
        );
      },
    );
  }
}

class ForgotPasswordArgs {
  const ForgotPasswordArgs({this.initialEmail});
  final String? initialEmail;
}

class MainCalendarArgs {
  const MainCalendarArgs({required this.isAdmin, required this.employeeId});
  final bool isAdmin;
  final String employeeId;
}

class ClientsListArgs {
  const ClientsListArgs({required this.isAdmin, required this.employeeId});
  final bool isAdmin;
  final String employeeId;
}

class HistoryArgs {
  const HistoryArgs({required this.isAdmin, required this.employeeId});
  final bool isAdmin;
  final String employeeId;
}

class SettingsArgs {
  const SettingsArgs({
    required this.name,
    required this.email,
    this.role,
    this.employeeId = '',
  });
  final String name;
  final String email;
  final String? role;
  final String employeeId;
}

import 'package:flutter/material.dart';
import 'package:scheduling/core/layout/adaptive_shell.dart';
import 'package:scheduling/features/auth/screens/forgot_password_screen.dart';
import 'package:scheduling/features/auth/screens/login_screen.dart';
import 'package:scheduling/features/calendar/screens/day_route_screen.dart';
import 'package:scheduling/features/dashboard/screens/dashboard_screen.dart';
import 'package:scheduling/routes/hub_shell.dart';

class AppRoutes {
  AppRoutes._();

  static const String login = '/login';
  static const String forgotPassword = '/forgot-password';
  static const String mainCalendar = '/calendar';
  static const String employees = '/employees';
  static const String clients = '/clients';
  static const String history = '/history';
  static const String liveMap = '/live-map';
  static const String settings = '/settings';
  static const String dashboard = '/dashboard';
  static const String dayRoute = '/day-route';

  static Route<dynamic>? onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case login:
        return AppPageRoute(
          settings: settings,
          builder: (_) => const Login(),
        );

      case forgotPassword:
        final args = settings.arguments as ForgotPasswordArgs?;
        return AppPageRoute(
          settings: settings,
          builder: (_) =>
              ForgotPasswordScreen(initialEmail: args?.initialEmail),
        );

      case dashboard:
        final args = settings.arguments as DashboardArgs?;
        return AppPageRoute(
          settings: settings,
          // Admin-only screen; default isAdmin to true if pushed without args.
          builder: (_) => DashboardScreen(
            isAdmin: args?.isAdmin ?? true,
            employeeId: args?.employeeId ?? '',
            userName: args?.userName,
            email: args?.email,
          ),
        );

      case dayRoute:
        final args = settings.arguments! as DayRouteArgs;
        return AppPageRoute(
          settings: settings,
          builder: (_) => DayRouteScreen(
            isAdmin: args.isAdmin,
            employeeId: args.employeeId,
          ),
        );

      case mainCalendar:
        // Post-login entry: builds fresh shell (pushReplacement always).
        final args = settings.arguments! as MainCalendarArgs;
        return AppPageRoute(
          settings: settings,
          builder: (_) => HubShell(
            isAdmin: args.isAdmin,
            employeeId: args.employeeId,
          ),
        );

      case employees:
        final args = settings.arguments! as MainCalendarArgs;
        return _hubRoute(
          settings,
          AdaptiveDestination.employees,
          isAdmin: args.isAdmin,
          employeeId: args.employeeId,
        );

      case clients:
        final args = settings.arguments! as ClientsListArgs;
        return _hubRoute(
          settings,
          AdaptiveDestination.clients,
          isAdmin: args.isAdmin,
          employeeId: args.employeeId,
        );

      case history:
        final args = settings.arguments! as HistoryArgs;
        return _hubRoute(
          settings,
          AdaptiveDestination.history,
          isAdmin: args.isAdmin,
          employeeId: args.employeeId,
        );

      case liveMap:
        final args = settings.arguments! as MainCalendarArgs;
        return _hubRoute(
          settings,
          AdaptiveDestination.liveMap,
          isAdmin: args.isAdmin,
          employeeId: args.employeeId,
        );

      case AppRoutes.settings:
        // Settings is only reachable post-login, so args are always present.
        final args = settings.arguments! as SettingsArgs;
        return _hubRoute(
          settings,
          AdaptiveDestination.settings,
          isAdmin: args.role == 'admin',
          employeeId: args.employeeId,
          userName: args.name,
          userEmail: args.email,
        );

      default:
        return null;
    }
  }

  /// Non-calendar hub route: redirects to tab switch on live shell or opens fresh one.
  static Route<dynamic> _hubRoute(
    RouteSettings routeSettings,
    AdaptiveDestination destination, {
    required bool isAdmin,
    required String employeeId,
    String userName = '',
    String userEmail = '',
  }) {
    if (HubShell.liveState != null) {
      return HubTabRedirectRoute(
        settings: routeSettings,
        destination: destination,
        isAdmin: isAdmin,
        employeeId: employeeId,
        userName: userName,
        userEmail: userEmail,
      );
    }
    return AppPageRoute(
      settings: routeSettings,
      builder: (_) => HubShell(
        initialDestination: destination,
        isAdmin: isAdmin,
        employeeId: employeeId,
        userName: userName,
        userEmail: userEmail,
      ),
    );
  }
}

/// Standard page route with platform-default transitions and reduced-motion support.
class AppPageRoute<T> extends MaterialPageRoute<T> {
  AppPageRoute({required super.builder, super.settings});

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return super.buildTransitions(
      context,
      animation,
      secondaryAnimation,
      child,
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

class DayRouteArgs {
  const DayRouteArgs({required this.isAdmin, required this.employeeId});
  final bool isAdmin;
  final String employeeId;
}

class DashboardArgs {
  const DashboardArgs({
    required this.isAdmin,
    required this.employeeId,
    this.userName,
    this.email,
  });
  final bool isAdmin;
  final String employeeId;
  final String? userName;
  final String? email;
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

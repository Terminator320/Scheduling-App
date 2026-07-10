import 'package:flutter/material.dart';

import 'package:scheduling/core/layout/adaptive_shell.dart';
import 'package:scheduling/features/auth/screens/forgot_password_screen.dart';
import 'package:scheduling/features/dashboard/screens/dashboard_screen.dart';
import 'package:scheduling/features/auth/screens/login_screen.dart';
import 'package:scheduling/routes/hub_shell.dart';

class AppRoutes {
  AppRoutes._();

  static const String login = '/login';
  static const String forgotPassword = '/forgot-password';
  static const String mainCalendar = '/calendar';
  static const String employees = '/employees';
  static const String clients = '/clients';
  static const String history = '/history';
  static const String settings = '/settings';
  static const String dashboard = '/dashboard';

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
        return AppPageRoute(
          settings: settings,
          builder: (_) => const DashboardScreen(),
        );

      case mainCalendar:
        // The post-login entry: hosts the persistent hub shell (U1/P4).
        // Always builds a fresh shell — this route is only ever the target
        // of a pushReplacement (login, splash, drawer), so by the time it
        // builds there is no live shell left to redirect into.
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

  /// Route for a non-calendar hub destination. The settings drawer still
  /// pushes these as named routes; when a [HubShell] is live that push is
  /// redirected into a tab switch on it ([HubTabRedirectRoute]) so the shell
  /// and its kept-alive screens stay the single navigation root. With no
  /// live shell (deep entry), a fresh shell opens on the requested tab.
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

/// The app's standard page route: platform-default transitions (Cupertino
/// slide with swipe-back on iOS, zoom/predictive-back on Android) that
/// collapse to an instant cut when the platform requests reduced motion.
///
/// Replaces the old bare fade `PageRouteBuilder`, whose custom transition
/// broke the iOS back-swipe gesture on pushed routes (U1).
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

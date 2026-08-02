import 'package:flutter/material.dart';
import 'package:scheduling/core/navigation/app_destination.dart';
import 'package:scheduling/features/auth/screens/accept_invite_code_screen.dart';
import 'package:scheduling/features/auth/screens/accept_invite_details_screen.dart';
import 'package:scheduling/features/auth/screens/forgot_password_screen.dart';
import 'package:scheduling/features/auth/screens/login_screen.dart';
import 'package:scheduling/features/calendar/screens/day_route_screen.dart';
import 'package:scheduling/features/clients/screens/history_screen.dart';
import 'package:scheduling/features/dashboard/screens/dashboard_screen.dart';
import 'package:scheduling/features/employees/domain/models/invite_preview.dart';
import 'package:scheduling/features/settings/screens/my_details_screen.dart';
import 'package:scheduling/features/settings/screens/settings_screen.dart';
import 'package:scheduling/routes/hub_shell.dart';

class AppRoutes {
  AppRoutes._();

  static const String login = '/login';
  static const String forgotPassword = '/forgot-password';
  static const String acceptInviteCode = '/accept-invite/code';
  static const String acceptInviteDetails = '/accept-invite/details';
  static const String mainCalendar = '/calendar';
  static const String employees = '/employees';
  static const String clients = '/clients';
  static const String history = '/history';
  static const String liveMap = '/live-map';
  static const String settings = '/settings';
  static const String myDetails = '/settings/my-details';
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

      case acceptInviteCode:
        // Args are optional: the sign-in prompt pushes it bare, the deep-link
        // dispatcher pushes it with a code to prefill.
        final args = settings.arguments as AcceptInviteCodeArgs?;
        return AppPageRoute(
          settings: settings,
          builder: (_) =>
              AcceptInviteCodeScreen(initialCode: args?.initialCode ?? ''),
        );

      case acceptInviteDetails:
        // Only ever reached from the code screen, which has already resolved
        // the preview — there is no way to build this screen without one.
        final args = settings.arguments! as AcceptInviteDetailsArgs;
        return AppPageRoute(
          settings: settings,
          builder: (_) => AcceptInviteDetailsScreen(
            code: args.code,
            preview: args.preview,
          ),
        );

      case dashboard:
        final args = settings.arguments as DashboardArgs?;
        return AppPageRoute(
          settings: settings,
          // This is an admin-only screen, so default isAdmin to true if it's
          // pushed without args.
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
        // This is the post-login entry point — always builds a fresh shell
        // via pushReplacement.
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
          HubTab.employees,
          isAdmin: args.isAdmin,
          employeeId: args.employeeId,
        );

      case clients:
        final args = settings.arguments! as ClientsListArgs;
        return _hubRoute(
          settings,
          HubTab.clients,
          isAdmin: args.isAdmin,
          employeeId: args.employeeId,
        );

      case history:
        final args = settings.arguments! as HistoryArgs;
        return AppPageRoute(
          settings: settings,
          builder: (_) => HistoryScreen(
            isAdmin: args.isAdmin,
            employeeId: args.employeeId,
          ),
        );

      case liveMap:
        final args = settings.arguments! as MainCalendarArgs;
        return _hubRoute(
          settings,
          HubTab.liveMap,
          isAdmin: args.isAdmin,
          employeeId: args.employeeId,
        );

      case AppRoutes.myDetails:
        return AppPageRoute(
          settings: settings,
          builder: (_) => const MyDetailsScreen(),
        );

      case AppRoutes.settings:
        // Settings is only reachable post-login, so args are always present.
        final args = settings.arguments! as SettingsArgs;
        return AppPageRoute(
          settings: settings,
          builder: (_) => SettingsScreen(
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

  /// Route for any non-calendar hub tab — redirects into a tab switch if a
  /// shell is already live, otherwise opens a fresh one.
  static Route<dynamic> _hubRoute(
    RouteSettings routeSettings,
    HubTab destination, {
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
        initialTab: destination,
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

class AcceptInviteCodeArgs {
  const AcceptInviteCodeArgs({this.initialCode = ''});

  /// Prefills the boxes. Never persisted — it rides the navigator stack only.
  final String initialCode;
}

class AcceptInviteDetailsArgs {
  const AcceptInviteDetailsArgs({required this.code, required this.preview});

  /// Already normalized, so the details screen never re-asks for it.
  final String code;
  final InvitePreview preview;
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

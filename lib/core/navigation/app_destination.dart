import 'package:scheduling/routes/app_routes.dart';

/// Anything the end drawer can navigate to. Sealed so switches stay
/// exhaustive; `implements Enum` so only enums can implement it and
/// `.name` works on the union type.
sealed class AppDestination implements Enum {}

/// The four persistent hub tabs (IndexedStack panes). The stack index is
/// [HubTab.index] — safe, because the stack children iterate
/// [HubTab.values], the same list the index derives from.
enum HubTab implements AppDestination { calendar, clients, employees, liveMap }

/// Destinations that push a plain route above the hub.
/// P5 adds `myDetails`; P6 adds `timeOff` — one member, one
/// [destinationRoute] case and one drawer row each, no restructure.
enum PushedDestination implements AppDestination {
  dayRoute,
  history,
  dashboard,
  settings,
}

/// Every destination, in tab-then-pushed order.
const List<AppDestination> allDestinations = [
  ...HubTab.values,
  ...PushedDestination.values,
];

/// Route + typed args for a destination — the one mapping every nav surface
/// uses, so the drawer and outside-shell navigation cannot drift.
({String route, Object arguments}) destinationRoute(
  AppDestination destination, {
  required bool isAdmin,
  required String employeeId,
  String userName = '',
  String userEmail = '',
}) => switch (destination) {
  HubTab.calendar => (
    route: AppRoutes.mainCalendar,
    arguments: MainCalendarArgs(isAdmin: isAdmin, employeeId: employeeId),
  ),
  HubTab.clients => (
    route: AppRoutes.clients,
    arguments: ClientsListArgs(isAdmin: isAdmin, employeeId: employeeId),
  ),
  HubTab.employees => (
    route: AppRoutes.employees,
    arguments: MainCalendarArgs(isAdmin: isAdmin, employeeId: employeeId),
  ),
  HubTab.liveMap => (
    route: AppRoutes.liveMap,
    arguments: MainCalendarArgs(isAdmin: isAdmin, employeeId: employeeId),
  ),
  PushedDestination.dayRoute => (
    route: AppRoutes.dayRoute,
    arguments: DayRouteArgs(isAdmin: isAdmin, employeeId: employeeId),
  ),
  PushedDestination.history => (
    route: AppRoutes.history,
    arguments: HistoryArgs(isAdmin: isAdmin, employeeId: employeeId),
  ),
  PushedDestination.dashboard => (
    route: AppRoutes.dashboard,
    arguments: DashboardArgs(
      isAdmin: isAdmin,
      employeeId: employeeId,
      userName: userName.isEmpty ? null : userName,
      email: userEmail.isEmpty ? null : userEmail,
    ),
  ),
  PushedDestination.settings => (
    route: AppRoutes.settings,
    arguments: SettingsArgs(
      name: userName,
      email: userEmail,
      role: isAdmin ? 'admin' : 'employee',
      employeeId: employeeId,
    ),
  ),
};

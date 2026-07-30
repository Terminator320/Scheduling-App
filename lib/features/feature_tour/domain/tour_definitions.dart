import 'package:scheduling/core/navigation/app_destination.dart';
import 'package:scheduling/features/feature_tour/domain/tour_step_id.dart';

/// The showcaseview scope name for a tab. Each tab needs its own scope
/// because the hub's IndexedStack keeps every tab mounted — a shared scope
/// would mix hidden tabs' targets into the visible tour.
String tourScopeName(AppDestination destination) => 'tour_${destination.name}';

/// Ordered step catalog for a destination and role. Clients, Employees,
/// History and LiveMap are admin-only, so their employee catalogs are empty.
/// A destination that mounts no tour host returns an empty catalog.
List<TourStepId> tourStepsFor(
  AppDestination destination, {
  required bool isAdmin,
}) => switch (destination) {
  HubTab.calendar => [
    TourStepId.calendarGrid,
    TourStepId.calendarDayList,
    if (isAdmin) TourStepId.calendarAddAppointment,
    TourStepId.calendarDayRoute,
  ],
  HubTab.clients => [
    if (isAdmin) ...[TourStepId.clientsSearch, TourStepId.clientsAdd],
  ],
  HubTab.employees => [
    if (isAdmin) ...[TourStepId.employeesSearch, TourStepId.employeesAdd],
  ],
  PushedDestination.history => [if (isAdmin) TourStepId.historySearch],
  HubTab.liveMap => [
    if (isAdmin) ...[TourStepId.liveMapRoster, TourStepId.liveMapRecenter],
  ],
  PushedDestination.settings => [
    TourStepId.settingsAppearance,
    TourStepId.settingsNotifications,
    TourStepId.settingsReplay,
  ],
  PushedDestination.dayRoute => const [],
  PushedDestination.dashboard => const [],
};

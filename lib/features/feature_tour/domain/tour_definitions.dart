import 'package:scheduling/core/navigation/app_destination.dart';
import 'package:scheduling/core/navigation/hub_shell_scope.dart';
import 'package:scheduling/features/feature_tour/domain/tour_step_id.dart';

/// The showcaseview scope name for a tab. Each tab needs its own scope
/// because the hub's IndexedStack keeps every tab mounted — a shared scope
/// would mix hidden tabs' targets into the visible tour.
String tourScopeName(AdaptiveDestination tab) => 'tour_${tab.name}';

/// Ordered step catalog for a tab and role. Clients, Employees, History, and
/// LiveMap are admin-only tabs, so their employee catalogs are empty.
List<TourStepId> tourStepsFor(
  AdaptiveDestination tab, {
  required bool isAdmin,
}) => switch (tab) {
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
};

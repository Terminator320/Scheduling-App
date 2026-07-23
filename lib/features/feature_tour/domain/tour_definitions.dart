import 'package:scheduling/core/layout/adaptive_shell.dart';
import 'package:scheduling/features/feature_tour/domain/tour_step_id.dart';

/// The showcaseview scope name for a tab — each tab needs its own scope
/// since the hub's IndexedStack keeps every tab mounted, so a shared scope
/// would mix hidden tabs' targets into the visible tour.
String tourScopeName(AdaptiveDestination tab) => 'tour_${tab.name}';

/// Ordered step catalog for a tab and role; Clients/Employees/History/LiveMap
/// are admin-only tabs, so their employee catalogs are empty.
List<TourStepId> tourStepsFor(
  AdaptiveDestination tab, {
  required bool isAdmin,
}) => switch (tab) {
  AdaptiveDestination.calendar => [
    TourStepId.calendarGrid,
    TourStepId.calendarDayList,
    if (isAdmin) TourStepId.calendarAddAppointment,
    TourStepId.calendarDayRoute,
  ],
  AdaptiveDestination.clients => [
    if (isAdmin) ...[TourStepId.clientsSearch, TourStepId.clientsAdd],
  ],
  AdaptiveDestination.employees => [
    if (isAdmin) ...[TourStepId.employeesSearch, TourStepId.employeesAdd],
  ],
  AdaptiveDestination.history => [if (isAdmin) TourStepId.historySearch],
  AdaptiveDestination.liveMap => [
    if (isAdmin) ...[TourStepId.liveMapRoster, TourStepId.liveMapRecenter],
  ],
  AdaptiveDestination.settings => [
    TourStepId.settingsAppearance,
    TourStepId.settingsNotifications,
    TourStepId.settingsReplay,
  ],
};

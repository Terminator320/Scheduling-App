import 'package:scheduling/core/navigation/app_destination.dart';
import 'package:scheduling/features/feature_tour/domain/tour_scope.dart';
import 'package:scheduling/features/feature_tour/domain/tour_step_id.dart';

/// Ordered step catalog for a scope and role. Clients, Employees, History,
/// LiveMap, Dashboard and the three create-flow sheets are admin-only, so
/// their employee catalogs are empty. A scope that mounts no tour host
/// returns an empty catalog.
List<TourStepId> tourStepsFor(TourScope scope, {required bool isAdmin}) =>
    switch (scope) {
      DestinationTour(:final destination) => _destinationSteps(
        destination,
        isAdmin: isAdmin,
      ),
      FormTour(:final form) => _formSteps(form, isAdmin: isAdmin),
    };

List<TourStepId> _destinationSteps(
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
  PushedDestination.dashboard => [
    if (isAdmin) ...[
      TourStepId.dashboardHero,
      TourStepId.dashboardUpcoming,
      TourStepId.dashboardWorkload,
      TourStepId.dashboardAttention,
    ],
  ],
};

/// The create-flow walkthroughs. Every one of these sheets is reachable only
/// from an admin surface, so the employee catalogs are empty.
List<TourStepId> _formSteps(TourForm form, {required bool isAdmin}) =>
    switch (form) {
      TourForm.addAppointment => const [],
      TourForm.addClient => const [],
      TourForm.invitePerson => const [],
    };

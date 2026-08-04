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
    // Portrait only — the handle doesn't exist in the split layout, so
    // isTargetRendered drops this step there.
    TourStepId.calendarCollapse,
    if (isAdmin) TourStepId.calendarAddAppointment,
    TourStepId.calendarDayRoute,
  ],
  HubTab.clients => [
    if (isAdmin) ...[
      TourStepId.clientsSearch,
      TourStepId.clientsFilter,
      TourStepId.clientsAdd,
      TourStepId.clientsRow,
    ],
  ],
  HubTab.employees => [
    if (isAdmin) ...[
      TourStepId.employeesSearch,
      TourStepId.employeesAdd,
      TourStepId.employeesRow,
    ],
  ],
  PushedDestination.history => [
    if (isAdmin) ...[
      TourStepId.historySearch,
      TourStepId.historyFilter,
      TourStepId.historyRow,
    ],
  ],
  HubTab.liveMap => [
    if (isAdmin) ...[TourStepId.liveMapRoster, TourStepId.liveMapRecenter],
  ],
  PushedDestination.settings => [
    TourStepId.settingsAppearance,
    TourStepId.settingsNotifications,
    TourStepId.settingsReplay,
  ],
  // Employees reach the day route too, so this catalog isn't admin-gated —
  // only the picker step is, since an employee sees just their own route.
  PushedDestination.dayRoute => [
    TourStepId.dayRouteDaySwitcher,
    if (isAdmin) TourStepId.dayRouteEmployee,
    TourStepId.dayRouteStops,
    TourStepId.dayRouteNavigate,
  ],
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
      TourForm.addAppointment => [
        if (isAdmin) ...[
          TourStepId.apptTemplates,
          TourStepId.apptClient,
          TourStepId.apptCrew,
          TourStepId.apptSchedule,
          TourStepId.apptDetails,
          TourStepId.apptSave,
        ],
      ],
      TourForm.addClient => [
        if (isAdmin) ...[
          TourStepId.clientWho,
          TourStepId.clientReach,
          TourStepId.clientSite,
          TourStepId.clientSave,
        ],
      ],
      TourForm.invitePerson => [
        if (isAdmin) ...[
          TourStepId.personDetails,
          // Before personAccess on purpose: the job title grants nothing and
          // the access toggle is the real switch, so the tour has to separate
          // them in that order.
          TourStepId.personJobTitle,
          TourStepId.personColour,
          TourStepId.personAccess,
          TourStepId.personCreate,
        ],
      ],
    };

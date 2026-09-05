import 'package:scheduling/features/feature_tour/domain/tour_step_id.dart';

/// The steps each tour scope carried at 1.57, keyed by `TourScope.storageKey`,
/// as the union across both roles.
///
/// FROZEN. It exists only to seed `tour_seen_steps` from the per-scope
/// `tour_seen_tabs` flags a device installed before this release already
/// holds: a device that saw a scope saw everything that scope could show it,
/// so every id here counts as seen. A step added after 1.57 must NOT be added
/// here, or it is marked seen on upgrade and no existing device ever sees it.
const Map<String, List<TourStepId>> kLegacyTourSteps = {
  'calendar': [
    TourStepId.calendarGrid,
    TourStepId.calendarDayList,
    TourStepId.calendarCollapse,
    TourStepId.calendarAddAppointment,
    TourStepId.calendarDayRoute,
  ],
  'clients': [
    TourStepId.clientsSearch,
    TourStepId.clientsFilter,
    TourStepId.clientsAdd,
    TourStepId.clientsRow,
  ],
  'employees': [
    TourStepId.employeesSearch,
    TourStepId.employeesAdd,
    TourStepId.employeesRow,
  ],
  'liveMap': [TourStepId.liveMapRoster, TourStepId.liveMapRecenter],
  'history': [
    TourStepId.historySearch,
    TourStepId.historyFilter,
    TourStepId.historyRow,
  ],
  'settings': [
    TourStepId.settingsAppearance,
    TourStepId.settingsNotifications,
    TourStepId.settingsReplay,
  ],
  'dayRoute': [
    TourStepId.dayRouteDaySwitcher,
    TourStepId.dayRouteEmployee,
    TourStepId.dayRouteStops,
    TourStepId.dayRouteNavigate,
  ],
  'dashboard': [
    TourStepId.dashboardHero,
    TourStepId.dashboardUpcoming,
    TourStepId.dashboardWorkload,
    TourStepId.dashboardAttention,
  ],
  'sheet_addAppointment': [
    TourStepId.apptTemplates,
    TourStepId.apptClient,
    TourStepId.apptCrew,
    TourStepId.apptSchedule,
    TourStepId.apptDetails,
    TourStepId.apptSave,
  ],
  'sheet_addClient': [
    TourStepId.clientWho,
    TourStepId.clientReach,
    TourStepId.clientSite,
    TourStepId.clientSave,
  ],
  'sheet_invitePerson': [
    TourStepId.personDetails,
    TourStepId.personJobTitle,
    TourStepId.personColour,
    TourStepId.personCreate,
  ],
};

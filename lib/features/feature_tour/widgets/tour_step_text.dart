import 'package:scheduling/features/feature_tour/domain/tour_step_id.dart';
import 'package:scheduling/l10n/l10n.dart';

/// Localized title + description for a tour step.
({String title, String description}) tourStepText(
  AppLocalizations l,
  TourStepId id,
) => switch (id) {
  TourStepId.calendarGrid => (
    title: l.tour_calendarGridTitle,
    description: l.tour_calendarGridDesc,
  ),
  TourStepId.calendarDayList => (
    title: l.tour_calendarDayListTitle,
    description: l.tour_calendarDayListDesc,
  ),
  TourStepId.calendarAddAppointment => (
    title: l.tour_calendarAddTitle,
    description: l.tour_calendarAddDesc,
  ),
  TourStepId.calendarDayRoute => (
    title: l.tour_calendarDayRouteTitle,
    description: l.tour_calendarDayRouteDesc,
  ),
  TourStepId.clientsSearch => (
    title: l.tour_clientsSearchTitle,
    description: l.tour_clientsSearchDesc,
  ),
  TourStepId.clientsAdd => (
    title: l.tour_clientsAddTitle,
    description: l.tour_clientsAddDesc,
  ),
  TourStepId.employeesSearch => (
    title: l.tour_employeesSearchTitle,
    description: l.tour_employeesSearchDesc,
  ),
  TourStepId.employeesAdd => (
    title: l.tour_employeesAddTitle,
    description: l.tour_employeesAddDesc,
  ),
  TourStepId.historySearch => (
    title: l.tour_historySearchTitle,
    description: l.tour_historySearchDesc,
  ),
  TourStepId.liveMapRoster => (
    title: l.tour_liveMapRosterTitle,
    description: l.tour_liveMapRosterDesc,
  ),
  TourStepId.liveMapRecenter => (
    title: l.tour_liveMapRecenterTitle,
    description: l.tour_liveMapRecenterDesc,
  ),
  TourStepId.settingsAppearance => (
    title: l.tour_settingsAppearanceTitle,
    description: l.tour_settingsAppearanceDesc,
  ),
  TourStepId.settingsNotifications => (
    title: l.tour_settingsNotificationsTitle,
    description: l.tour_settingsNotificationsDesc,
  ),
  TourStepId.settingsReplay => (
    title: l.tour_settingsReplayTitle,
    description: l.tour_settingsReplayDesc,
  ),
};

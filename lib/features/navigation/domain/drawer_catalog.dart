import 'dart:ui' show Color;

import 'package:scheduling/core/navigation/app_destination.dart';
import 'package:scheduling/l10n/l10n.dart';

/// One labelled block of drawer rows.
typedef DrawerGroup = ({
  String Function(AppLocalizations) title,
  List<AppDestination> rows,
});

/// Grouped drawer rows for a role, grouped by WHEN you would reach for
/// them, not by object type. Employees get TODAY + ACCOUNT only.
List<DrawerGroup> drawerGroups({required bool isAdmin}) => [
  (
    title: (l10n) => l10n.nav_groupToday,
    rows: [
      HubTab.calendar,
      PushedDestination.dayRoute,
      if (isAdmin) HubTab.liveMap,
    ],
  ),
  if (isAdmin)
    (
      title: (l10n) => l10n.nav_groupPeople,
      // PushedDestination.timeOff joins here in P6.
      rows: [HubTab.employees, HubTab.clients],
    ),
  if (isAdmin)
    (
      title: (l10n) => l10n.nav_groupBusiness,
      rows: [PushedDestination.dashboard, PushedDestination.history],
    ),
  (
    title: (l10n) => l10n.nav_groupAccount,
    // PushedDestination.myDetails joins here in P5.
    rows: [PushedDestination.settings],
  ),
];

/// Localized row label. Kept out of [AppDestination] so the destination enum
/// stays presentation-free.
String drawerRowLabel(AppLocalizations l10n, AppDestination destination) =>
    switch (destination) {
      HubTab.calendar => l10n.common_calendar,
      HubTab.clients => l10n.common_clients,
      HubTab.employees => l10n.nav_team,
      HubTab.liveMap => l10n.common_liveMap,
      PushedDestination.dayRoute => l10n.nav_dayRoute,
      PushedDestination.history => l10n.common_history,
      PushedDestination.dashboard => l10n.nav_dashboard,
      PushedDestination.settings => l10n.common_settings,
    };

/// The row's colour square. These are crew-palette hues used as decoration,
/// so a call site must resolve them through `crewColorOf` to get the dark
/// lift — never paint the stored value directly.
Color drawerDotColor(AppDestination destination) => switch (destination) {
  HubTab.calendar => const Color(0xFF005CC8),
  PushedDestination.dayRoute => const Color(0xFFD61F3A),
  HubTab.liveMap => const Color(0xFF00A5C4),
  HubTab.employees => const Color(0xFF0E9B6E),
  HubTab.clients => const Color(0xFF7A3FF2),
  PushedDestination.dashboard => const Color(0xFFE08A00),
  PushedDestination.history => const Color(0xFFC43F8E),
  PushedDestination.settings => const Color(0xFF5A6B85),
};

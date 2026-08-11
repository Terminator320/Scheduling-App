import 'package:flutter/material.dart' show Color, IconData, Icons;

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
    // My details is NOT a drawer row: P5 landed it inside Settings, which is
    // where its two grants (own emergency contact, self-service availability)
    // sit beside the rest of a person's own preferences.
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

/// The row's icon. Seven of these are the icons the pre-redesign drawer used
/// before P1 replaced them with bare colour squares; `dayRoute` is the one
/// row that had no predecessor.
///
/// This is a second exhaustive switch beside [drawerDotColor] rather than a
/// record returned from one, because the two answer different questions and a
/// row's icon is stable while its hue is decoration. A new destination is a
/// compile error in both.
IconData drawerRowIcon(AppDestination destination) => switch (destination) {
  HubTab.calendar => Icons.calendar_today_rounded,
  PushedDestination.dayRoute => Icons.route_rounded,
  HubTab.liveMap => Icons.map_rounded,
  HubTab.employees => Icons.badge_rounded,
  HubTab.clients => Icons.people_rounded,
  PushedDestination.dashboard => Icons.insights_rounded,
  PushedDestination.history => Icons.history_rounded,
  PushedDestination.settings => Icons.settings_rounded,
};

/// The row's colour. These are crew-palette hues used as decoration,
/// so a call site must resolve them through `crewColorOf` to get the dark
/// lift — never paint the stored value directly.
///
/// Deliberately literals rather than `AppColors.crewPalette[n]`, even though
/// each one matches an entry exactly: that list is the pool employee colours
/// are ASSIGNED from, and indexing it here would mean reordering it (a normal
/// change for staff colours) silently repaints the whole nav drawer. Same
/// hues, no coupling.
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

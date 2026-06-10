import 'package:flutter/material.dart';
import 'package:scheduling/core/layout/breakpoints.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/routes/app_routes.dart';

enum AdaptiveDestination { calendar, clients, employees, history, settings }

/// Route + typed args for a destination — shared by the nav rail and the
/// settings drawer so the two nav surfaces can't drift.
({String route, Object arguments}) destinationRoute(
  AdaptiveDestination destination, {
  required bool isAdmin,
  required String employeeId,
  String userName = '',
  String userEmail = '',
}) => switch (destination) {
  AdaptiveDestination.calendar => (
    route: AppRoutes.mainCalendar,
    arguments: MainCalendarArgs(isAdmin: isAdmin, employeeId: employeeId),
  ),
  AdaptiveDestination.clients => (
    route: AppRoutes.clients,
    arguments: ClientsListArgs(isAdmin: isAdmin, employeeId: employeeId),
  ),
  AdaptiveDestination.employees => (
    route: AppRoutes.employees,
    arguments: MainCalendarArgs(isAdmin: isAdmin, employeeId: employeeId),
  ),
  AdaptiveDestination.history => (
    route: AppRoutes.history,
    arguments: HistoryArgs(isAdmin: isAdmin, employeeId: employeeId),
  ),
  AdaptiveDestination.settings => (
    route: AppRoutes.settings,
    arguments: SettingsArgs(
      name: userName,
      email: userEmail,
      role: isAdmin ? 'admin' : 'employee',
      employeeId: employeeId,
    ),
  ),
};

/// Replaces the current route with [destination] and its typed args — the
/// single nav action shared by the rail and every screen's back button, so
/// they can't drift from [destinationRoute].
void navigateToDestination(
  BuildContext context,
  AdaptiveDestination destination, {
  required bool isAdmin,
  required String employeeId,
  String userName = '',
  String userEmail = '',
}) {
  final target = destinationRoute(
    destination,
    isAdmin: isAdmin,
    employeeId: employeeId,
    userName: userName,
    userEmail: userEmail,
  );
  Navigator.pushReplacementNamed(
    context,
    target.route,
    arguments: target.arguments,
  );
}

class AdaptiveShell extends StatelessWidget {
  const AdaptiveShell({
    required this.currentDestination,
    required this.isAdmin,
    required this.employeeId,
    required this.child,
    super.key,
    this.userName,
    this.userEmail,
  });

  final AdaptiveDestination currentDestination;
  final bool isAdmin;
  final String employeeId;
  final Widget child;
  final String? userName;
  final String? userEmail;

  @override
  Widget build(BuildContext context) {
    if (!context.isSplitLayout) return child;

    final destinations = _destinationsFor(context, isAdmin);
    final selectedIndex = destinations
        .indexWhere((d) => d.destination == currentDestination)
        .clamp(0, destinations.length - 1);

    final scheme = Theme.of(context).colorScheme;
    // A landscape phone is short: stacking a label under every icon can
    // overflow the rail, so only label the selected destination there.
    final isShort = MediaQuery.sizeOf(context).height < 520;

    return Row(
      children: [
        NavigationRail(
          backgroundColor: scheme.surfaceContainerLow,
          extended: context.isExpanded,
          selectedIndex: selectedIndex,
          labelType: context.isExpanded
              ? NavigationRailLabelType.none
              : (isShort
                    ? NavigationRailLabelType.selected
                    : NavigationRailLabelType.all),
          onDestinationSelected: (index) =>
              _onSelect(context, destinations[index].destination),
          destinations: [
            for (final d in destinations)
              NavigationRailDestination(
                icon: Icon(d.icon),
                selectedIcon: Icon(d.selectedIcon),
                label: Text(d.label),
              ),
          ],
        ),
        const VerticalDivider(width: 1, thickness: 1),
        Expanded(child: child),
      ],
    );
  }

  void _onSelect(BuildContext context, AdaptiveDestination destination) {
    if (destination == currentDestination) return;
    navigateToDestination(
      context,
      destination,
      isAdmin: isAdmin,
      employeeId: employeeId,
      userName: userName ?? '',
      userEmail: userEmail ?? '',
    );
  }

  List<_RailEntry> _destinationsFor(BuildContext context, bool isAdmin) {
    final l = context.l10n;
    return [
      _RailEntry(
        destination: AdaptiveDestination.calendar,
        icon: Icons.calendar_today_outlined,
        selectedIcon: Icons.calendar_today_rounded,
        label: l.common_calendar,
      ),
      if (isAdmin) ...[
        _RailEntry(
          destination: AdaptiveDestination.clients,
          icon: Icons.people_outline_rounded,
          selectedIcon: Icons.people_rounded,
          label: l.common_clients,
        ),
        _RailEntry(
          destination: AdaptiveDestination.employees,
          icon: Icons.badge_outlined,
          selectedIcon: Icons.badge_rounded,
          label: l.common_employees,
        ),
        _RailEntry(
          destination: AdaptiveDestination.history,
          icon: Icons.history_rounded,
          selectedIcon: Icons.history_rounded,
          label: l.common_history,
        ),
      ],
      _RailEntry(
        destination: AdaptiveDestination.settings,
        icon: Icons.settings_outlined,
        selectedIcon: Icons.settings_rounded,
        label: l.common_settings,
      ),
    ];
  }
}

class _RailEntry {
  const _RailEntry({
    required this.destination,
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final AdaptiveDestination destination;
  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

import 'package:flutter/material.dart';
import 'package:scheduling/core/layout/breakpoints.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/routes/app_routes.dart';

enum AdaptiveDestination {
  calendar,
  clients,
  employees,
  history,
  liveMap,
  settings,
}

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
  AdaptiveDestination.liveMap => (
    route: AppRoutes.liveMap,
    arguments: MainCalendarArgs(isAdmin: isAdmin, employeeId: employeeId),
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

/// Tab-switch contract that lets core drive navigation without depending on
/// routes. userName/userEmail stay sticky on the shell side.
// One-method contract by design: an abstract class (vs a callback type)
// keeps the InheritedWidget field debuggable and the signature named.
// ignore: one_member_abstracts
abstract interface class HubTabSelector {
  /// Switches the visible hub tab, refreshing the identity args the hub
  /// screens are constructed with.
  void select(
    AdaptiveDestination destination, {
    required bool isAdmin,
    required String employeeId,
    String userName,
    String userEmail,
  });
}

/// Lets shell descendants — the nav rail, hub back buttons — reach the
/// enclosing hub shell to switch tabs. [current] is carried along so
/// dependents rebuild when the selection changes.
class HubShellScope extends InheritedWidget {
  const HubShellScope({
    required this.shell,
    required this.current,
    required super.child,
    super.key,
  });

  final HubTabSelector shell;
  final AdaptiveDestination current;

  /// The enclosing shell, or null when hosted outside one (standalone route,
  /// tests). Doesn't create a rebuild dependency — meant for one-shot navigation.
  static HubTabSelector? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<HubShellScope>()?.shell;

  /// The currently visible hub tab as a build dependency (null outside a
  /// shell). Used by FeatureTourHost to start or stop a tab's tour.
  static AdaptiveDestination? currentOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<HubShellScope>()?.current;

  /// One-shot read of the current tab (no rebuild dependency) — safe outside
  /// build, e.g. in a post-frame callback.
  static AdaptiveDestination? readCurrentOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<HubShellScope>()?.current;

  @override
  bool updateShouldNotify(HubShellScope oldWidget) =>
      current != oldWidget.current || shell != oldWidget.shell;
}

/// The single nav action for switching destinations, so the rail and back
/// buttons can't drift out of sync. Inside the shell it's a tab switch;
/// outside it, it's a route replacement.
void navigateToDestination(
  BuildContext context,
  AdaptiveDestination destination, {
  required bool isAdmin,
  required String employeeId,
  String userName = '',
  String userEmail = '',
}) {
  final shell = HubShellScope.maybeOf(context);
  if (shell != null) {
    shell.select(
      destination,
      isAdmin: isAdmin,
      employeeId: employeeId,
      userName: userName,
      userEmail: userEmail,
    );
    return;
  }
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
        // NavigationRail can overflow on short viewports, so make it scrollable with its own PrimaryScrollController to avoid sharing with content.
        PrimaryScrollController.none(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: NavigationRail(
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
                ),
              ),
            ),
          ),
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
        _RailEntry(
          destination: AdaptiveDestination.liveMap,
          icon: Icons.map_outlined,
          selectedIcon: Icons.map_rounded,
          label: l.common_liveMap,
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

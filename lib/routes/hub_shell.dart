import 'package:flutter/material.dart';

import 'package:scheduling/core/adaptive/adaptive.dart';
import 'package:scheduling/core/layout/adaptive_shell.dart';
import 'package:scheduling/core/layout/primary_scroll_scope.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/features/calendar/screens/main_calendar_screen.dart';
import 'package:scheduling/features/clients/screens/clients_screen.dart';
import 'package:scheduling/features/clients/screens/history_screen.dart';
import 'package:scheduling/features/employees/screens/employees_screen.dart';
import 'package:scheduling/features/presence/screens/live_map_screen.dart';
import 'package:scheduling/features/settings/screens/settings_screen.dart';

/// Post-login shell with six tab destinations, all kept alive in an
/// IndexedStack. Android back goes to calendar, unless we're already there.
class HubShell extends StatefulWidget {
  const HubShell({
    required this.isAdmin,
    required this.employeeId,
    this.initialDestination = AdaptiveDestination.calendar,
    this.userName = '',
    this.userEmail = '',
    super.key,
    @visibleForTesting this.screenBuilder,
  });

  final bool isAdmin;
  final String employeeId;

  /// Initial tab (calendar on login, or another destination if deep-linked).
  final AdaptiveDestination initialDestination;

  /// Initial identity shown on settings tab (sticky).
  final String userName;
  final String userEmail;

  /// Lets tests swap in stub screens instead of the real ones.
  final Widget Function(AdaptiveDestination destination)? screenBuilder;

  /// The most recently active shell — used to redirect hub-route pushes into
  /// tab switches.
  static HubShellState? get liveState => HubShellState._live;

  @override
  State<HubShell> createState() => HubShellState();
}

class HubShellState extends State<HubShell> implements HubTabSelector {
  static HubShellState? _live;

  late bool _isAdmin = widget.isAdmin;
  late String _employeeId = widget.employeeId;
  late String _userName = widget.userName;
  late String _userEmail = widget.userEmail;
  late AdaptiveDestination _current = widget.initialDestination;

  /// Destinations built so far (lazy-built, kept alive by IndexedStack).
  late final Set<AdaptiveDestination> _built = {widget.initialDestination};

  /// The tab currently shown.
  AdaptiveDestination get currentDestination => _current;

  /// The live role, used by deep links to gate admin-only edit/cancel/delete
  /// controls.
  bool get isAdmin => _isAdmin;

  @override
  void initState() {
    super.initState();
    _live = this;
  }

  @override
  void dispose() {
    if (_live == this) _live = null;
    super.dispose();
  }

  @override
  void select(
    AdaptiveDestination destination, {
    required bool isAdmin,
    required String employeeId,
    String userName = '',
    String userEmail = '',
  }) {
    if (!mounted) return;
    setState(() {
      _isAdmin = isAdmin;
      if (employeeId.isNotEmpty) _employeeId = employeeId;
      if (userName.isNotEmpty) _userName = userName;
      if (userEmail.isNotEmpty) _userEmail = userEmail;
      _current = destination;
      _built.add(destination);
    });
  }

  /// Switch to calendar, preserving identity for deep-linked appointment sheets.
  void showCalendar() {
    select(
      AdaptiveDestination.calendar,
      isAdmin: _isAdmin,
      employeeId: _employeeId,
    );
  }

  void _handlePop(bool didPop, Object? result) {
    if (didPop) return;
    // System back on non-calendar tab → calendar (like the app bar).
    select(
      AdaptiveDestination.calendar,
      isAdmin: _isAdmin,
      employeeId: _employeeId,
    );
  }

  // iOS left-edge swipe for non-calendar tabs (no pushed route in IndexedStack).
  static const double _kBackSwipeEdge = 24;
  static const double _kBackSwipeMinVelocity = 250;
  bool _backSwipeArmed = false;
  double _backSwipeDx = 0;

  Widget _withBackSwipe(Widget child) {
    return GestureDetector(
      // Translucent to pass vertical drags to tab scrollables.
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: (details) {
        _backSwipeArmed = details.globalPosition.dx <= _kBackSwipeEdge;
        _backSwipeDx = 0;
      },
      onHorizontalDragUpdate: (details) {
        if (_backSwipeArmed) _backSwipeDx += details.delta.dx;
      },
      onHorizontalDragEnd: (details) {
        if (!_backSwipeArmed) return;
        _backSwipeArmed = false;
        final width = MediaQuery.of(context).size.width;
        final velocity = details.primaryVelocity ?? 0;
        // Rightward fling or drag > 1/3 width → back.
        if (velocity > _kBackSwipeMinVelocity || _backSwipeDx > width * 0.35) {
          showCalendar();
        }
      },
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    _refreshScreenCache();
    return HubShellScope(
      shell: this,
      current: _current,
      child: PopScope(
        canPop: _current == AdaptiveDestination.calendar,
        onPopInvokedWithResult: _handlePop,
        child: IndexedStack(
          index: _current.index,
          children: [
            for (final destination in AdaptiveDestination.values)
              if (_built.contains(destination))
                // Mute animations on hidden tabs, and pin viewInsets so they
                // don't cause rebuild churn while hidden.
                TickerMode(
                  enabled: destination == _current,
                  child: _TabViewInsets(
                    active: destination == _current,
                    // Each tab needs its own PrimaryScrollController.
                    child: PrimaryScrollScope(
                      // Fade in new tabs, unless reduced motion is on — then
                      // just swap instantly.
                      child: AnimatedOpacity(
                        opacity: destination == _current ? 1 : 0,
                        duration: MediaQuery.disableAnimationsOf(context)
                            ? Duration.zero
                            : AppMotion.tabSwitch,
                        curve: Curves.easeInOut,
                        // iOS edge-swipe for non-calendar tabs (calendar owns week-swipe).
                        child:
                            destination == AdaptiveDestination.calendar ||
                                !context.isCupertino
                            ? _cachedScreenFor(destination)
                            : _withBackSwipe(_cachedScreenFor(destination)),
                      ),
                    ),
                  ),
                )
              else
                const SizedBox.shrink(),
          ],
        ),
      ),
    );
  }

  /// Caches screens so unchanged tabs skip a rebuild — cleared whenever
  /// identity changes.
  final Map<AdaptiveDestination, Widget> _screenCache = {};
  ({bool isAdmin, String employeeId, String userName, String userEmail})?
  _screenCacheIdentity;

  /// Clear cache when identity args change (structural compare).
  void _refreshScreenCache() {
    final identity = (
      isAdmin: _isAdmin,
      employeeId: _employeeId,
      userName: _userName,
      userEmail: _userEmail,
    );
    if (identity != _screenCacheIdentity) {
      _screenCache.clear();
      _screenCacheIdentity = identity;
    }
  }

  Widget _cachedScreenFor(AdaptiveDestination destination) =>
      _screenCache.putIfAbsent(destination, () => _screenFor(destination));

  Widget _screenFor(AdaptiveDestination destination) {
    final builder = widget.screenBuilder;
    if (builder != null) return builder(destination);
    // Key on identity so in-place changes (e.g. admin upgrade) rebuild the screen.
    final key = ValueKey('hub-${destination.name}-$_isAdmin-$_employeeId');
    return switch (destination) {
      AdaptiveDestination.calendar => MainCalendar(
        key: key,
        isAdmin: _isAdmin,
        employeeId: _employeeId,
      ),
      AdaptiveDestination.clients => ListInformation(
        key: key,
        isAdmin: _isAdmin,
        employeeId: _employeeId,
      ),
      AdaptiveDestination.employees => AddEmployeePage(
        key: key,
        isAdmin: _isAdmin,
        employeeId: _employeeId,
      ),
      AdaptiveDestination.history => HistoryScreen(
        key: key,
        isAdmin: _isAdmin,
        employeeId: _employeeId,
      ),
      AdaptiveDestination.liveMap => LiveMapScreen(
        key: key,
        isAdmin: _isAdmin,
        employeeId: _employeeId,
      ),
      AdaptiveDestination.settings => SettingsScreen(
        key: key,
        name: _userName,
        email: _userEmail,
        role: _isAdmin ? 'admin' : 'employee',
        employeeId: _employeeId,
      ),
    };
  }
}

/// Pins hidden tab viewInsets to zero so hidden tabs don't cause rebuild
/// churn. This widget stays mounted whether its tab is active or not.
class _TabViewInsets extends StatelessWidget {
  const _TabViewInsets({required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final data = MediaQuery.of(context);
    return MediaQuery(
      data: active ? data : data.copyWith(viewInsets: EdgeInsets.zero),
      child: child,
    );
  }
}

/// Redirect named hub-route pushes into tab switches on the live HubShell.
class HubTabRedirectRoute extends PageRouteBuilder<void> {
  HubTabRedirectRoute({
    required RouteSettings settings,
    required this.destination,
    required this.isAdmin,
    required this.employeeId,
    this.userName = '',
    this.userEmail = '',
  }) : super(
         settings: settings,
         opaque: false,
         transitionDuration: Duration.zero,
         reverseTransitionDuration: Duration.zero,
         pageBuilder: (_, _, _) => const SizedBox.shrink(),
       );

  final AdaptiveDestination destination;
  final bool isAdmin;
  final String employeeId;
  final String userName;
  final String userEmail;

  @override
  TickerFuture didPush() {
    final ticker = super.didPush();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final nav = navigator;
      if (nav == null || !isActive) return;
      final shell = HubShellState._live;
      if (shell != null && shell.mounted) {
        shell.select(
          destination,
          isAdmin: isAdmin,
          employeeId: employeeId,
          userName: userName,
          userEmail: userEmail,
        );
        nav.removeRoute(this);
      } else {
        nav.replace<void>(
          oldRoute: this,
          newRoute: MaterialPageRoute<void>(
            settings: settings,
            builder: (_) => HubShell(
              initialDestination: destination,
              isAdmin: isAdmin,
              employeeId: employeeId,
              userName: userName,
              userEmail: userEmail,
            ),
          ),
        );
      }
    });
    return ticker;
  }
}

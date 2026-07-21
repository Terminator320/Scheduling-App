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

/// The persistent post-login shell (U1/P4). Hosts the six hub destinations
/// (calendar, clients, employees, history, live map, settings) in a single
/// route with an [IndexedStack], so switching tabs swaps an index instead of
/// replacing
/// routes: screens are built lazily on first visit and then kept alive (no
/// listener churn, page-1 refetch or skeleton flash), and the navigator
/// stack keeps a stable root that deep pushes (detail screens, sheets) stack
/// on top of.
///
/// A root [PopScope] maps Android system back (including predictive back) to
/// the same contract as the visible back chevron ([navigateToDestination]
/// resolves this shell through [HubShellScope]): back on a non-calendar tab
/// returns to the calendar tab; back on the calendar tab lets the pop
/// through (app exit).
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

  /// The tab shown first — the calendar for the post-login entry, or another
  /// destination when a named hub route is deep-opened with no live shell.
  final AdaptiveDestination initialDestination;

  /// Initial identity shown on the settings tab (sticky; see
  /// [HubTabSelector.select]).
  final String userName;
  final String userEmail;

  /// Test seam: replaces the real hub screens (which need Firebase) with
  /// lightweight stubs.
  final Widget Function(AdaptiveDestination destination)? screenBuilder;

  /// The most recently mounted shell, if any. Lets route-level code
  /// (`AppRoutes`) redirect a named hub-route push into a tab switch on the
  /// live shell instead of stacking a second standalone hub screen.
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

  /// Destinations visited so far: each is built lazily on first visit, then
  /// kept alive by the [IndexedStack].
  late final Set<AdaptiveDestination> _built = {widget.initialDestination};

  /// The tab currently shown.
  AdaptiveDestination get currentDestination => _current;

  /// The live role, kept current by [select]. Read by the notification/widget
  /// deep link so the appointment sheet opens with the right affordances —
  /// an employee must not be shown admin-only Edit/Cancel/Delete controls.
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

  /// Surfaces the calendar tab, preserving the current identity. Used by the
  /// notification deep-link so a tapped appointment's detail sheet opens over
  /// the calendar rather than whatever tab was last visited.
  void showCalendar() {
    select(
      AdaptiveDestination.calendar,
      isAdmin: _isAdmin,
      employeeId: _employeeId,
    );
  }

  void _handlePop(bool didPop, Object? result) {
    if (didPop) return;
    // System back on a non-calendar tab mirrors the top bar's back chevron:
    // return to the calendar tab instead of exiting the app.
    select(
      AdaptiveDestination.calendar,
      isAdmin: _isAdmin,
      employeeId: _employeeId,
    );
  }

  // iOS-style left-edge back-swipe for the non-calendar tabs. The tabs live in
  // an IndexedStack (no pushed route), so they'd otherwise lack the native
  // edge-swipe the pushed dashboard gets — a left-to-right edge swipe here
  // returns to the calendar tab, matching the top-bar chevron and system back.
  static const double _kBackSwipeEdge = 24;
  static const double _kBackSwipeMinVelocity = 250;
  bool _backSwipeArmed = false;
  double _backSwipeDx = 0;

  Widget _withBackSwipe(Widget child) {
    return GestureDetector(
      // Translucent so the tab's own scrollables still receive vertical drags;
      // only horizontal drags land here.
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
        // A rightward fling, or a drag past a third of the width, goes back.
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
                // Mute animations on hidden tabs; IndexedStack keeps their
                // state but they should not burn frames while invisible.
                TickerMode(
                  enabled: destination == _current,
                  // A hidden tab can never own the focused field, so pin its
                  // viewInsets: otherwise every kept-alive Scaffold rebuilds
                  // per frame of the keyboard animation.
                  child: _TabViewInsets(
                    active: destination == _current,
                    // Every tab stays mounted in this one IndexedStack under a
                    // single route, which offers just one
                    // PrimaryScrollController. Give each tab its own so their
                    // (always-attached) primary ListViews don't all pile onto
                    // the shared one — a Scrollbar requires its controller to
                    // hold a single ScrollPosition.
                    child: PrimaryScrollScope(
                      // IndexedStack keeps the outgoing tab offstage instantly
                      // (no cross-fade of the old page); the newly-shown tab
                      // gently fades in via AnimatedOpacity so the switch reads
                      // as a smooth transition rather than a hard cut. An
                      // offstage tab holds opacity 0, so re-showing it animates
                      // 0 -> 1. Reduced-motion collapses it to an instant swap.
                      child: AnimatedOpacity(
                        opacity: destination == _current ? 1 : 0,
                        duration: MediaQuery.disableAnimationsOf(context)
                            ? Duration.zero
                            : AppMotion.tabSwitch,
                        curve: Curves.easeInOut,
                        // iOS-only edge back-swipe. The calendar tab owns its
                        // own horizontal week-swipe, so only the other tabs get
                        // it, and only on iOS (context.isCupertino is the single
                        // platform seam) so Android keeps its plain tabs.
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

  /// Built-screen cache: reusing the identical widget instance across shell
  /// `setState`s lets unchanged (especially hidden) tabs short-circuit their
  /// rebuild. Invalidated when the identity args change, which mirrors when
  /// [_screenFor] would produce different widgets.
  final Map<AdaptiveDestination, Widget> _screenCache = {};
  ({bool isAdmin, String employeeId, String userName, String userEmail})?
  _screenCacheIdentity;

  /// Drops the cache once per build when the identity args change (records
  /// compare structurally), so `_cachedScreenFor` stays a plain lookup.
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
    // Key on the identity args so an in-place change (live admin upgrade)
    // rebuilds the screen from scratch — matching the old route-replacement
    // semantics — while plain tab switches keep the screen's state alive.
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

/// Pins a hidden tab's `viewInsets` to zero so the keyboard open/close
/// animation (per-frame `viewInsets` changes) never dirties it — only the
/// visible tab can own the focused field, so only it needs to resize.
///
/// Always present in every tab's subtree (parameterized by [active] rather
/// than conditionally inserted) so toggling a tab never changes the element
/// tree shape, which would drop the kept-alive screen state.
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

/// Redirects a named hub-route push into a tab switch on the live [HubShell].
///
/// The settings drawer still navigates by pushing named hub routes
/// (`Navigator.pushNamed`). With a shell already live, stacking a second
/// standalone hub screen on top of it would fork navigation state, so
/// `AppRoutes` returns this transparent, zero-duration route instead: on the
/// first frame after the push it switches the live shell's tab and removes
/// itself, leaving the stack exactly as it was. If the shell somehow died in
/// the meantime (it can't for a plain push — the shell stays beneath this
/// route — but be defensive), it replaces itself with a fresh shell so the
/// navigator can never end up empty.
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

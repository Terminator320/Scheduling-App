// Pins navigateToDestination — the ONE nav action. Its three branches are
// invisible when they break: picking the wrong one leaves the previous screen
// stacked on top of the tab you just switched to, which reads as "the drawer
// didn't work" rather than as an error.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/core/navigation/app_destination.dart';
import 'package:scheduling/core/navigation/hub_shell_scope.dart';
import 'package:scheduling/routes/app_routes.dart';

class _FakeShell implements HubTabSelector {
  final List<HubTab> selected = [];
  final List<HubTab> revealed = [];
  int goneHome = 0;

  @override
  void select(
    HubTab tab, {
    required bool isAdmin,
    required String employeeId,
    String userName = '',
    String userEmail = '',
  }) => selected.add(tab);

  @override
  void selectAndReveal(
    HubTab tab, {
    required bool isAdmin,
    required String employeeId,
    String userName = '',
    String userEmail = '',
  }) => revealed.add(tab);

  @override
  void goHome() => goneHome++;
}

/// Records the name of every pushed route.
class _RecordingObserver extends NavigatorObserver {
  _RecordingObserver(this.pushed);

  final List<String?> pushed;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      pushed.add(route.settings.name);
}

void main() {
  tearDown(() => HubShellScope.liveSelector = null);

  /// Every route name the Navigator was asked to push.
  final pushed = <String?>[];
  final observer = _RecordingObserver(pushed);

  /// Pumps a leaf — INSIDE the scope when [shell] is given, since that is what
  /// decides whether inheritance can find it — and returns its context.
  /// [routeName] names the route the leaf is on.
  Future<BuildContext> pump(
    WidgetTester tester, {
    _FakeShell? shell,
    HubTab current = HubTab.calendar,
    String routeName = AppRoutes.mainCalendar,
  }) async {
    late final BuildContext ctx;
    final leaf = Builder(
      builder: (context) {
        ctx = context;
        return const SizedBox.shrink();
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [observer],
        initialRoute: routeName,
        onGenerateRoute: (settings) => MaterialPageRoute<void>(
          settings: settings,
          builder: (_) {
            // Anything pushed on top is irrelevant here — only its name is.
            if (settings.name != routeName) return const SizedBox.shrink();
            return shell == null
                ? leaf
                : HubShellScope(shell: shell, current: current, child: leaf);
          },
        ),
      ),
    );
    pushed.clear();
    return ctx;
  }

  void go(BuildContext context, AppDestination destination) =>
      navigateToDestination(
        context,
        destination,
        isAdmin: true,
        employeeId: 'e1',
      );

  testWidgets('inside the shell, a hub tab just switches the tab', (
    tester,
  ) async {
    final shell = _FakeShell();
    final ctx = await pump(tester, shell: shell);

    go(ctx, HubTab.clients);

    expect(shell.selected, [HubTab.clients]);
    // Nothing is stacked above the shell here, so no reveal is needed.
    expect(shell.revealed, isEmpty);
  });

  testWidgets('from a pushed route, a hub tab reveals the shell first', (
    tester,
  ) async {
    // A pushed route's subtree is a sibling overlay entry, so inheritance
    // can't find the scope — this is what liveSelector exists for. Without the
    // reveal the pushed screen stays on top of the tab it just switched to.
    final shell = _FakeShell();
    HubShellScope.liveSelector = shell;
    final ctx = await pump(tester, routeName: AppRoutes.settings);

    go(ctx, HubTab.clients);

    expect(shell.revealed, [HubTab.clients]);
    expect(shell.selected, isEmpty);
  });

  testWidgets('a pushed destination pushes its route', (tester) async {
    final shell = _FakeShell();
    final ctx = await pump(tester, shell: shell);

    go(ctx, PushedDestination.settings);
    await tester.pumpAndSettle();

    expect(pushed, [AppRoutes.settings]);
    expect(shell.selected, isEmpty);
    expect(shell.revealed, isEmpty);
  });

  testWidgets('re-tapping the route you are already on is a no-op', (
    tester,
  ) async {
    final ctx = await pump(tester, routeName: AppRoutes.settings);

    go(ctx, PushedDestination.settings);
    await tester.pumpAndSettle();

    expect(pushed, isEmpty);
  });

  testWidgets('goHomeToCalendar goes through the shell, not a raw push', (
    tester,
  ) async {
    final shell = _FakeShell();
    final ctx = await pump(tester, shell: shell);

    goHomeToCalendar(ctx);

    expect(shell.goneHome, 1);
  });

  testWidgets('goHomeToCalendar reaches a pushed route via liveSelector', (
    tester,
  ) async {
    final shell = _FakeShell();
    HubShellScope.liveSelector = shell;
    final ctx = await pump(tester, routeName: AppRoutes.settings);

    goHomeToCalendar(ctx);

    expect(shell.goneHome, 1);
  });

  testWidgets('currentOf is null outside the shell subtree', (tester) async {
    // The distinction the tour gating depends on: null means "not in the hub",
    // which also describes a hub screen hosted standalone in a test.
    final ctx = await pump(tester, routeName: AppRoutes.settings);

    expect(HubShellScope.currentOf(ctx), isNull);
    expect(HubShellScope.maybeOf(ctx), isNull);
  });

  testWidgets('currentOf reports the visible tab inside the shell', (
    tester,
  ) async {
    final ctx = await pump(
      tester,
      shell: _FakeShell(),
      current: HubTab.liveMap,
    );

    expect(HubShellScope.currentOf(ctx), HubTab.liveMap);
    expect(HubShellScope.readCurrentOf(ctx), HubTab.liveMap);
  });
}

// The cold-start half of `AppRoutes._hubRoute`.
//
// `lib/core/navigation/CLAUDE.md` says `_hubRoute` + `HubTabRedirectRoute`
// "look dead but remain the cold-start fallback". `hub_shell_test.dart` only
// ever mounts a live `HubShell` as `home:` before pushing, so it exercises the
// redirect branch alone — `grep -rn "initialTab" test/` came back empty, and
// the fallback that builds a FRESH shell on the target tab was never reached
// by any test. A push landing on the calendar instead of the tab that was
// asked for (a push notification tap, or a drawer entry taken before the shell
// exists) is exactly what that branch prevents.
//
// These tests deliberately inspect the generated Route rather than pumping it:
// the fallback constructs a real `HubShell` with the production screen
// builders, whose tabs each need Firebase and a ProviderScope. The branch
// selection and the `initialTab` it carries are the logic under test.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/core/navigation/app_destination.dart';
import 'package:scheduling/routes/app_routes.dart';
import 'package:scheduling/routes/hub_shell.dart';

/// A stub-screen shell, so a "live shell" exists without touching Firebase.
Widget _stubScreen(HubTab destination) =>
    Scaffold(body: Text('screen-${destination.name}'));

/// The three named routes that go through `_hubRoute`, with the argument class
/// each one casts to.
const _hubRoutes = <({String name, Object args, HubTab tab})>[
  (
    name: AppRoutes.clients,
    args: ClientsListArgs(isAdmin: true, employeeId: 'e1'),
    tab: HubTab.clients,
  ),
  (
    name: AppRoutes.employees,
    args: MainCalendarArgs(isAdmin: true, employeeId: 'e1'),
    tab: HubTab.employees,
  ),
  (
    name: AppRoutes.liveMap,
    args: MainCalendarArgs(isAdmin: false, employeeId: 'e2'),
    tab: HubTab.liveMap,
  ),
];

void main() {
  /// Pumps a harness with NO hub shell in it, so `HubShell.liveState` is null —
  /// the cold-start condition. Returns a context for the route builders.
  Future<BuildContext> pumpShellLessApp(WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          onGenerateRoute: AppRoutes.onGenerateRoute,
          home: Scaffold(body: Text('no-shell')),
        ),
      ),
    );
    expect(HubShell.liveState, isNull, reason: 'a shell leaked into the test');
    return tester.element(find.text('no-shell'));
  }

  HubShell shellFrom(Route<dynamic> route, BuildContext context) {
    expect(
      route,
      isNot(isA<HubTabRedirectRoute>()),
      reason: 'took the redirect branch with no shell to redirect into',
    );
    final page = route as MaterialPageRoute<dynamic>;
    return page.builder(context) as HubShell;
  }

  testWidgets(
    'with no live shell each hub route opens a fresh shell already on its tab',
    (tester) async {
      final context = await pumpShellLessApp(tester);

      for (final entry in _hubRoutes) {
        final route = AppRoutes.onGenerateRoute(
          RouteSettings(name: entry.name, arguments: entry.args),
        );
        expect(route, isNotNull, reason: '${entry.name} generated no route');

        final shell = shellFrom(route!, context);
        // The whole point of the fallback: without `initialTab` the person
        // lands on the calendar and has to find the tab they asked for.
        expect(
          shell.initialTab,
          entry.tab,
          reason: '${entry.name} opened on ${shell.initialTab}',
        );
      }
    },
  );

  testWidgets('the fresh shell carries the identity the push supplied', (
    tester,
  ) async {
    final context = await pumpShellLessApp(tester);

    final route = AppRoutes.onGenerateRoute(
      const RouteSettings(
        name: AppRoutes.liveMap,
        arguments: MainCalendarArgs(isAdmin: false, employeeId: 'e2'),
      ),
    )!;
    final shell = shellFrom(route, context);

    // A dropped identity here reopens the admin surfaces to an employee, or
    // strands an admin without them.
    expect(shell.isAdmin, isFalse);
    expect(shell.employeeId, 'e2');
  });

  testWidgets('the generated route keeps its settings so goHome can find it', (
    tester,
  ) async {
    final context = await pumpShellLessApp(tester);

    final route = AppRoutes.onGenerateRoute(
      const RouteSettings(
        name: AppRoutes.clients,
        arguments: ClientsListArgs(isAdmin: true, employeeId: 'e1'),
      ),
    )!;
    shellFrom(route, context);

    // On this branch the shell is NOT route #1, which is why `_popToShell`
    // captures its own ModalRoute instead of using `isFirst`.
    expect(route.settings.name, AppRoutes.clients);
  });

  testWidgets('a live shell takes the redirect branch instead', (tester) async {
    // The contrast case, and the reason the pair is two branches: once a shell
    // exists the same push must switch its tab rather than stack a second one.
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          onGenerateRoute: AppRoutes.onGenerateRoute,
          home: HubShell(
            isAdmin: true,
            employeeId: 'e1',
            screenBuilder: _stubScreen,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(HubShell.liveState, isNotNull);

    final route = AppRoutes.onGenerateRoute(
      const RouteSettings(
        name: AppRoutes.clients,
        arguments: ClientsListArgs(isAdmin: true, employeeId: 'e1'),
      ),
    );

    expect(route, isA<HubTabRedirectRoute>());
    expect((route! as HubTabRedirectRoute).destination, HubTab.clients);
  });
}

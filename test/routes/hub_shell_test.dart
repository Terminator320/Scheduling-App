import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/core/layout/adaptive_shell.dart';
import 'package:scheduling/routes/app_routes.dart';
import 'package:scheduling/routes/hub_shell.dart';

/// Stub hub screen: renders a marker per destination and a button that
/// drives [navigateToDestination] from inside the shell, mirroring how the
/// real screens' back chevrons and nav rail switch tabs.
Widget _stubScreen(AdaptiveDestination destination) => Scaffold(
  body: Builder(
    builder: (context) => Column(
      children: [
        Text('screen-${destination.name}'),
        TextButton(
          onPressed: () => navigateToDestination(
            context,
            AdaptiveDestination.calendar,
            isAdmin: true,
            employeeId: 'e1',
          ),
          child: Text('back-${destination.name}'),
        ),
      ],
    ),
  ),
);

Widget _app({Widget? home}) => MaterialApp(
  home:
      home ??
      const HubShell(
        isAdmin: true,
        employeeId: 'e1',
        screenBuilder: _stubScreen,
      ),
  onGenerateRoute: AppRoutes.onGenerateRoute,
);

HubShellState _shellState(WidgetTester tester) =>
    tester.state<HubShellState>(find.byType(HubShell));

void main() {
  testWidgets(
    'system back on a non-calendar tab returns to the calendar tab '
    'instead of popping the root route',
    (tester) async {
      await tester.pumpWidget(_app());
      _shellState(tester).select(
        AdaptiveDestination.settings,
        isAdmin: true,
        employeeId: 'e1',
      );
      await tester.pump();
      expect(find.text('screen-settings'), findsOneWidget);

      // Android system back.
      await tester.binding.handlePopRoute();
      await tester.pump();

      expect(
        _shellState(tester).currentDestination,
        AdaptiveDestination.calendar,
      );
      expect(find.text('screen-calendar'), findsOneWidget);
      // The shell route itself was not popped.
      expect(find.byType(HubShell), findsOneWidget);
    },
  );

  testWidgets('back on the calendar tab lets the pop through (canPop)', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    final popScope = tester.widget<PopScope<Object?>>(
      find.byWidgetPredicate((w) => w is PopScope),
    );
    expect(popScope.canPop, isTrue);

    _shellState(tester).select(
      AdaptiveDestination.clients,
      isAdmin: true,
      employeeId: 'e1',
    );
    await tester.pump();
    final popScopeOnClients = tester.widget<PopScope<Object?>>(
      find.byWidgetPredicate((w) => w is PopScope),
    );
    expect(popScopeOnClients.canPop, isFalse);
  });

  testWidgets('tabs build lazily on first visit, then stay alive', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    // Only the initial tab has been built.
    expect(find.text('screen-calendar'), findsOneWidget);
    expect(find.text('screen-clients', skipOffstage: false), findsNothing);

    _shellState(tester).select(
      AdaptiveDestination.clients,
      isAdmin: true,
      employeeId: 'e1',
    );
    await tester.pump();
    expect(find.text('screen-clients'), findsOneWidget);
    // The calendar stays alive offstage instead of being disposed.
    expect(find.text('screen-calendar', skipOffstage: false), findsOneWidget);
    expect(find.text('screen-calendar'), findsNothing);
  });

  testWidgets(
    'navigateToDestination inside the shell switches tabs without '
    'touching the navigator stack',
    (tester) async {
      await tester.pumpWidget(_app());
      _shellState(tester).select(
        AdaptiveDestination.history,
        isAdmin: true,
        employeeId: 'e1',
      );
      await tester.pump();

      // The stub's back button mirrors the hub screens' AppTopBar chevron.
      await tester.tap(find.text('back-history'));
      await tester.pump();

      expect(find.text('screen-calendar'), findsOneWidget);
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      expect(navigator.canPop(), isFalse);
    },
  );

  testWidgets(
    'pushing a named hub route with a live shell redirects into a tab '
    'switch instead of stacking a second screen',
    (tester) async {
      await tester.pumpWidget(_app());
      expect(find.text('screen-calendar'), findsOneWidget);

      // Mirrors the settings drawer, which still pushes named hub routes.
      final context = tester.element(find.text('screen-calendar'));
      unawaited(
        Navigator.pushNamed(
          context,
          AppRoutes.clients,
          arguments: const ClientsListArgs(isAdmin: true, employeeId: 'e1'),
        ),
      );
      await tester.pump(); // Build the redirect route (post-frame scheduled).
      await tester.pump(); // Redirect switches the tab and removes itself.

      expect(find.byType(HubShell), findsOneWidget);
      expect(
        _shellState(tester).currentDestination,
        AdaptiveDestination.clients,
      );
      expect(find.text('screen-clients'), findsOneWidget);
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      expect(navigator.canPop(), isFalse);
    },
  );
}

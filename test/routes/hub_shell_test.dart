import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/core/navigation/app_destination.dart';
import 'package:scheduling/core/navigation/hub_shell_scope.dart';
import 'package:scheduling/routes/app_routes.dart';
import 'package:scheduling/routes/hub_shell.dart';

/// Stub hub screen: renders a marker per destination and a button that
/// drives [navigateToDestination] from inside the shell, mirroring how the
/// real screens' back chevrons and nav rail switch tabs.
Widget _stubScreen(HubTab destination) => Scaffold(
  body: Builder(
    builder: (context) => Column(
      children: [
        Text('screen-${destination.name}'),
        TextButton(
          onPressed: () => navigateToDestination(
            context,
            HubTab.calendar,
            isAdmin: true,
            employeeId: 'e1',
          ),
          child: Text('back-${destination.name}'),
        ),
      ],
    ),
  ),
);

/// The shell is a `ConsumerStatefulWidget` (it reports its own tab screen
/// views), so every pump needs a scope. Nothing here overrides
/// `analyticsServiceProvider`: with no Firebase in the harness the service
/// resolves to null and every call is a silent no-op.
Widget _app({Widget? home}) => ProviderScope(
  child: MaterialApp(
    home:
        home ??
        const HubShell(
          isAdmin: true,
          employeeId: 'e1',
          screenBuilder: _stubScreen,
        ),
    onGenerateRoute: AppRoutes.onGenerateRoute,
  ),
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
        HubTab.liveMap,
        isAdmin: true,
        employeeId: 'e1',
      );
      await tester.pump();
      expect(find.text('screen-liveMap'), findsOneWidget);

      // Android system back.
      await tester.binding.handlePopRoute();
      await tester.pump();

      expect(
        _shellState(tester).currentTab,
        HubTab.calendar,
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
      HubTab.clients,
      isAdmin: true,
      employeeId: 'e1',
    );
    await tester.pump();
    final popScopeOnClients = tester.widget<PopScope<Object?>>(
      find.byWidgetPredicate((w) => w is PopScope),
    );
    expect(popScopeOnClients.canPop, isFalse);
  });

  testWidgets('the live-map tab builds lazily and selects via the shell', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    expect(find.text('screen-liveMap', skipOffstage: false), findsNothing);

    _shellState(tester).select(
      HubTab.liveMap,
      isAdmin: true,
      employeeId: 'e1',
    );
    await tester.pump();

    expect(
      _shellState(tester).currentTab,
      HubTab.liveMap,
    );
    expect(find.text('screen-liveMap'), findsOneWidget);
  });

  testWidgets('tabs build lazily on first visit, then stay alive', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    // Only the initial tab has been built.
    expect(find.text('screen-calendar'), findsOneWidget);
    expect(find.text('screen-clients', skipOffstage: false), findsNothing);

    _shellState(tester).select(
      HubTab.clients,
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
        HubTab.employees,
        isAdmin: true,
        employeeId: 'e1',
      );
      await tester.pump();

      // The stub's back button mirrors the hub screens' AppTopBar chevron.
      await tester.tap(find.text('back-employees'));
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
      Navigator.pushNamed(
        context,
        AppRoutes.clients,
        arguments: const ClientsListArgs(isAdmin: true, employeeId: 'e1'),
      );
      await tester.pump(); // Build the redirect route (post-frame scheduled).
      await tester.pump(); // Redirect switches the tab and removes itself.

      expect(find.byType(HubShell), findsOneWidget);
      expect(
        _shellState(tester).currentTab,
        HubTab.clients,
      );
      expect(find.text('screen-clients'), findsOneWidget);
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      expect(navigator.canPop(), isFalse);
    },
  );

  testWidgets(
    'the screen cache reuses one instance per tab, so a plain tab switch '
    'does not rebuild an already-built screen',
    (tester) async {
      final buildCounts = <HubTab, int>{};
      Widget countingBuilder(HubTab destination) {
        buildCounts[destination] = (buildCounts[destination] ?? 0) + 1;
        return Scaffold(body: Text('screen-${destination.name}'));
      }

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: HubShell(
              isAdmin: true,
              employeeId: 'e1',
              screenBuilder: countingBuilder,
            ),
          ),
        ),
      );
      expect(buildCounts[HubTab.calendar], 1);

      // Visit employees, then return to calendar — identity unchanged.
      _shellState(tester).select(
        HubTab.employees,
        isAdmin: true,
        employeeId: 'e1',
      );
      await tester.pump();
      _shellState(tester).select(
        HubTab.calendar,
        isAdmin: true,
        employeeId: 'e1',
      );
      await tester.pump();

      // Employees built once on first visit; calendar never rebuilt despite
      // three shell builds (without the cache it would rebuild each time).
      expect(buildCounts[HubTab.employees], 1);
      expect(buildCounts[HubTab.calendar], 1);
    },
  );

  testWidgets(
    'changing the identity args (an admin upgrade) invalidates the cache '
    'so the screen is rebuilt, while a same-identity reselect does not',
    (tester) async {
      final buildCounts = <HubTab, int>{};
      Widget countingBuilder(HubTab destination) {
        buildCounts[destination] = (buildCounts[destination] ?? 0) + 1;
        return Scaffold(body: Text('screen-${destination.name}'));
      }

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: HubShell(
              isAdmin: false,
              employeeId: 'e1',
              screenBuilder: countingBuilder,
            ),
          ),
        ),
      );
      expect(buildCounts[HubTab.calendar], 1);

      // Reselecting with the same identity must not rebuild.
      _shellState(tester).select(
        HubTab.calendar,
        isAdmin: false,
        employeeId: 'e1',
      );
      await tester.pump();
      expect(buildCounts[HubTab.calendar], 1);

      // Flipping isAdmin changes the identity -> cache clears -> rebuild.
      _shellState(tester).select(
        HubTab.calendar,
        isAdmin: true,
        employeeId: 'e1',
      );
      await tester.pump();
      expect(buildCounts[HubTab.calendar], 2);
    },
  );

  testWidgets('goHome pops back to the shell route and lands on calendar', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    _shellState(tester).select(
      HubTab.clients,
      isAdmin: true,
      employeeId: 'e1',
    );
    await tester.pump();
    expect(find.text('screen-clients'), findsOneWidget);

    // Stack two routes above the shell.
    final navigator = tester.state<NavigatorState>(find.byType(Navigator))
      ..push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('pushed-one')),
        ),
      );
    await tester.pumpAndSettle();
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('pushed-two')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('pushed-two'), findsOneWidget);

    HubShell.liveState!.goHome();
    await tester.pumpAndSettle();

    expect(find.text('pushed-one'), findsNothing);
    expect(find.text('pushed-two'), findsNothing);
    expect(find.text('screen-calendar'), findsOneWidget);
    expect(HubShell.liveState!.currentTab, HubTab.calendar);
  });
}

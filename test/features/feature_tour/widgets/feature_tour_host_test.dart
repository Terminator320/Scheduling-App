import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/core/navigation/app_destination.dart';
import 'package:scheduling/core/navigation/hub_shell_scope.dart';
import 'package:scheduling/features/feature_tour/application/tour_seen_store.dart';
import 'package:scheduling/features/feature_tour/domain/tour_scope.dart';
import 'package:scheduling/features/feature_tour/domain/tour_step_id.dart';
import 'package:scheduling/features/feature_tour/widgets/feature_tour_host.dart';
import 'package:scheduling/features/feature_tour/widgets/tour_showcase.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeShell implements HubTabSelector {
  @override
  void select(
    HubTab tab, {
    required bool isAdmin,
    required String employeeId,
    String userName = '',
    String userEmail = '',
  }) {}

  @override
  void selectAndReveal(
    HubTab tab, {
    required bool isAdmin,
    required String employeeId,
    String userName = '',
    String userEmail = '',
  }) {}

  @override
  void goHome() {}
}

void main() {
  Widget harness({
    required HubTab current,
    required TourScope scope,
    required Map<TourStepId, GlobalKey> stepKeys,
    required Widget child,
    required ProviderContainer container,
  }) {
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: HubShellScope(
          shell: _FakeShell(),
          current: current,
          child: FeatureTourHost(
            scope: scope,
            isAdmin: true,
            stepKeys: stepKeys,
            child: Scaffold(body: child),
          ),
        ),
      ),
    );
  }

  ProviderContainer newContainer() {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.listen(tourSeenProvider, (_, _) {});
    return c;
  }

  testWidgets('does not start while its tab is hidden', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final container = newContainer();
    final key = GlobalKey();
    await tester.pumpWidget(
      harness(
        current: HubTab.calendar, // another tab is visible
        scope: const DestinationTour(HubTab.clients),
        stepKeys: {TourStepId.clientsSearch: key},
        container: container,
        child: TourShowcase(
          showcaseKey: key,
          scope: const DestinationTour(HubTab.clients),
          id: TourStepId.clientsSearch,
          index: 0,
          count: 2,
          child: const Text('target'),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
    expect(find.text('Find a client'), findsNothing);
    expect(
      container.read(tourSeenProvider),
      isNot(contains(const DestinationTour(HubTab.clients))),
    );
  });

  testWidgets('marks seen without starting when no target is mounted', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final container = newContainer();
    await tester.pumpWidget(
      harness(
        current: HubTab.clients,
        scope: const DestinationTour(HubTab.clients),
        stepKeys: {TourStepId.clientsSearch: GlobalKey()}, // never attached
        container: container,
        child: const Text('no showcase targets here'),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
    expect(
      container.read(tourSeenProvider),
      contains(const DestinationTour(HubTab.clients)),
    );
  });

  testWidgets('starts and shows the first step when visible and unseen', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final container = newContainer();
    final searchKey = GlobalKey();
    final addKey = GlobalKey();
    await tester.pumpWidget(
      harness(
        current: HubTab.clients,
        scope: const DestinationTour(HubTab.clients),
        stepKeys: {
          TourStepId.clientsSearch: searchKey,
          TourStepId.clientsAdd: addKey,
        },
        container: container,
        child: Column(
          children: [
            TourShowcase(
              showcaseKey: searchKey,
              scope: const DestinationTour(HubTab.clients),
              id: TourStepId.clientsSearch,
              index: 0,
              count: 2,
              child: const Text('search target'),
            ),
            TourShowcase(
              showcaseKey: addKey,
              scope: const DestinationTour(HubTab.clients),
              id: TourStepId.clientsAdd,
              index: 1,
              count: 2,
              child: const Text('add target'),
            ),
          ],
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
    expect(find.text('Find a client'), findsOneWidget);
    expect(find.text('1 of 2'), findsOneWidget);
  });

  testWidgets('does not start when already seen', (tester) async {
    SharedPreferences.setMockInitialValues({
      'tour_seen_tabs': ['clients'],
    });
    final container = newContainer();
    final key = GlobalKey();
    await tester.pumpWidget(
      harness(
        current: HubTab.clients,
        scope: const DestinationTour(HubTab.clients),
        stepKeys: {TourStepId.clientsSearch: key},
        container: container,
        child: TourShowcase(
          showcaseKey: key,
          scope: const DestinationTour(HubTab.clients),
          id: TourStepId.clientsSearch,
          index: 0,
          count: 2,
          child: const Text('target'),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
    expect(find.text('Find a client'), findsNothing);
  });

  testWidgets(
    'a pushed destination gates on its own route being current, not on the '
    'hub scope',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final container = newContainer();
      final navigatorKey = GlobalKey<NavigatorState>();

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            navigatorKey: navigatorKey,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(body: Text('root')),
          ),
        ),
      );

      // Both pushes in one batch, so the toured route is never momentarily
      // on top — otherwise it gets a legitimate window to start.
      unawaited(
        navigatorKey.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => FeatureTourHost(
              scope: const DestinationTour(PushedDestination.settings),
              isAdmin: true,
              // Never attached, so a start would mark seen instead.
              stepKeys: {TourStepId.settingsAppearance: GlobalKey()},
              child: const Scaffold(body: Text('settings-body')),
            ),
          ),
        ),
      );
      unawaited(
        navigatorKey.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('on-top')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('on-top'), findsOneWidget);
      expect(
        container.read(tourSeenProvider),
        isNot(contains(const DestinationTour(PushedDestination.settings))),
        reason: 'a buried route must not start its tour',
      );

      // Popping back makes the route current again, re-opening the gate.
      navigatorKey.currentState!.pop();
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));

      expect(tester.takeException(), isNull);
      expect(
        container.read(tourSeenProvider),
        contains(const DestinationTour(PushedDestination.settings)),
      );
    },
  );

  testWidgets('a form sheet gates on its own modal route being current', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final container = newContainer();
    final navigatorKey = GlobalKey<NavigatorState>();
    const scope = FormTour(TourForm.addAppointment);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          navigatorKey: navigatorKey,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: Text('root')),
        ),
      ),
    );

    expect(
      container.read(tourSeenProvider),
      isNot(contains(scope)),
      reason: 'nothing has opened the sheet yet',
    );

    // A ModalBottomSheetRoute is a ModalRoute, so the host's route branch
    // covers it with no third visibility mode.
    unawaited(
      showModalBottomSheet<void>(
        context: navigatorKey.currentContext!,
        builder: (_) => const FeatureTourHost(
          scope: scope,
          isAdmin: true,
          // Never attached, so a start marks seen rather than showing a step.
          stepKeys: {},
          child: Text('sheet-body'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));

    expect(tester.takeException(), isNull);
    expect(find.text('sheet-body'), findsOneWidget);
    expect(
      container.read(tourSeenProvider),
      contains(scope),
      reason: 'the sheet route is current, so its tour ran',
    );
  });
}

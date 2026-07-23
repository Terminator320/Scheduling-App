import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/core/layout/adaptive_shell.dart';
import 'package:scheduling/features/feature_tour/application/tour_seen_store.dart';
import 'package:scheduling/features/feature_tour/domain/tour_step_id.dart';
import 'package:scheduling/features/feature_tour/widgets/feature_tour_host.dart';
import 'package:scheduling/features/feature_tour/widgets/tour_showcase.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeShell implements HubTabSelector {
  @override
  void select(
    AdaptiveDestination destination, {
    required bool isAdmin,
    required String employeeId,
    String userName = '',
    String userEmail = '',
  }) {}
}

void main() {
  Widget harness({
    required AdaptiveDestination current,
    required AdaptiveDestination tab,
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
            tab: tab,
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
        current: AdaptiveDestination.calendar, // another tab is visible
        tab: AdaptiveDestination.clients,
        stepKeys: {TourStepId.clientsSearch: key},
        container: container,
        child: TourShowcase(
          showcaseKey: key,
          tab: AdaptiveDestination.clients,
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
      isNot(contains(AdaptiveDestination.clients)),
    );
  });

  testWidgets('marks seen without starting when no target is mounted', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final container = newContainer();
    await tester.pumpWidget(
      harness(
        current: AdaptiveDestination.clients,
        tab: AdaptiveDestination.clients,
        stepKeys: {TourStepId.clientsSearch: GlobalKey()}, // never attached
        container: container,
        child: const Text('no showcase targets here'),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
    expect(
      container.read(tourSeenProvider),
      contains(AdaptiveDestination.clients),
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
        current: AdaptiveDestination.clients,
        tab: AdaptiveDestination.clients,
        stepKeys: {
          TourStepId.clientsSearch: searchKey,
          TourStepId.clientsAdd: addKey,
        },
        container: container,
        child: Column(
          children: [
            TourShowcase(
              showcaseKey: searchKey,
              tab: AdaptiveDestination.clients,
              id: TourStepId.clientsSearch,
              index: 0,
              count: 2,
              child: const Text('search target'),
            ),
            TourShowcase(
              showcaseKey: addKey,
              tab: AdaptiveDestination.clients,
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
        current: AdaptiveDestination.clients,
        tab: AdaptiveDestination.clients,
        stepKeys: {TourStepId.clientsSearch: key},
        container: container,
        child: TourShowcase(
          showcaseKey: key,
          tab: AdaptiveDestination.clients,
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
}

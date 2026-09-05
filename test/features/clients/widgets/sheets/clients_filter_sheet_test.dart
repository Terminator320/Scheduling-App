import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/core/theme/themes.dart';
import 'package:scheduling/features/clients/application/clients_providers.dart';
import 'package:scheduling/features/clients/domain/models/client_type.dart';
import 'package:scheduling/features/clients/domain/models/clients_filter.dart';
import 'package:scheduling/features/clients/domain/policies/client_building.dart';
import 'package:scheduling/features/clients/widgets/sheets/clients_filter_sheet.dart';
import 'package:scheduling/l10n/l10n.dart';

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(ClientsFilterSheet)));

Widget _harness({
  required ClientsFilter selected,
  required ValueChanged<ClientsFilterPick> onChanged,
  List<ClientBuilding> buildings = const [],
  bool buildingsLoading = false,
  bool buildingsFail = false,
}) {
  return ProviderScope(
    overrides: [
      clientBuildingsProvider.overrideWith((ref) {
        if (buildingsLoading) {
          return Completer<List<ClientBuilding>>().future;
        }
        if (buildingsFail) throw StateError('scan failed');
        return Future.value(buildings);
      }),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: lightTheme(),
      home: Scaffold(
        body: ClientsFilterSheet(selected: selected, onChanged: onChanged),
      ),
    ),
  );
}

const _building = ClientBuilding(
  key: 'k1',
  street: '1200 Rue Sherbrooke',
  city: 'Montreal',
  clientCount: 4,
);

void main() {
  testWidgets('renders every pickable type plus All and Archived', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(selected: const ClientsFilterAll(), onChanged: (_) {}),
    );
    await tester.pumpAndSettle();

    final l10n = _l10n(tester);
    // Three pickable types, not two — dropping `building` would make those
    // clients unreachable by filter.
    expect(ClientType.pickable.length, 3);
    for (final type in ClientType.pickable) {
      expect(find.text(clientTypeLabel(l10n, type)), findsOneWidget);
    }
    expect(find.text(l10n.clients_filterAll), findsOneWidget);
    expect(find.text(l10n.clients_filterArchived), findsOneWidget);
  });

  testWidgets('picking a type emits that filter and no building label', (
    tester,
  ) async {
    ClientsFilterPick? emitted;
    await tester.pumpWidget(
      _harness(
        selected: const ClientsFilterAll(),
        onChanged: (pick) => emitted = pick,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.text(clientTypeLabel(_l10n(tester), ClientType.residential)),
    );
    await tester.pumpAndSettle();

    expect(emitted?.filter, const ClientsFilterType(ClientType.residential));
    expect(emitted?.buildingLabel, isNull);
  });

  // The whole point of the redesign: ONE radio group, so picking an address
  // replaces the type rather than combining with it.
  testWidgets('picking an address replaces an active type filter', (
    tester,
  ) async {
    ClientsFilterPick? emitted;
    await tester.pumpWidget(
      _harness(
        selected: const ClientsFilterType(ClientType.commercial),
        onChanged: (pick) => emitted = pick,
        buildings: const [_building],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('1200 Rue Sherbrooke'));
    await tester.pumpAndSettle();

    expect(emitted?.filter, const ClientsFilterBuilding('k1'));
    // Carried back so the caller's chip can name it without watching the scan.
    expect(emitted?.buildingLabel, '1200 Rue Sherbrooke');
  });

  testWidgets('shows the shared-client count beside each address', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        selected: const ClientsFilterAll(),
        onChanged: (_) {},
        buildings: const [_building],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('4'), findsOneWidget);
    expect(find.text('Montreal'), findsOneWidget);
  });

  testWidgets('opens immediately, with a spinner while the scan resolves', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        selected: const ClientsFilterAll(),
        onChanged: (_) {},
        buildingsLoading: true,
      ),
    );
    await tester.pump();

    expect(find.text(_l10n(tester).clients_filterTitle), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('hides the address section entirely when nothing is shared', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(selected: const ClientsFilterAll(), onChanged: (_) {}),
    );
    await tester.pumpAndSettle();

    expect(find.text(_l10n(tester).clients_filterSectionAddress), findsNothing);
  });

  // A failed scan must not take the type options down with it.
  testWidgets('a failed scan hides the address section and keeps the types', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        selected: const ClientsFilterAll(),
        onChanged: (_) {},
        buildingsFail: true,
      ),
    );
    await tester.pumpAndSettle();

    final l10n = _l10n(tester);
    expect(find.text(l10n.clients_filterSectionAddress), findsNothing);
    expect(
      find.text(clientTypeLabel(l10n, ClientType.residential)),
      findsOneWidget,
    );
  });

  testWidgets('does not overflow at 260px with 2x text', (tester) async {
    tester.view.physicalSize = const Size(260, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: _harness(
          selected: const ClientsFilterAll(),
          onChanged: (_) {},
          buildings: const [_building],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}

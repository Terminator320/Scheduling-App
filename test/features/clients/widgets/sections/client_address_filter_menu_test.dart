// Pins the Address filter menu — the one clients-list filter whose options are
// discovered from the data rather than fixed, so the things worth asserting
// are what it does with no options and how it reports the selected one.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/core/theme/theme_notifier.dart';
import 'package:scheduling/core/theme/themes.dart';
import 'package:scheduling/features/clients/domain/models/clients_filter.dart';
import 'package:scheduling/features/clients/domain/policies/client_building.dart';
import 'package:scheduling/features/clients/widgets/sections/client_address_filter_menu.dart';
import 'package:scheduling/l10n/l10n.dart';

const _paton = ClientBuilding(
  key: 'paton',
  street: '4450 Prom. Paton',
  city: 'Laval',
  clientCount: 18,
);
const _acadie = ClientBuilding(
  key: 'acadie',
  street: "10200 Bd de l'Acadie",
  city: 'Montréal',
  clientCount: 3,
);

Widget _harness({
  required List<ClientBuilding> buildings,
  ClientsFilter selected = const ClientsFilterAll(),
  ValueChanged<ClientsFilter>? onChanged,
}) => ThemeNotifier(
  themeMode: ThemeMode.light,
  toggleTheme: () {},
  textScale: 1,
  setTextScale: (_) {},
  setLanguage: (_) {},
  child: MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: lightTheme(),
    home: Scaffold(
      body: ClientAddressFilterMenu(
        buildings: buildings,
        selected: selected,
        onChanged: onChanged ?? (_) {},
      ),
    ),
  ),
);

void main() {
  testWidgets('renders NOTHING when no address is shared', (tester) async {
    // The normal state on a small roster. An empty menu is a control that
    // looks broken.
    await tester.pumpWidget(_harness(buildings: const []));
    await tester.pumpAndSettle();

    expect(find.byType(FilterChip), findsNothing);
  });

  testWidgets('offers every shared address, with its count', (tester) async {
    await tester.pumpWidget(_harness(buildings: const [_paton, _acadie]));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FilterChip));
    await tester.pumpAndSettle();

    expect(find.text('4450 Prom. Paton'), findsOneWidget);
    expect(find.text('Laval · 18 units'), findsOneWidget);
    expect(find.text("10200 Bd de l'Acadie"), findsOneWidget);
    expect(find.text('Montréal · 3 units'), findsOneWidget);
  });

  testWidgets('picking one selects that building', (tester) async {
    ClientsFilter? picked;
    await tester.pumpWidget(
      _harness(
        buildings: const [_paton, _acadie],
        onChanged: (next) => picked = next,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FilterChip));
    await tester.pumpAndSettle();
    await tester.tap(find.text('4450 Prom. Paton'));
    await tester.pumpAndSettle();

    expect(picked, const ClientsFilterBuilding('paton'));
  });

  testWidgets('the chip names the selected address', (tester) async {
    // So the active filter is readable without opening the menu.
    await tester.pumpWidget(
      _harness(
        buildings: const [_paton, _acadie],
        selected: const ClientsFilterBuilding('paton'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('4450 Prom. Paton'), findsOneWidget);
    expect(find.text('Address'), findsNothing);
  });

  testWidgets('picking the selected address clears the filter', (tester) async {
    // Mirrors the chips beside it — `toggledFilter`.
    ClientsFilter? picked;
    await tester.pumpWidget(
      _harness(
        buildings: const [_paton],
        selected: const ClientsFilterBuilding('paton'),
        onChanged: (next) => picked = next,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FilterChip));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Laval · 18 units'));
    await tester.pumpAndSettle();

    expect(picked, const ClientsFilterAll());
  });

  testWidgets('a selection that is no longer offered falls back', (
    tester,
  ) async {
    // The window refreshes between builds — a building whose last client moved
    // away must not leave the chip rendering a stale street or crashing on a
    // missing key.
    await tester.pumpWidget(
      _harness(
        buildings: const [_acadie],
        selected: const ClientsFilterBuilding('paton'),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Address'), findsOneWidget);
  });
}

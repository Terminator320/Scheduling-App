import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/core/theme/themes.dart';
import 'package:scheduling/features/clients/domain/models/client_type.dart';
import 'package:scheduling/features/clients/domain/models/clients_filter.dart';
import 'package:scheduling/features/clients/widgets/sections/clients_filter_bar.dart';
import 'package:scheduling/l10n/l10n.dart';

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(ClientsFilterBar)));

Widget _harness({
  required ClientsFilter selected,
  VoidCallback? onOpen,
  VoidCallback? onClear,
  String? buildingLabel,
  double textScale = 1,
  // The tour wraps this bar in a showcase, which hands its child UNBOUNDED
  // width — the shape that broke the first version of this widget.
  bool unbounded = false,
}) {
  final bar = ClientsFilterBar(
    selected: selected,
    onOpen: onOpen ?? () {},
    onClear: onClear ?? () {},
    activeBuildingLabel: buildingLabel,
  );
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    // The REAL theme, not the Material default: it makes every OutlinedButton
    // full-width, which is exactly what broke this bar in a Row.
    theme: lightTheme(),
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: Scaffold(
        body: unbounded ? Row(children: [bar]) : Column(children: [bar]),
      ),
    ),
  );
}

void main() {
  testWidgets('shows no active chip when the filter is All', (tester) async {
    await tester.pumpWidget(_harness(selected: const ClientsFilterAll()));
    await tester.pumpAndSettle();

    expect(find.text(_l10n(tester).clients_filter), findsOneWidget);
    expect(find.byType(InputChip), findsNothing);
  });

  testWidgets('shows one dismissible chip naming the active type', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(selected: const ClientsFilterType(ClientType.commercial)),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(clientTypeLabel(_l10n(tester), ClientType.commercial)),
      findsOneWidget,
    );
    expect(find.byType(InputChip), findsOneWidget);
  });

  testWidgets('dismissing the chip clears back to All', (tester) async {
    var cleared = false;
    await tester.pumpWidget(
      _harness(
        selected: const ClientsFilterArchived(),
        onClear: () => cleared = true,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(cleared, isTrue);
  });

  testWidgets('an active building chip uses the label it is given', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        selected: const ClientsFilterBuilding('k1'),
        buildingLabel: '1200 Rue Sherbrooke',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('1200 Rue Sherbrooke'), findsOneWidget);
  });

  testWidgets('tapping Filter calls onOpen', (tester) async {
    var opened = 0;
    await tester.pumpWidget(
      _harness(selected: const ClientsFilterAll(), onOpen: () => opened++),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text(_l10n(tester).clients_filter));
    await tester.pumpAndSettle();

    expect(opened, 1);
  });

  testWidgets('lays out under UNBOUNDED width, as the tour showcase gives it', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        selected: const ClientsFilterBuilding('k1'),
        buildingLabel: '1200 Rue Sherbrooke Ouest, Montreal',
        unbounded: true,
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(InputChip), findsOneWidget);
  });

  testWidgets('the Filter button survives a 260px phone at 2x text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(260, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _harness(
        selected: const ClientsFilterType(ClientType.residential),
        textScale: 2,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(_l10n(tester).clients_filter), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

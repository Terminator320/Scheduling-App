import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/features/clients/domain/models/client_record.dart';
import 'package:scheduling/features/clients/widgets/fields/client_search_field.dart';
import 'package:scheduling/l10n/l10n.dart';

void main() {
  List<ClientRecord> manyClients(int n) => [
    for (var i = 0; i < n; i++)
      ClientRecord(id: 'c$i', name: 'Client $i', phone: '555-00$i'),
  ];

  Widget harness(
    List<ClientRecord> results, {
    ValueChanged<ClientRecord>? onSelect,
    VoidCallback? onAddNew,
    String query = 'Client',
  }) {
    return MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: ClientSearchField(
          controller: TextEditingController(text: query),
          selectedClient: null,
          results: results,
          isSearching: false,
          onChanged: (_) {},
          onSelect: onSelect ?? (_) {},
          onClear: () {},
          onAddNew: onAddNew,
        ),
      ),
    );
  }

  final addTile = find.byIcon(Icons.person_add_alt_1);

  testWidgets('a result beyond the old 5-item cap is reachable by scrolling', (
    tester,
  ) async {
    final selected = <ClientRecord>[];
    await tester.pumpWidget(
      harness(manyClients(12), onSelect: selected.add),
    );
    await tester.pumpAndSettle();

    // The 11th result would have been hidden by the old take(5) cap.
    final target = find.text('Client 11');
    await tester.scrollUntilVisible(
      target,
      80,
      scrollable: find.byType(Scrollable).last,
    );
    expect(target, findsOneWidget);

    await tester.tap(target);
    await tester.pumpAndSettle();
    expect(selected.single.id, 'c11');
    expect(tester.takeException(), isNull);
  });

  testWidgets('no results with onAddNew shows the add-new tile and fires it', (
    tester,
  ) async {
    var tapped = false;
    await tester.pumpWidget(
      harness(const [], onAddNew: () => tapped = true),
    );
    await tester.pumpAndSettle();

    expect(addTile, findsOneWidget);
    expect(find.text('Add "Client" as a new client'), findsOneWidget);

    await tester.tap(addTile);
    await tester.pumpAndSettle();
    expect(tapped, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('results present still offer the add-new tile as a footer', (
    tester,
  ) async {
    var tapped = false;
    await tester.pumpWidget(
      harness(manyClients(2), onAddNew: () => tapped = true),
    );
    await tester.pumpAndSettle();

    expect(find.text('Client 0'), findsOneWidget);
    expect(addTile, findsOneWidget);

    await tester.tap(addTile);
    await tester.pumpAndSettle();
    expect(tapped, isTrue);
  });

  testWidgets('no add-new affordance when onAddNew is null', (tester) async {
    await tester.pumpWidget(harness(const []));
    await tester.pumpAndSettle();

    expect(addTile, findsNothing);
    // Falls back to the plain no-results text.
    expect(find.text('No clients found'), findsOneWidget);
  });

  testWidgets('no add-new tile while the query is empty', (tester) async {
    await tester.pumpWidget(
      harness(const [], onAddNew: () {}, query: ''),
    );
    await tester.pumpAndSettle();

    expect(addTile, findsNothing);
  });
}

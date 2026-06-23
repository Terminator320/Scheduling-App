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
          controller: TextEditingController(text: 'Client'),
          selectedClient: null,
          results: results,
          isSearching: false,
          onChanged: (_) {},
          onSelect: onSelect ?? (_) {},
          onClear: () {},
        ),
      ),
    );
  }

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
}

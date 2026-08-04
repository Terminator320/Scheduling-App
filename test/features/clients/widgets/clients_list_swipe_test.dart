import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:scheduling/core/theme/theme_notifier.dart';
import 'package:scheduling/core/theme/themes.dart';
import 'package:scheduling/features/clients/application/clients_providers.dart';
import 'package:scheduling/features/clients/domain/clients_repository.dart';
import 'package:scheduling/features/clients/domain/models/client_record.dart';
import 'package:scheduling/features/clients/widgets/cards/client_tile.dart';
import 'package:scheduling/features/clients/widgets/views/clients_list_view.dart';
import 'package:scheduling/l10n/l10n.dart';

class _MockClientsRepo extends Mock implements ClientsRepository {}

ClientRecord _clientWithJobs(int jobs) =>
    ClientRecord(id: 'c1', name: 'Acme', jobCount: jobs);

Widget _wrap(ClientsRepository repo) => ProviderScope(
  overrides: [clientsRepositoryProvider.overrideWithValue(repo)],
  child: ThemeNotifier(
    themeMode: ThemeMode.light,
    toggleTheme: () {},
    textScale: 1,
    setTextScale: (_) {},
    setLanguage: (_) {},
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: lightTheme(),
      home: const Scaffold(
        body: ClientsListView(searchQuery: '', isAdmin: true),
      ),
    ),
  ),
);

Future<void> _pumpAndSwipe(WidgetTester tester, ClientRecord client) async {
  final repo = _MockClientsRepo();
  when(
    () => repo.fetchClientsPage(
      after: any(named: 'after'),
      limit: any(named: 'limit'),
    ),
  ).thenAnswer((_) async => [client]);

  await tester.pumpWidget(_wrap(repo));
  await tester.pumpAndSettle();
  await tester.drag(find.byType(ClientTile).first, const Offset(-300, 0));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('swipe offers Archive but not Delete for a client with history', (
    tester,
  ) async {
    await _pumpAndSwipe(tester, _clientWithJobs(12));

    // canDeleteClient is advisory UI: the server would refuse this delete, so
    // the swipe must not offer it in the first place.
    expect(find.text('Archive'), findsOneWidget);
    expect(find.text('Delete'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('swipe offers Delete only when there are no jobs', (
    tester,
  ) async {
    await _pumpAndSwipe(tester, _clientWithJobs(0));

    expect(find.text('Archive'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an unknown job count withholds Delete', (tester) async {
    // jobCount is lazily backfilled, so null means "not counted yet".
    await _pumpAndSwipe(tester, const ClientRecord(id: 'c1', name: 'Acme'));

    expect(find.text('Archive'), findsOneWidget);
    expect(find.text('Delete'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

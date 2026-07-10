import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:scheduling/core/theme/theme_notifier.dart';
import 'package:scheduling/core/theme/themes.dart';
import 'package:scheduling/features/clients/application/clients_providers.dart';
import 'package:scheduling/features/clients/domain/clients_repository.dart';
import 'package:scheduling/features/clients/domain/models/client_record.dart';
import 'package:scheduling/features/clients/widgets/views/clients_list_view.dart';
import 'package:scheduling/l10n/l10n.dart';

class _MockClientsRepo extends Mock implements ClientsRepository {}

const _sophie = ClientRecord(
  id: 'c1',
  name: 'Sophie Tremblay',
  phone: '514-555-0101',
  email: 'sophie@example.com',
);

Widget _wrap(ClientsRepository repo, {String searchQuery = ''}) {
  return ProviderScope(
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
        home: Scaffold(
          body: ClientsListView(searchQuery: searchQuery, isAdmin: true),
        ),
      ),
    ),
  );
}

void main() {
  late _MockClientsRepo repo;

  setUp(() {
    repo = _MockClientsRepo();
    when(
      () => repo.fetchClientsPage(
        after: any(named: 'after'),
        limit: any(named: 'limit'),
      ),
    ).thenAnswer((_) async => const []);
  });

  testWidgets('search error offers a Retry that re-runs the search', (
    tester,
  ) async {
    when(() => repo.searchClients(any())).thenThrow(Exception('boom'));

    // Start with an empty query, then type one, so the debounce commits the
    // search the way live typing does.
    await tester.pumpWidget(_wrap(repo));
    await tester.pumpAndSettle();
    await tester.pumpWidget(_wrap(repo, searchQuery: 'sophie'));
    // Let the search debounce commit, then the provider fail.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.textContaining("Couldn't load clients"), findsOneWidget);

    when(
      () => repo.searchClients(any()),
    ).thenAnswer((_) async => const [_sophie]);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Sophie'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'committed search results refresh after a clientsRefresh bump '
    '(deleted client disappears)',
    (tester) async {
      when(
        () => repo.searchClients(any()),
      ).thenAnswer((_) async => const [_sophie]);

      await tester.pumpWidget(_wrap(repo));
      await tester.pumpAndSettle();
      await tester.pumpWidget(_wrap(repo, searchQuery: 'sophie'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(find.textContaining('Sophie'), findsWidgets);

      // Simulate a delete flow: the repository stops returning the client and
      // the write path bumps clientsRefreshProvider.
      when(() => repo.searchClients(any())).thenAnswer((_) async => const []);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ClientsListView)),
      );
      container.read(clientsRefreshProvider.notifier).bump();
      await tester.pumpAndSettle();

      expect(find.textContaining('Sophie'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}

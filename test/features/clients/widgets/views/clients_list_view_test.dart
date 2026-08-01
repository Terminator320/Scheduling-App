import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:scheduling/core/theme/theme_notifier.dart';
import 'package:scheduling/core/theme/themes.dart';
import 'package:scheduling/features/clients/application/clients_providers.dart';
import 'package:scheduling/features/clients/domain/clients_repository.dart';
import 'package:scheduling/features/clients/domain/models/client_record.dart';
import 'package:scheduling/features/clients/domain/models/client_type.dart';
import 'package:scheduling/features/clients/widgets/views/clients_list_view.dart';
import 'package:scheduling/l10n/l10n.dart';

class _MockClientsRepo extends Mock implements ClientsRepository {}

const _sophie = ClientRecord(
  id: 'c1',
  name: 'Sophie Tremblay',
  phone: '514-555-0101',
  email: 'sophie@example.com',
);

Widget _wrap(
  ClientsRepository repo, {
  String searchQuery = '',
  ClientType? selectedType,
}) {
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
          body: ClientsListView(
            searchQuery: searchQuery,
            isAdmin: true,
            selectedType: selectedType,
          ),
        ),
      ),
    ),
  );
}

void main() {
  late _MockClientsRepo repo;

  // mocktail needs a concrete instance before any(<ClientType>) is usable.
  setUpAll(() => registerFallbackValue(ClientType.unset));

  setUp(() {
    repo = _MockClientsRepo();
    when(
      () => repo.fetchClientsPage(
        after: any(named: 'after'),
        limit: any(named: 'limit'),
      ),
    ).thenAnswer((_) async => const []);
    when(
      () => repo.fetchClientsByType(any()),
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

  testWidgets('the type filter renders only that type of client', (
    tester,
  ) async {
    when(() => repo.fetchClientsByType(ClientType.commercial)).thenAnswer(
      (_) async => const [
        ClientRecord(
          id: 'v1',
          name: 'Commercial Client',
          type: ClientType.commercial,
        ),
      ],
    );

    await tester.pumpWidget(_wrap(repo, selectedType: ClientType.commercial));
    await tester.pumpAndSettle();

    expect(find.text('Commercial Client'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the type filter never touches the paginated list', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(repo, selectedType: ClientType.commercial));
    await tester.pumpAndSettle();

    // It is a separate bounded read. Filtering the paginated list in Dart would
    // shorten a full server page and stop paging early.
    verifyNever(
      () => repo.fetchClientsPage(
        after: any(named: 'after'),
        limit: any(named: 'limit'),
      ),
    );
    verify(() => repo.fetchClientsByType(ClientType.commercial)).called(1);
  });

  testWidgets('searching within a type filters that type', (tester) async {
    when(() => repo.fetchClientsByType(ClientType.commercial)).thenAnswer(
      (_) async => const [
        ClientRecord(
          id: 'v1',
          name: 'Sophie Tremblay',
          type: ClientType.commercial,
        ),
        ClientRecord(
          id: 'v2',
          name: 'Marc Gagnon',
          type: ClientType.commercial,
        ),
      ],
    );

    await tester.pumpWidget(
      _wrap(repo, selectedType: ClientType.commercial, searchQuery: 'sophie'),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Sophie'), findsOneWidget);
    expect(find.textContaining('Marc'), findsNothing);
    // Matched locally against the bounded list, not via a second server query.
    verifyNever(() => repo.searchClients(any()));
  });

  testWidgets('an empty type result shows the type empty state', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(repo, selectedType: ClientType.commercial));
    await tester.pumpAndSettle();

    expect(find.textContaining('No Commercial clients'), findsOneWidget);
  });
}

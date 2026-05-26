import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:scheduling/core/theme/theme_notifier.dart';
import 'package:scheduling/core/theme/themes.dart';
import 'package:scheduling/features/clients/application/clients_providers.dart';
import 'package:scheduling/features/clients/domain/clients_repository.dart';
import 'package:scheduling/features/clients/domain/models/client_record.dart';
import 'package:scheduling/features/clients/screens/clients_screen.dart';
import 'package:scheduling/l10n/l10n.dart';

class _MockClientsRepo extends Mock implements ClientsRepository {}

const _alice = ClientRecord(
  id: 'c1',
  name: 'Alice Brown',
  phone: '555-0101',
  address: '1 Main St',
  email: 'alice@example.com',
);

const _bob = ClientRecord(
  id: 'c2',
  name: 'Bob Carter',
  phone: '555-0202',
  address: '2 Main St',
  email: 'bob@example.com',
);

Widget _wrap(ClientsRepository repo) {
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
        home: const ListInformation(
          mode: 'Clients',
          isAdmin: true,
          employeeId: 'admin',
        ),
      ),
    ),
  );
}

void main() {
  late _MockClientsRepo repo;

  setUp(() {
    repo = _MockClientsRepo();
  });

  testWidgets('renders the first page of client names', (tester) async {
    when(
      () => repo.fetchClientsPage(
        after: any(named: 'after'),
        limit: any(named: 'limit'),
      ),
    ).thenAnswer((_) async => const [_alice, _bob]);

    await tester.pumpWidget(_wrap(repo));
    await tester.pumpAndSettle();

    expect(find.textContaining('Alice'), findsWidgets);
    expect(find.textContaining('Bob'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows empty-state copy when the page is empty', (tester) async {
    when(
      () => repo.fetchClientsPage(
        after: any(named: 'after'),
        limit: any(named: 'limit'),
      ),
    ).thenAnswer((_) async => const []);

    await tester.pumpWidget(_wrap(repo));
    await tester.pumpAndSettle();

    expect(find.textContaining('No clients'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows fallback copy when the first page errors', (tester) async {
    when(
      () => repo.fetchClientsPage(
        after: any(named: 'after'),
        limit: any(named: 'limit'),
      ),
    ).thenThrow(Exception('boom'));

    await tester.pumpWidget(_wrap(repo));
    await tester.pumpAndSettle();

    expect(find.textContaining("Couldn't load clients"), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

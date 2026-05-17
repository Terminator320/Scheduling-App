import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/core/theme/theme_notifier.dart';
import 'package:scheduling/core/theme/themes.dart';
import 'package:scheduling/features/clients/application/clients_providers.dart';
import 'package:scheduling/features/clients/domain/models/client_record.dart';
import 'package:scheduling/features/clients/screens/clients_screen.dart';
import 'package:scheduling/l10n/app_localizations.dart';

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

Widget _wrap({required Stream<List<ClientRecord>> clients}) {
  return ProviderScope(
    overrides: [clientsStreamProvider.overrideWith((_) => clients)],
    child: ThemeNotifier(
      themeMode: ThemeMode.light,
      toggleTheme: () {},
      textScale: 1.0,
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
  testWidgets('renders client names from the stream', (tester) async {
    await tester.pumpWidget(_wrap(clients: Stream.value(const [_alice, _bob])));
    await tester.pumpAndSettle();

    expect(find.textContaining('Alice'), findsWidgets);
    expect(find.textContaining('Bob'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows empty-state copy when the list is empty', (tester) async {
    await tester.pumpWidget(_wrap(clients: Stream.value(const [])));
    await tester.pumpAndSettle();

    expect(find.textContaining('No clients'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows fallback copy when the stream errors', (tester) async {
    await tester.pumpWidget(_wrap(clients: Stream.error(StateError('boom'))));
    await tester.pumpAndSettle();

    expect(find.textContaining('Something went wrong'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

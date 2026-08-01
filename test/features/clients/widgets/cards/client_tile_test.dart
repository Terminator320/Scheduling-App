import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/core/theme/theme_notifier.dart';
import 'package:scheduling/core/theme/themes.dart';
import 'package:scheduling/features/clients/domain/models/client_record.dart';
import 'package:scheduling/features/clients/domain/models/client_type.dart';
import 'package:scheduling/features/clients/widgets/cards/client_tile.dart';
import 'package:scheduling/l10n/l10n.dart';

Widget _harness(ClientRecord client) => ThemeNotifier(
  themeMode: ThemeMode.light,
  toggleTheme: () {},
  textScale: 1,
  setTextScale: (_) {},
  setLanguage: (_) {},
  child: MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: lightTheme(),
    home: Scaffold(body: ClientTile(client: client)),
  ),
);

void main() {
  testWidgets('shows the address as the subtitle', (tester) async {
    await tester.pumpWidget(
      _harness(
        const ClientRecord(id: 'c1', name: 'Acme', address: '12 Main St'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Acme'), findsOneWidget);
    expect(find.text('12 Main St'), findsOneWidget);
  });

  testWidgets('falls back to the phone when there is no address', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        const ClientRecord(id: 'c1', name: 'Acme', phone: '514-555-0101'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('514-555-0101'), findsOneWidget);
  });

  testWidgets('renders the job count when the trigger has written it', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(const ClientRecord(id: 'c1', name: 'Acme', jobCount: 12)),
    );
    await tester.pumpAndSettle();

    expect(find.text('12'), findsOneWidget);
    expect(find.text('JOBS'), findsOneWidget);
  });

  testWidgets('renders nothing when the job count is not written yet', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(const ClientRecord(id: 'c1', name: 'Acme')),
    );
    await tester.pumpAndSettle();

    // Never "0" — a missing count is unknown, not zero.
    expect(find.text('0'), findsNothing);
    expect(find.text('JOBS'), findsNothing);
  });

  testWidgets('renders the type chip', (tester) async {
    await tester.pumpWidget(
      _harness(
        const ClientRecord(
          id: 'c1',
          name: 'Acme',
          type: ClientType.commercial,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Commercial'), findsOneWidget);
  });

  testWidgets('a typeless client renders no chip', (tester) async {
    await tester.pumpWidget(
      _harness(const ClientRecord(id: 'c1', name: 'Acme', jobCount: 3)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Commercial'), findsNothing);
    expect(find.text('Residential'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

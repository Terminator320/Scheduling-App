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
    home: Scaffold(
      body: ClientTile(client: client),
    ),
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

  testWidgets('an archived client shows the Archived pill', (tester) async {
    await tester.pumpWidget(
      _harness(ClientRecord.fromMap('c1', {'name': 'Acme', 'archived': true})),
    );
    await tester.pumpAndSettle();

    // Archived clients still turn up in search, so the row has to say so.
    expect(find.text('Archived'), findsOneWidget);
  });

  testWidgets('an active client shows no Archived pill', (tester) async {
    await tester.pumpWidget(
      _harness(ClientRecord.fromMap('c1', {'name': 'Acme'})),
    );
    await tester.pumpAndSettle();

    expect(find.text('Archived'), findsNothing);
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

  // Type and shared-address moved off the row on 2026-09-04 — four signals
  // competed under one name. Type lives in the filter sheet now, the
  // shared-address count on the client detail.
  testWidgets('no longer renders a type chip', (tester) async {
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

    expect(find.text('Commercial'), findsNothing);
    expect(find.text('Residential'), findsNothing);
  });

  testWidgets('no longer marks a shared address as a building', (tester) async {
    await tester.pumpWidget(
      _harness(
        const ClientRecord(
          id: 'c1',
          name: 'Acme',
          address: '914-4450 Prom. Paton',
          type: ClientType.building,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Building'), findsNothing);
  });

  testWidgets('the archived badge survives on a small phone at 2x text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(260, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: _harness(
          const ClientRecord(
            id: 'c1',
            name: 'Acme Property Holdings',
            address: '914-4450 Prom. Paton',
            archived: true,
            type: ClientType.building,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Archived'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

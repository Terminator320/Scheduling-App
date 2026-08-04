import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';


import 'package:scheduling/core/utils/date_utils_helper.dart';
import 'package:scheduling/features/calendar/widgets/sheets/add_appointment_sheet.dart';
import 'package:scheduling/features/clients/domain/models/client_record.dart';
import 'package:scheduling/l10n/l10n.dart';

import '../../../support/tour_test_support.dart';

const _client = ClientRecord(
  id: 'c1',
  name: 'Acme Plumbing',
  address: '12 Main St',
);

Widget _harness({ClientRecord? initialClient, DateTime? initialDate}) =>
    ProviderScope(
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: AddEventSheet(
            initialClient: initialClient,
            initialDate: initialDate,
          ),
        ),
      ),
    );

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    markFormToursSeen();
  });

  testWidgets('initialClient pre-seeds the client field', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_harness(initialClient: _client));
    await tester.pumpAndSettle();

    expect(find.text('Acme Plumbing'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('no initialClient leaves the client field empty', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();

    expect(find.text('Acme Plumbing'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('picking a later end date turns the draft into a multi-day run', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // Aug 1 2026 — the day defaults, so it is left off to satisfy the linter.
    await tester.pumpWidget(_harness(initialDate: DateTime(2026, 8)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('End date'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(DatePickerDialog),
        matching: find.text('3'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(
      find.text(DateUtilsHelper.formatDate(DateTime(2026, 8, 3))),
      findsOneWidget,
    );
    expect(find.text('3 days'), findsOneWidget);
    expect(find.text('Start time · each day'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/core/theme/themes.dart';
import 'package:scheduling/features/calendar/widgets/dialogs/delete_appointment_dialog.dart';
import 'package:scheduling/features/calendar/widgets/dialogs/series_scope_dialog.dart';
import 'package:scheduling/l10n/l10n.dart';

/// The MAPPING this launcher performs, which nothing covered.
///
/// Both building blocks it delegates to (`showConfirmDialog`,
/// `showSeriesScopeDialog`) are near-fully covered on their own; what was at 0%
/// is the translation between them — a confirmed one-off becoming
/// `SeriesScopeChoice.thisOnly` and a cancel becoming `null`. Getting that
/// backwards deletes a whole repeat series when the user asked for one visit,
/// which is not recoverable from the app.
void main() {
  // `returned` distinguishes "not called back yet" from "returned null".
  SeriesScopeChoice? choice;
  var returned = false;

  Future<void> open(WidgetTester tester, {required bool isSeries}) async {
    choice = null;
    returned = false;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        theme: lightTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () async {
                  choice = await showDeleteAppointmentDialog(
                    context,
                    isSeries: isSeries,
                  );
                  returned = true;
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  group('a one-off visit', () {
    testWidgets('confirming maps to thisOnly', (tester) async {
      await open(tester, isSeries: false);

      expect(find.text('Delete Appointment'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(returned, isTrue);
      expect(choice, SeriesScopeChoice.thisOnly);
    });

    testWidgets('cancelling maps to null, not to a scope', (tester) async {
      // `null` is what the caller reads as "do nothing". Returning a scope
      // here would delete the job the user just backed out of.
      await open(tester, isSeries: false);

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(returned, isTrue);
      expect(choice, isNull);
    });

    testWidgets('never offers a series scope', (tester) async {
      await open(tester, isSeries: false);

      expect(find.text('Delete this visit only'), findsNothing);
      expect(find.text('Delete this and future visits'), findsNothing);
    });
  });

  group('a repeating visit', () {
    testWidgets('routes to the scope dialog and returns the pick', (
      tester,
    ) async {
      await open(tester, isSeries: true);

      expect(find.text('Delete this and future visits'), findsOneWidget);
      await tester.tap(find.text('Delete this and future visits'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(FilledButton, 'Delete Appointment'),
      );
      await tester.pumpAndSettle();

      expect(choice, SeriesScopeChoice.thisAndFuture);
    });

    testWidgets('defaults to this-visit-only, the safer of the two', (
      tester,
    ) async {
      // A mis-set default is the difference between removing one visit and
      // removing every remaining one.
      await open(tester, isSeries: true);

      await tester.tap(
        find.widgetWithText(FilledButton, 'Delete Appointment'),
      );
      await tester.pumpAndSettle();

      expect(choice, SeriesScopeChoice.thisOnly);
    });

    testWidgets('backing out maps to null', (tester) async {
      // The scope dialog's dismiss is labelled "Back", not "Cancel" — the
      // one-off path above uses the shared confirm dialog, which is not the
      // same control.
      await open(tester, isSeries: true);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Back'));
      await tester.pumpAndSettle();

      expect(returned, isTrue);
      expect(choice, isNull);
    });
  });
}

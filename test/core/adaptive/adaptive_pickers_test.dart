// On an iOS-only app these two files are the SOLE path by which anyone picks
// an appointment start time, an end time, a date, or an employee's working
// hours — five call sites, and neither file was imported by any test.
//
// The logic that can actually be wrong: the platform branch, the
// firstDate/lastDate clamp applied before the wheel ever renders, the mutable
// `tempPicked` the wheel writes into, and Cancel -> null vs Done -> onDone().
// A clamp that stopped firing hands `CupertinoDatePicker` an initialDateTime
// outside [minimumDate, maximumDate], which is an assertion failure on a
// screen the admin uses daily.

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/core/adaptive/adaptive_pickers.dart';
import 'package:scheduling/core/adaptive/cupertino_time_picker.dart';
import 'package:scheduling/l10n/l10n.dart';

void main() {
  late BuildContext hostContext;

  Future<void> pumpHost(
    WidgetTester tester, {
    TargetPlatform platform = TargetPlatform.iOS,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: platform),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) {
            hostContext = context;
            return const Scaffold(body: SizedBox.shrink());
          },
        ),
      ),
    );
  }

  CupertinoDatePicker wheel(WidgetTester tester) =>
      tester.widget<CupertinoDatePicker>(find.byType(CupertinoDatePicker));

  Future<void> tapCancel(WidgetTester tester) async {
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  }

  Future<void> tapDone(WidgetTester tester) async {
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
  }

  group('showCupertinoDatePickerSheet', () {
    testWidgets('Done returns the seeded date when the wheel is untouched', (
      tester,
    ) async {
      await pumpHost(tester);
      final result = showCupertinoDatePickerSheet(
        hostContext,
        initialDate: DateTime(2026, 8, 19),
        firstDate: DateTime(2026),
        lastDate: DateTime(2026, 12, 31),
      );
      await tester.pumpAndSettle();

      await tapDone(tester);

      expect(await result, DateTime(2026, 8, 19));
    });

    testWidgets('Cancel resolves to null, not to the seeded date', (
      tester,
    ) async {
      await pumpHost(tester);
      final result = showCupertinoDatePickerSheet(
        hostContext,
        initialDate: DateTime(2026, 8, 19),
        firstDate: DateTime(2026),
        lastDate: DateTime(2026, 12, 31),
      );
      await tester.pumpAndSettle();

      await tapCancel(tester);

      // A non-null Cancel would silently overwrite the field the user chose
      // to leave alone.
      expect(await result, isNull);
    });

    testWidgets('the wheel writes through to what Done returns', (
      tester,
    ) async {
      await pumpHost(tester);
      final result = showCupertinoDatePickerSheet(
        hostContext,
        initialDate: DateTime(2026, 8, 19),
        firstDate: DateTime(2026),
        lastDate: DateTime(2026, 12, 31),
      );
      await tester.pumpAndSettle();

      // The mutable `tempPicked`: the wheel reports every scroll here, and
      // Done reads the LAST one. Capturing it once at build time instead would
      // make every pick return the seed.
      wheel(tester).onDateTimeChanged(DateTime(2026, 9, 2));
      await tester.pumpAndSettle();
      await tapDone(tester);

      expect(await result, DateTime(2026, 9, 2));
    });

    testWidgets('an initial date before firstDate is clamped up to it', (
      tester,
    ) async {
      await pumpHost(tester);
      final firstDate = DateTime(2026, 8);
      final result = showCupertinoDatePickerSheet(
        hostContext,
        initialDate: DateTime(2026, 5, 4),
        firstDate: firstDate,
        lastDate: DateTime(2026, 12, 31),
      );
      await tester.pumpAndSettle();

      // Clamped BEFORE the wheel is built — CupertinoDatePicker asserts on an
      // initialDateTime outside its bounds.
      expect(wheel(tester).initialDateTime, firstDate);
      await tapDone(tester);
      expect(await result, firstDate);
    });

    testWidgets('an initial date after lastDate is clamped down to it', (
      tester,
    ) async {
      await pumpHost(tester);
      final lastDate = DateTime(2026, 9, 30);
      final result = showCupertinoDatePickerSheet(
        hostContext,
        initialDate: DateTime(2027, 3, 4),
        firstDate: DateTime(2026, 8),
        lastDate: lastDate,
      );
      await tester.pumpAndSettle();

      expect(wheel(tester).initialDateTime, lastDate);
      await tapDone(tester);
      expect(await result, lastDate);
    });

    testWidgets('the time of day is dropped from the seed', (tester) async {
      await pumpHost(tester);
      final result = showCupertinoDatePickerSheet(
        hostContext,
        initialDate: DateTime(2026, 8, 19, 14, 45),
        firstDate: DateTime(2026),
        lastDate: DateTime(2026, 12, 31),
      );
      await tester.pumpAndSettle();

      await tapDone(tester);

      // Date mode only ever means midnight; keeping 14:45 would make the
      // clamp comparisons disagree with the wheel.
      expect(await result, DateTime(2026, 8, 19));
    });

    testWidgets('the bounds are handed to the wheel, not just to the clamp', (
      tester,
    ) async {
      await pumpHost(tester);
      final firstDate = DateTime(2026, 8);
      final lastDate = DateTime(2026, 12, 31);
      final result = showCupertinoDatePickerSheet(
        hostContext,
        initialDate: DateTime(2026, 8, 19),
        firstDate: firstDate,
        lastDate: lastDate,
      );
      await tester.pumpAndSettle();

      expect(wheel(tester).minimumDate, firstDate);
      expect(wheel(tester).maximumDate, lastDate);
      await tapCancel(tester);
      await result;
    });
  });

  group('showCupertinoTimePicker', () {
    testWidgets('Done returns the seeded time', (tester) async {
      await pumpHost(tester);
      final result = showCupertinoTimePicker(
        hostContext,
        initialTime: const TimeOfDay(hour: 9, minute: 30),
      );
      await tester.pumpAndSettle();

      await tapDone(tester);

      expect(await result, const TimeOfDay(hour: 9, minute: 30));
    });

    testWidgets('Cancel resolves to null', (tester) async {
      await pumpHost(tester);
      final result = showCupertinoTimePicker(
        hostContext,
        initialTime: const TimeOfDay(hour: 9, minute: 30),
      );
      await tester.pumpAndSettle();

      await tapCancel(tester);

      expect(await result, isNull);
    });

    testWidgets('a scrolled wheel returns the new time, date part discarded', (
      tester,
    ) async {
      await pumpHost(tester);
      final result = showCupertinoTimePicker(
        hostContext,
        initialTime: const TimeOfDay(hour: 9, minute: 30),
      );
      await tester.pumpAndSettle();

      // The wheel reports a full DateTime; only hour/minute survive, so the
      // day the sheet happened to be opened on can never leak into the field.
      wheel(tester).onDateTimeChanged(DateTime(2001, 4, 5, 16, 15));
      await tester.pumpAndSettle();
      await tapDone(tester);

      expect(await result, const TimeOfDay(hour: 16, minute: 15));
    });

    testWidgets('the wheel is seeded in time mode from the initial time', (
      tester,
    ) async {
      await pumpHost(tester);
      final result = showCupertinoTimePicker(
        hostContext,
        initialTime: const TimeOfDay(hour: 17, minute: 5),
      );
      await tester.pumpAndSettle();

      expect(wheel(tester).mode, CupertinoDatePickerMode.time);
      expect(wheel(tester).initialDateTime.hour, 17);
      expect(wheel(tester).initialDateTime.minute, 5);
      await tapCancel(tester);
      await result;
    });
  });

  group('the adaptive wrappers pick a look from the theme platform', () {
    testWidgets('iOS gets the Cupertino date wheel', (tester) async {
      await pumpHost(tester);
      final result = showAdaptiveDatePicker(
        hostContext,
        initialDate: DateTime(2026, 8, 19),
        firstDate: DateTime(2026),
        lastDate: DateTime(2026, 12, 31),
      );
      await tester.pumpAndSettle();

      expect(find.byType(CupertinoDatePicker), findsOneWidget);
      expect(find.byType(CalendarDatePicker), findsNothing);
      await tapCancel(tester);
      await result;
    });

    testWidgets('a non-Cupertino platform gets the Material calendar', (
      tester,
    ) async {
      await pumpHost(tester, platform: TargetPlatform.android);
      final result = showAdaptiveDatePicker(
        hostContext,
        initialDate: DateTime(2026, 8, 19),
        firstDate: DateTime(2026),
        lastDate: DateTime(2026, 12, 31),
      );
      await tester.pumpAndSettle();

      expect(find.byType(DatePickerDialog), findsOneWidget);
      expect(find.byType(CupertinoDatePicker), findsNothing);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(await result, isNull);
    });

    testWidgets('iOS gets the Cupertino time wheel', (tester) async {
      await pumpHost(tester);
      final result = showAdaptiveTimePicker(
        hostContext,
        initialTime: const TimeOfDay(hour: 9, minute: 30),
      );
      await tester.pumpAndSettle();

      expect(find.byType(CupertinoDatePicker), findsOneWidget);
      await tapDone(tester);
      expect(await result, const TimeOfDay(hour: 9, minute: 30));
    });

    testWidgets('a non-Cupertino platform gets the Material time dialog', (
      tester,
    ) async {
      await pumpHost(tester, platform: TargetPlatform.android);
      final result = showAdaptiveTimePicker(
        hostContext,
        initialTime: const TimeOfDay(hour: 9, minute: 30),
      );
      await tester.pumpAndSettle();

      expect(find.byType(TimePickerDialog), findsOneWidget);
      expect(find.byType(CupertinoDatePicker), findsNothing);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(await result, isNull);
    });
  });
}

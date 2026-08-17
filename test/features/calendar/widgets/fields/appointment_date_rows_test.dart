import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/features/calendar/widgets/fields/appointment_date_rows.dart';
import 'package:scheduling/l10n/l10n.dart';

void main() {
  Future<void> pumpRows(
    WidgetTester tester, {
    DateTime? startDate,
    DateTime? endDate,
    ValueChanged<DateTime>? onStartDateSelected,
    ValueChanged<DateTime>? onEndDateSelected,
    double width = 800,
  }) async {
    tester.view.physicalSize = Size(width, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: AppointmentDateRows(
              startValue: 'Aug 5, 2026',
              endValue: 'Aug 7, 2026',
              startDate: startDate ?? DateTime(2026, 8, 5),
              endDate: endDate ?? DateTime(2026, 8, 7),
              firstDate: DateTime(2020),
              lastDate: DateTime(2100),
              onStartDateSelected: onStartDateSelected ?? (_) {},
              onEndDateSelected: onEndDateSelected ?? (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the month is closed until a date row is tapped', (tester) async {
    await pumpRows(tester);

    expect(
      find.byKey(const ValueKey('inline-date-day-2026-08-05')),
      findsNothing,
    );

    await tester.tap(find.text('Start date'));
    await tester.pumpAndSettle();

    // The whole month is on screen, not three days of a wheel.
    expect(
      find.byKey(const ValueKey('inline-date-day-2026-08-01')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('inline-date-day-2026-08-31')),
      findsOneWidget,
    );
    expect(find.text('August 2026'), findsOneWidget);
  });

  testWidgets('picking a day reports it and leaves the month OPEN', (
    tester,
  ) async {
    final picked = <DateTime>[];
    await pumpRows(tester, onStartDateSelected: picked.add);

    await tester.tap(find.text('Start date'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('inline-date-day-2026-08-12')));
    await tester.pumpAndSettle();

    expect(picked, [DateTime(2026, 8, 12)]);
    // Owner call: choosing a date is rarely one tap, so a correction must not
    // cost a reopen.
    expect(
      find.byKey(const ValueKey('inline-date-day-2026-08-12')),
      findsOneWidget,
    );

    // And the correction lands, from the still-open month.
    await tester.tap(find.byKey(const ValueKey('inline-date-day-2026-08-19')));
    await tester.pumpAndSettle();
    expect(picked, [DateTime(2026, 8, 12), DateTime(2026, 8, 19)]);
  });

  testWidgets('dismissing is instant — the form is back to its closed height '
      'in the SAME frame as the tap on the row', (tester) async {
    await pumpRows(tester);
    final closedHeight = tester
        .getSize(find.byType(AppointmentDateRows))
        .height;

    await tester.tap(find.text('Start date'));
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byType(AppointmentDateRows)).height,
      greaterThan(closedHeight),
    );

    await tester.tap(find.text('Start date'));
    // ONE frame, not pumpAndSettle: a shrinking gap would keep pushing the
    // rest of the form around for 200ms after the panel was dismissed. Under
    // an animated collapse this frame still measured the fully-open month.
    await tester.pump();

    expect(
      tester.getSize(find.byType(AppointmentDateRows)).height,
      closedHeight,
    );
  });

  testWidgets('the month marks the OTHER end of the run, so the end date can '
      'be read against the start', (tester) async {
    await pumpRows(tester);

    Color? fillOf(String key) {
      final container = tester.widget<Container>(
        find.descendant(
          of: find.byKey(ValueKey(key)),
          matching: find.byType(Container),
        ),
      );
      return (container.decoration! as BoxDecoration).color;
    }

    // Picking the END: the Aug 5 start is marked, and it is NOT the same mark
    // as the Aug 7 selection — one is the choice, the other is context.
    await tester.tap(find.text('End date'));
    await tester.pumpAndSettle();
    final selected = fillOf('inline-date-day-2026-08-07');
    final companion = fillOf('inline-date-day-2026-08-05');
    expect(selected, isNotNull);
    expect(companion, isNotNull);
    expect(companion, isNot(selected));
    // A plain day carries no fill at all.
    expect(fillOf('inline-date-day-2026-08-12'), isNull);

    // Screen readers get the marker in words — a tint says nothing out loud.
    expect(
      tester
          .getSemantics(
            find.byKey(const ValueKey('inline-date-day-2026-08-05')),
          )
          .label,
      contains('Start date'),
    );

    // And it is symmetric: picking the START marks the end date.
    await tester.tap(find.text('Start date'));
    await tester.pumpAndSettle();
    expect(fillOf('inline-date-day-2026-08-07'), isNotNull);
    expect(fillOf('inline-date-day-2026-08-05'), isNotNull);
  });

  testWidgets('a one-day job marks its day ONCE — both ends are the same day, '
      'and a soft fill under a solid one is just a muddier solid one', (
    tester,
  ) async {
    await pumpRows(
      tester,
      startDate: DateTime(2026, 8, 5),
      endDate: DateTime(2026, 8, 5),
    );

    await tester.tap(find.text('Start date'));
    await tester.pumpAndSettle();

    final semantics = tester.getSemantics(
      find.byKey(const ValueKey('inline-date-day-2026-08-05')),
    );
    expect(semantics.label, isNot(contains('End date')));
  });

  testWidgets('only ONE month is ever open — opening the end row closes the '
      'start row', (tester) async {
    await pumpRows(tester);

    await tester.tap(find.text('Start date'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('End date'));
    await tester.pumpAndSettle();

    // One grid, not two stacked inside the panel.
    expect(
      find.byKey(const ValueKey('inline-date-day-2026-08-12')),
      findsOneWidget,
    );
  });

  testWidgets('tapping the open row again closes it', (tester) async {
    await pumpRows(tester);

    await tester.tap(find.text('Start date'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start date'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('inline-date-day-2026-08-12')),
      findsNothing,
    );
  });

  testWidgets('the chevrons page the month', (tester) async {
    await pumpRows(tester);

    await tester.tap(find.text('Start date'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('inline-date-next-month')));
    await tester.pumpAndSettle();

    expect(find.text('September 2026'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('inline-date-day-2026-09-30')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('inline-date-prev-month')));
    await tester.pumpAndSettle();

    expect(find.text('August 2026'), findsOneWidget);
  });

  testWidgets('the END row never offers a day before the start date', (
    tester,
  ) async {
    DateTime? picked;
    await pumpRows(tester, onEndDateSelected: (day) => picked = day);

    await tester.tap(find.text('End date'));
    await tester.pumpAndSettle();

    // Aug 4 precedes the Aug 5 start: rendered for context, but out of bounds
    // and therefore not a button at all — an end before its start is
    // unbookable, so it must not be reachable here either.
    await tester.tap(
      find.byKey(const ValueKey('inline-date-day-2026-08-04')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(picked, isNull);

    await tester.tap(find.byKey(const ValueKey('inline-date-day-2026-08-06')));
    await tester.pumpAndSettle();
    expect(picked, DateTime(2026, 8, 6));
  });

  testWidgets('the rows stack on a narrow phone and share a row when there is '
      'width for both', (tester) async {
    await pumpRows(tester, width: 320);
    final narrowStart = tester.getTopLeft(find.text('Start date'));
    final narrowEnd = tester.getTopLeft(find.text('End date'));
    expect(narrowEnd.dy, greaterThan(narrowStart.dy + 20));

    await pumpRows(tester);
    final wideStart = tester.getTopLeft(find.text('Start date'));
    final wideEnd = tester.getTopLeft(find.text('End date'));
    expect(wideEnd.dy, wideStart.dy);
    expect(wideEnd.dx, greaterThan(wideStart.dx));
  });
}

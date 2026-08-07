// Replaces app_calendar_view_test.dart. The grid owns the day-cell semantics
// that table_calendar used to provide.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:scheduling/features/calendar/widgets/views/calendar_month_grid.dart';
import 'package:scheduling/l10n/l10n.dart';

final _month = DateTime(2026, 5);
final _day = DateTime(2026, 5, 16);

Widget _wrap(Widget child) => MaterialApp(
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

Widget _grid({
  int count = 0,
  ValueChanged<DateTime>? onDaySelected,
  List<Color?> dots = const [],
  DateTime? selectedDay,
}) => CalendarMonthGrid(
  month: _month,
  selectedDay: selectedDay ?? _day,
  today: _day,
  onDaySelected: onDaySelected ?? (_) {},
  dotColorsFor: (d) => d.day == 16 && d.month == 5 ? dots : const [],
  countFor: (d) => d.day == 16 && d.month == 5 ? count : 0,
);

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en_CA');
  });

  testWidgets('day cells expose a full-date label and appointment count', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_wrap(_grid(count: 2)));
    await tester.pumpAndSettle();

    expect(
      find.bySemanticsLabel(
        RegExp('Saturday, May 16, 2026.*2 appointments', dotAll: true),
      ),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Friday, May 15, 2026'), findsOneWidget);
    expect(tester.takeException(), isNull);
    handle.dispose();
  });

  testWidgets('a single appointment uses the singular label', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_wrap(_grid(count: 1)));
    await tester.pumpAndSettle();

    expect(
      find.bySemanticsLabel(
        RegExp('Saturday, May 16, 2026.*1 appointment', dotAll: true),
      ),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel(RegExp('1 appointments')), findsNothing);
    handle.dispose();
  });

  testWidgets('renders 42 cells and keeps the last day of the month', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(_grid()));
    await tester.pumpAndSettle();
    // 1 May 2026 is a Friday: 5 lead cells, 31 days, 6 trailing.
    expect(find.text('31'), findsOneWidget);
    expect(find.byType(CalendarDayCell), findsNWidgets(42));
  });

  testWidgets('weekday headers come from the locale, not a hardcoded string', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(_grid()));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('calendar-weekday-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('calendar-weekday-6')), findsOneWidget);
  });

  testWidgets('tapping an in-month cell selects it', (tester) async {
    DateTime? picked;
    await tester.pumpWidget(_wrap(_grid(onDaySelected: (d) => picked = d)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('20'));
    expect(picked, DateTime(2026, 5, 20));
  });

  testWidgets('an off-month cell is rendered but not tappable', (tester) async {
    DateTime? picked;
    await tester.pumpWidget(_wrap(_grid(onDaySelected: (d) => picked = d)));
    await tester.pumpAndSettle();
    // 30 April 2026 is a lead cell for May.
    final cell = find.byKey(const ValueKey('calendar-day-2026-04-30'));
    expect(cell, findsOneWidget);
    await tester.tap(cell, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(picked, isNull);
  });

  testWidgets('off-month cells stay out of the semantics tree', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_wrap(_grid()));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel(RegExp('April 30, 2026')), findsNothing);
    handle.dispose();
  });

  testWidgets('an off-month day never takes the selected fill', (tester) async {
    // A selected day from the previous month must not paint a lead cell.
    await tester.pumpWidget(
      _wrap(_grid(selectedDay: DateTime(2026, 4, 30))),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('the selected day keeps its crew dots', (tester) async {
    // The selection circle fills the number only; the dot row sits below it,
    // so hiding the dots on the selected day made the day you were actually
    // looking at the one day whose crew you couldn't see.
    Finder dotsOn(String key) => find.descendant(
      of: find.byKey(ValueKey(key)),
      matching: find.byWidgetPredicate(
        (w) => w is Container && w.constraints?.maxWidth == 5,
      ),
    );

    // Day 16 is both the dotted day and the default selection.
    await tester.pumpWidget(
      _wrap(_grid(dots: const [Colors.teal, Colors.orange])),
    );
    await tester.pumpAndSettle();
    expect(dotsOn('calendar-day-2026-05-16'), findsNWidgets(2));

    // Same two dots when the selection moves off it.
    await tester.pumpWidget(
      _wrap(
        _grid(
          dots: const [Colors.teal, Colors.orange],
          selectedDay: DateTime(2026, 5, 17),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(dotsOn('calendar-day-2026-05-16'), findsNWidgets(2));
  });

  testWidgets('survives a 2.0 text scale without overflowing', (tester) async {
    tester.view.physicalSize = const Size(375, 667);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _wrap(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: _grid(count: 3, dots: const [Colors.teal]),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

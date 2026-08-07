import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:scheduling/features/calendar/domain/month_grid.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en_CA');
    await initializeDateFormatting('fr_CA');
  });

  test('renders whole weeks, and only the weeks the month occupies', () {
    for (var m = 1; m <= 12; m++) {
      final month = DateTime(2026, m);
      final days = monthGridDays(month, weekStart: 0);
      final rows = monthGridRowCount(month, weekStart: 0);
      expect(days, hasLength(7 * rows));
      expect(rows, inInclusiveRange(4, monthGridMaxRows));
      // Every day of the month is present …
      expect(days.where((d) => d.month == m && d.year == 2026), hasLength(
        DateTime(2026, m + 1, 0).day,
      ));
      // … and no trailing week is entirely outside it.
      expect(
        days.skip(7 * (rows - 1)).any((d) => isInMonth(d, month)),
        isTrue,
        reason: 'last row of month $m is all off-month',
      );
    }
  });

  test('August 2026 keeps its last day — the 35-cell bug', () {
    // 1 Aug 2026 is a Saturday: 6 lead cells + 31 days = 37 > 35, so this is
    // the month that still needs a sixth week.
    final days = monthGridDays(DateTime(2026, 8), weekStart: 0);
    expect(monthGridRowCount(DateTime(2026, 8), weekStart: 0), 6);
    expect(days.first, DateTime(2026, 7, 26));
    expect(days.contains(DateTime(2026, 8, 31)), isTrue);
    expect(days.last, DateTime(2026, 9, 5));
  });

  test('February 2026 is exactly four weeks — no lead, no trail', () {
    // 1 Feb 2026 is a Sunday and the month has 28 days.
    expect(monthGridRowCount(DateTime(2026, 2), weekStart: 0), 4);
    final days = monthGridDays(DateTime(2026, 2), weekStart: 0);
    expect(days, hasLength(28));
    expect(days.first, DateTime(2026, 2));
    expect(days.last, DateTime(2026, 2, 28));
  });

  test('the week start changes how many weeks a month spans', () {
    // 1 Mar 2026 is a Sunday: no lead cells Sunday-first, so its 31 days fit
    // in 5 weeks; Monday-first pushes 6 lead cells in and needs a 6th.
    expect(monthGridRowCount(DateTime(2026, 3), weekStart: 0), 5);
    expect(monthGridRowCount(DateTime(2026, 3), weekStart: 1), 6);
  });

  test('a month starting on the week start has no lead cells', () {
    // 1 Feb 2026 is a Sunday.
    expect(
      monthGridDays(DateTime(2026, 2), weekStart: 0).first,
      DateTime(2026, 2),
    );
  });

  test('a Monday week start shifts the lead', () {
    // 1 Aug 2026 is a Saturday; Monday-first means 5 lead cells.
    expect(
      monthGridDays(DateTime(2026, 8), weekStart: 1).first,
      DateTime(2026, 7, 27),
    );
  });

  test('every cell is midnight-floored and consecutive', () {
    final days = monthGridDays(DateTime(2026, 3), weekStart: 0);
    for (final d in days) {
      expect(d.hour, 0);
      expect(d.minute, 0);
    }
    // Spans the 8 March 2026 DST jump without losing or repeating a day.
    for (var i = 1; i < days.length; i++) {
      final expected = DateTime(
        days[i - 1].year,
        days[i - 1].month,
        days[i - 1].day + 1,
      );
      expect(days[i], expected);
    }
  });

  test('en_CA starts the week on Sunday and labels S first', () {
    expect(weekStartForLocale('en_CA'), 0);
    expect(weekdayLabelsForLocale('en_CA').first, 'S');
    expect(weekdayLabelsForLocale('en_CA'), hasLength(7));
  });

  test('fr_CA labels are localized and rotated to its week start', () {
    final start = weekStartForLocale('fr_CA');
    final labels = weekdayLabelsForLocale('fr_CA');
    expect(labels, hasLength(7));
    expect(labels, isNot(equals(weekdayLabelsForLocale('en_CA'))));
    expect(start, inInclusiveRange(0, 6));
  });

  test('isSameDate ignores the time of day', () {
    expect(
      isSameDate(DateTime(2026, 5, 16, 23, 59), DateTime(2026, 5, 16)),
      isTrue,
    );
    expect(isSameDate(DateTime(2026, 5, 16), DateTime(2026, 5, 17)), isFalse);
  });

  test('isInMonth rejects the grid lead and trail cells', () {
    expect(isInMonth(DateTime(2026, 8, 15), DateTime(2026, 8)), isTrue);
    expect(isInMonth(DateTime(2026, 7, 26), DateTime(2026, 8)), isFalse);
    expect(isInMonth(DateTime(2026, 9, 5), DateTime(2026, 8)), isFalse);
  });

  test('weekOf spans the selected day and starts on the week start', () {
    // 16 May 2026 is a Saturday.
    final week = weekOf(DateTime(2026, 5, 16), weekStart: 0);
    expect(week, hasLength(7));
    expect(week.first, DateTime(2026, 5, 10));
    expect(week.last, DateTime(2026, 5, 16));
  });

  test('weekOf crosses a month boundary', () {
    final week = weekOf(DateTime(2026, 6, 2), weekStart: 0);
    expect(week.first, DateTime(2026, 5, 31));
    expect(week.last, DateTime(2026, 6, 6));
  });
}

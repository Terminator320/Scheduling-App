import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/calendar/domain/month_grid.dart';

/// Pins the one thing `AppointmentDateRange.visibleMonth`'s overscan exists to
/// guarantee: the fetch window covers every cell the month grid actually
/// renders, so no off-month cell is left dotless.
///
/// The overscan used to be ±14 — a superset of every grid shape, including the
/// fixed-6-row grid P2 replaced. It is ±7 now, one day past what
/// `monthGridRowCount`'s variable rows can produce, which makes it a saving of
/// a fortnight of documents per month view AND a coupling to the row rule.
/// This test is that coupling, made to fail loudly: bring back a fixed row
/// count (or any rule that trails more days) and it breaks here rather than in
/// silently empty crew dots on the edge of somebody's calendar.
void main() {
  // Every week start intl can report, not just the two the app ships — the
  // grid takes `weekStart` as a parameter and the worst case moves with it.
  const weekStarts = [0, 1, 2, 3, 4, 5, 6];

  /// Months spanning a full leap cycle, so a 29-day February and every
  /// weekday-alignment of a 28/30/31-day month are all covered.
  Iterable<DateTime> monthsAcrossALeapCycle() sync* {
    for (var year = 2024; year <= 2031; year++) {
      for (var month = 1; month <= 12; month++) {
        yield DateTime(year, month);
      }
    }
  }

  test('the fetch window covers every rendered grid cell', () {
    for (final month in monthsAcrossALeapCycle()) {
      final range = AppointmentDateRange.visibleMonth(month);
      for (final weekStart in weekStarts) {
        final days = monthGridDays(month, weekStart: weekStart);
        final first = days.first;
        final last = days.last;
        final where = '${month.year}-${month.month} @ weekStart $weekStart';

        expect(
          range.start.isAfter(first),
          isFalse,
          reason:
              '$where: grid starts $first, before the fetch window '
              '${range.start} — those cells render with no crew dots',
        );
        // `end` is exclusive, so the last cell must fall strictly inside it.
        expect(
          range.end.isAfter(last),
          isTrue,
          reason:
              '$where: grid ends $last, at or past the fetch window end '
              '${range.end} — those cells render with no crew dots',
        );
      }
    }
  });

  test('the grid never trails more than 6 off-month days on either side', () {
    // The premise the ±7 overscan is sized against, asserted directly so a
    // change to `monthGridRowCount` fails here with the reason rather than
    // only as a coverage gap in the test above.
    for (final month in monthsAcrossALeapCycle()) {
      final firstOfNextMonth = DateTime(month.year, month.month + 1);
      for (final weekStart in weekStarts) {
        final days = monthGridDays(month, weekStart: weekStart);
        final leading = days.where((d) => d.isBefore(month)).length;
        final trailing = days
            .where((d) => !d.isBefore(firstOfNextMonth))
            .length;
        final where = '${month.year}-${month.month} @ weekStart $weekStart';

        expect(leading, lessThanOrEqualTo(6), reason: '$where leading');
        expect(trailing, lessThanOrEqualTo(6), reason: '$where trailing');
      }
    }
  });
}

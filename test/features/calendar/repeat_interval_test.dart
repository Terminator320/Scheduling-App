import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/features/calendar/domain/models/repeat_interval.dart';

void main() {
  group('occurrenceStartsAfter', () {
    test('none yields no future occurrences', () {
      expect(
        RepeatInterval.none.occurrenceStartsAfter(DateTime(2026, 5, 10, 9)),
        isEmpty,
      );
    });

    test('fourMonths books every four months across five years', () {
      final occurrences = RepeatInterval.fourMonths.occurrenceStartsAfter(
        DateTime(2026, 5, 10, 9),
      );
      // 60-month horizon / 4 = 15 future visits, spanning multiple years.
      expect(occurrences, hasLength(15));
      expect(occurrences.first, DateTime(2026, 9, 10, 9));
      expect(occurrences.last, DateTime(2031, 5, 10, 9));
    });

    test('sixMonths books every six months across five years', () {
      final occurrences = RepeatInterval.sixMonths.occurrenceStartsAfter(
        DateTime(2026, 5, 10, 9),
      );
      expect(occurrences, hasLength(10));
      expect(occurrences.first, DateTime(2026, 11, 10, 9));
      expect(occurrences.last, DateTime(2031, 5, 10, 9));
    });

    test('oneYear books one visit per year for five years', () {
      expect(
        RepeatInterval.oneYear.occurrenceStartsAfter(DateTime(2026, 5, 10, 9)),
        [
          DateTime(2027, 5, 10, 9),
          DateTime(2028, 5, 10, 9),
          DateTime(2029, 5, 10, 9),
          DateTime(2030, 5, 10, 9),
          DateTime(2031, 5, 10, 9),
        ],
      );
    });

    test('clamps the day to the target month length', () {
      final occurrences = RepeatInterval.fourMonths.occurrenceStartsAfter(
        DateTime(2026, 10, 31, 9),
      );
      expect(occurrences, hasLength(15));
      expect(occurrences[0], DateTime(2027, 2, 28, 9));
      expect(occurrences[1], DateTime(2027, 6, 30, 9));
      expect(occurrences[2], DateTime(2027, 10, 31, 9));
    });

    test('preserves the time of day across occurrences', () {
      final occurrences = RepeatInterval.sixMonths.occurrenceStartsAfter(
        DateTime(2026, 1, 5, 14, 30),
      );
      expect(occurrences.first, DateTime(2026, 7, 5, 14, 30));
      expect(occurrences.last, DateTime(2031, 1, 5, 14, 30));
      expect(occurrences.every((d) => d.hour == 14 && d.minute == 30), isTrue);
    });
  });

  // `occurrenceEnd` writes `endTime` on up to maxOccurrences documents in one
  // atomic batch (add_event_controller, appointment_series_editor). A wrong
  // day-span there is invisible on the sheet that booked it and shows up
  // months later as a job that ends before it starts, or a one-day visit that
  // blocks a whole week of the calendar.
  group('occurrenceEnd', () {
    test('a same-day visit ends on the copy day at the original time', () {
      expect(
        occurrenceEnd(
          originalStart: DateTime(2026, 5, 10, 9),
          originalEnd: DateTime(2026, 5, 10, 11, 30),
          copyStart: DateTime(2026, 9, 10, 9),
        ),
        DateTime(2026, 9, 10, 11, 30),
      );
    });

    test('a multi-day span keeps its exact length on every copy', () {
      // Three calendar days apart on the original: the copy must span three
      // days too, not collapse to the copy's own start day.
      expect(
        occurrenceEnd(
          originalStart: DateTime(2026, 5, 10, 8),
          originalEnd: DateTime(2026, 5, 13, 17),
          copyStart: DateTime(2026, 11, 10, 8),
        ),
        DateTime(2026, 11, 13, 17),
      );
    });

    test(
      'the end time-of-day comes from the original end, not the copy start',
      () {
        expect(
          occurrenceEnd(
            originalStart: DateTime(2026, 5, 10, 8),
            originalEnd: DateTime(2026, 5, 10, 16, 45),
            copyStart: DateTime(2026, 9, 10, 6, 15),
          ),
          DateTime(2026, 9, 10, 16, 45),
        );
      },
    );

    test('a span crossing spring-forward keeps both days', () {
      // 2026-03-08 is the North American spring-forward Sunday: that local day
      // is 23 hours long, so an elapsed-duration `inDays` reads a two-day
      // booking as one. The UTC-midnight arithmetic is what stops that.
      expect(
        occurrenceEnd(
          originalStart: DateTime(2026, 3, 7, 9),
          originalEnd: DateTime(2026, 3, 9, 17),
          copyStart: DateTime(2026, 7, 7, 9),
        ),
        DateTime(2026, 7, 9, 17),
      );
    });

    test('a span crossing fall-back keeps both days', () {
      // 2026-11-01 is the fall-back Sunday — a 25-hour local day, the mirror
      // image of the case above.
      expect(
        occurrenceEnd(
          originalStart: DateTime(2026, 10, 31, 9),
          originalEnd: DateTime(2026, 11, 2, 17),
          copyStart: DateTime(2027, 2, 28, 9),
        ),
        DateTime(2027, 3, 2, 17),
      );
    });

    test('a one-hour booking across midnight is still a one-day span', () {
      // The DST guard's mechanism stated without depending on the runner's
      // timezone: the span is CALENDAR days, so 23:30 → 00:30 spans one day
      // even though only an hour elapsed. Rewriting the day span as
      // `originalEnd.difference(originalStart).inDays` fails this in every
      // zone — and that rewrite is exactly what DST also breaks.
      expect(
        occurrenceEnd(
          originalStart: DateTime(2026, 3, 7, 23, 30),
          originalEnd: DateTime(2026, 3, 8, 0, 30),
          copyStart: DateTime(2026, 7, 7, 23, 30),
        ),
        DateTime(2026, 7, 8, 0, 30),
      );
    });

    test('a span pushed past the end of a month rolls into the next one', () {
      expect(
        occurrenceEnd(
          originalStart: DateTime(2026, 5, 10, 8),
          originalEnd: DateTime(2026, 5, 12, 17),
          copyStart: DateTime(2027, 2, 27, 8),
        ),
        DateTime(2027, 3, 1, 17),
      );
    });

    test(
      'every occurrence of the widest series keeps the span, under the batch cap',
      () {
        // fourMonths over the five-year horizon is the worst case: one atomic
        // WriteBatch carrying every occurrence, so the count has to stay under
        // maxOccurrences AND each endTime has to survive the copy.
        final originalStart = DateTime(2026, 5, 10, 8);
        final originalEnd = DateTime(2026, 5, 12, 17);
        final starts = RepeatInterval.fourMonths.occurrenceStartsAfter(
          originalStart,
        );

        expect(starts.length, lessThanOrEqualTo(RepeatInterval.maxOccurrences));
        for (final copyStart in starts) {
          final end = occurrenceEnd(
            originalStart: originalStart,
            originalEnd: originalEnd,
            copyStart: copyStart,
          );
          expect(end.isAfter(copyStart), isTrue, reason: '$copyStart -> $end');
          expect(
            // UTC midnights in the assertion too: local ones would themselves
            // be 23/25 hours apart across a DST boundary and read one day short.
            DateTime.utc(end.year, end.month, end.day)
                .difference(
                  DateTime.utc(copyStart.year, copyStart.month, copyStart.day),
                )
                .inDays,
            2,
            reason: 'span lost on the occurrence starting $copyStart',
          );
          expect(end.hour, 17);
        }
      },
    );
  });
}

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
}

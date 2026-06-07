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

    test('fourMonths books three future visits within a year', () {
      expect(
        RepeatInterval.fourMonths.occurrenceStartsAfter(
          DateTime(2026, 5, 10, 9),
        ),
        [
          DateTime(2026, 9, 10, 9),
          DateTime(2027, 1, 10, 9),
          DateTime(2027, 5, 10, 9),
        ],
      );
    });

    test('sixMonths books two future visits within a year', () {
      expect(
        RepeatInterval.sixMonths.occurrenceStartsAfter(
          DateTime(2026, 5, 10, 9),
        ),
        [DateTime(2026, 11, 10, 9), DateTime(2027, 5, 10, 9)],
      );
    });

    test('oneYear books one future visit', () {
      expect(
        RepeatInterval.oneYear.occurrenceStartsAfter(DateTime(2026, 5, 10, 9)),
        [DateTime(2027, 5, 10, 9)],
      );
    });

    test('clamps the day to the target month length', () {
      expect(
        RepeatInterval.fourMonths.occurrenceStartsAfter(
          DateTime(2026, 10, 31, 9),
        ),
        [
          DateTime(2027, 2, 28, 9),
          DateTime(2027, 6, 30, 9),
          DateTime(2027, 10, 31, 9),
        ],
      );
    });

    test('preserves the time of day across occurrences', () {
      expect(
        RepeatInterval.sixMonths.occurrenceStartsAfter(
          DateTime(2026, 1, 5, 14, 30),
        ),
        [DateTime(2026, 7, 5, 14, 30), DateTime(2027, 1, 5, 14, 30)],
      );
    });
  });
}

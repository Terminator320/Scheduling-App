import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/features/calendar/domain/appointment_day_slice.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';

AppointmentRecord _record({
  required DateTime start,
  required DateTime end,
  bool isAllDay = false,
}) => AppointmentRecord(
  id: 'a1',
  title: 'Repipe',
  startTime: start,
  endTime: end,
  isAllDay: isAllDay,
);

void main() {
  group('sliceFor', () {
    test('a single-day job is day 1 of 1', () {
      final a = _record(
        start: DateTime(2026, 8, 1, 9),
        end: DateTime(2026, 8, 1, 17),
      );
      final slice = sliceFor(a, DateTime(2026, 8, 1))!;
      expect(slice.dayIndex, 1);
      expect(slice.dayCount, 1);
      expect(slice.isMultiDay, isFalse);
    });

    test('a 5-day job reports the same daily window on every day', () {
      final a = _record(
        start: DateTime(2026, 8, 1, 9),
        end: DateTime(2026, 8, 5, 17),
      );
      final slice = sliceFor(a, DateTime(2026, 8, 3))!;
      expect(slice.dayIndex, 3);
      expect(slice.dayCount, 5);
      expect(slice.windowStart, DateTime(2026, 8, 3, 9));
      expect(slice.windowEnd, DateTime(2026, 8, 3, 17));
      expect(slice.isOvernight, isFalse);
    });

    test('a day outside the span has no slice', () {
      final a = _record(
        start: DateTime(2026, 8, 1, 9),
        end: DateTime(2026, 8, 5, 17),
      );
      expect(sliceFor(a, DateTime(2026, 7, 31)), isNull);
      expect(sliceFor(a, DateTime(2026, 8, 6)), isNull);
    });

    test('a night shift counts nights and ends the next morning', () {
      // Aug 1, 2, 3 at 10pm; the last window ends Aug 4 at 6am.
      final a = _record(
        start: DateTime(2026, 8, 1, 22),
        end: DateTime(2026, 8, 4, 6),
      );
      final slice = sliceFor(a, DateTime(2026, 8, 2))!;
      expect(slice.dayCount, 3);
      expect(slice.dayIndex, 2);
      expect(slice.isOvernight, isTrue);
      expect(slice.windowStart, DateTime(2026, 8, 2, 22));
      expect(slice.windowEnd, DateTime(2026, 8, 3, 6));
    });

    test('a night shift shows nothing on the morning it finishes', () {
      final a = _record(
        start: DateTime(2026, 8, 1, 22),
        end: DateTime(2026, 8, 4, 6),
      );
      expect(sliceFor(a, DateTime(2026, 8, 4)), isNull);
    });

    test('an all-day block is not overnight', () {
      final a = _record(
        start: DateTime(2026, 8, 10),
        end: DateTime(2026, 8, 14, 23, 59),
        isAllDay: true,
      );
      final slice = sliceFor(a, DateTime(2026, 8, 12))!;
      expect(slice.dayCount, 5);
      expect(slice.dayIndex, 3);
      expect(slice.isOvernight, isFalse);
    });
  });

  group('expandToDays', () {
    test('fans one record across every day it spans', () {
      final a = _record(
        start: DateTime(2026, 8, 1, 9),
        end: DateTime(2026, 8, 3, 17),
      );
      final index = expandToDays(
        [a],
        AppointmentDateRange(
          start: DateTime(2026, 8, 1),
          end: DateTime(2026, 8, 9),
        ),
      );
      expect(index.keys.toList(), [
        DateTime(2026, 8, 1),
        DateTime(2026, 8, 2),
        DateTime(2026, 8, 3),
      ]);
    });

    test('drops days outside the requested range', () {
      final a = _record(
        start: DateTime(2026, 7, 30, 9),
        end: DateTime(2026, 8, 2, 17),
      );
      final index = expandToDays(
        [a],
        AppointmentDateRange(
          start: DateTime(2026, 8, 1),
          end: DateTime(2026, 8, 9),
        ),
      );
      expect(index.keys.toList(), [DateTime(2026, 8, 1), DateTime(2026, 8, 2)]);
    });

    test('sorts all-day blocks above timed jobs, then by window start', () {
      final timedEarly = _record(
        start: DateTime(2026, 8, 3, 8, 30),
        end: DateTime(2026, 8, 3, 10),
      ).copyWith(id: 'early');
      final timedLate = _record(
        start: DateTime(2026, 8, 3, 13),
        end: DateTime(2026, 8, 3, 16),
      ).copyWith(id: 'late');
      final allDay = _record(
        start: DateTime(2026, 8, 3),
        end: DateTime(2026, 8, 3, 23, 59),
        isAllDay: true,
      ).copyWith(id: 'allday');

      final index = expandToDays(
        [timedLate, timedEarly, allDay],
        AppointmentDateRange(
          start: DateTime(2026, 8, 3),
          end: DateTime(2026, 8, 4),
        ),
      );
      expect(
        index[DateTime(2026, 8, 3)]!.map((s) => s.appointment.id).toList(),
        ['allday', 'early', 'late'],
      );
    });
  });
}

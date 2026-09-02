import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';

void main() {
  final month = AppointmentDateRange(
    start: DateTime(2026, 8, 25),
    end: DateTime(2026, 10, 8),
  );

  test('a range already inside this one returns the SAME instance', () {
    // The calendar keys its listener on range VALUE; the week almost always
    // sits inside the month overscan, so the common case must not re-key.
    final week = AppointmentDateRange(
      start: DateTime(2026, 9, 7),
      end: DateTime(2026, 9, 14),
    );
    expect(identical(month.union(week), month), isTrue);
  });

  test('a week past the end widens only the end', () {
    final week = AppointmentDateRange(
      start: DateTime(2026, 10, 5),
      end: DateTime(2026, 10, 12),
    );
    final union = month.union(week);
    expect(union.start, DateTime(2026, 8, 25));
    expect(union.end, DateTime(2026, 10, 12));
  });

  test('a week before the start widens only the start', () {
    final week = AppointmentDateRange(
      start: DateTime(2026, 8, 24),
      end: DateTime(2026, 8, 31),
    );
    final union = month.union(week);
    expect(union.start, DateTime(2026, 8, 24));
    expect(union.end, DateTime(2026, 10, 8));
  });

  test('union is value-equal whichever side it is taken from', () {
    final other = AppointmentDateRange(
      start: DateTime(2026, 8),
      end: DateTime(2026, 11),
    );
    expect(month.union(other), other.union(month));
  });
}

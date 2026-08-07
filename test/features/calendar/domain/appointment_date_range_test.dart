import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/features/calendar/domain/appointment_day_slice.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';

void main() {
  test('fetchStart reaches maxAppointmentSpanDays before the range start', () {
    final range = AppointmentDateRange.forDay(DateTime(2026, 8, 20));
    expect(range.start, DateTime(2026, 8, 20));
    expect(
      range.fetchStart,
      DateTime(2026, 8, 20 - maxAppointmentSpanDays),
    );
  });

  test('fetchStart crosses a month boundary by calendar arithmetic', () {
    final range = AppointmentDateRange.forDay(DateTime(2026, 8, 5));
    expect(range.fetchStart, DateTime(2026, 7, 22));
  });

  test('two ranges for the same day are equal, so they share one listener', () {
    expect(
      AppointmentDateRange.forDay(DateTime(2026, 8, 5)),
      AppointmentDateRange.forDay(DateTime(2026, 8, 5)),
    );
  });

  test('fetchStart never moves the range end', () {
    final range = AppointmentDateRange.forDay(DateTime(2026, 8, 5));
    expect(range.end, DateTime(2026, 8, 6));
  });
}

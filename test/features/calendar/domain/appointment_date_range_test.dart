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

  group('forMirrors', () {
    test('the Siri snapshot and the home widget produce the SAME range', () {
      // The two mirrors ask the same myAppointmentsProvider family, which is
      // keyed by range VALUE — two different windows meant two permanent
      // Firestore listeners per signed-in user, one a strict subset of the
      // other.
      expect(
        AppointmentDateRange.forMirrors(DateTime(2026, 8, 5)),
        AppointmentDateRange.forMirrors(DateTime(2026, 8, 5)),
      );
    });

    test('covers today plus the snapshot lookahead', () {
      final range = AppointmentDateRange.forMirrors(DateTime(2026, 8, 5, 14));
      expect(range.start, DateTime(2026, 8, 5));
      // Exclusive end one day past the last day Siri speaks about.
      expect(range.end, DateTime(2026, 8, 13));
    });

    test('is a superset of the widget today+tomorrow window', () {
      final range = AppointmentDateRange.forMirrors(DateTime(2026, 8, 5));
      expect(range.end.isAfter(DateTime(2026, 8, 7)), isTrue);
    });

    test('uses calendar arithmetic, so a DST day cannot fork a listener', () {
      // Nov 1 2026 is the fall-back day in America/Toronto.
      final range = AppointmentDateRange.forMirrors(DateTime(2026, 11, 1, 23));
      expect(range.start, DateTime(2026, 11));
      expect(range.end, DateTime(2026, 11, 9));
    });
  });
}

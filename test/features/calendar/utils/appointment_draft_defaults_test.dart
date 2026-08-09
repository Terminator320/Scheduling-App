// The default end time is start + 1h, and the only interesting case is the
// one that wraps: an 11:30 PM start must yield 12:30 AM, not hour 24. A
// TimeOfDay built with hour 24 asserts in debug and renders nonsense in
// release, and both call sites (the add controller's seed and the picker's
// auto-fill) push it straight into the form.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/features/calendar/utils/appointment_draft_defaults.dart';

void main() {
  group('AppointmentDraftDefaults.defaultEndTime', () {
    test('adds an hour within the same day', () {
      expect(
        AppointmentDraftDefaults.defaultEndTime(
          const TimeOfDay(hour: 9, minute: 15),
        ),
        const TimeOfDay(hour: 10, minute: 15),
      );
    });

    test('wraps past midnight instead of producing hour 24', () {
      expect(
        AppointmentDraftDefaults.defaultEndTime(
          const TimeOfDay(hour: 23, minute: 30),
        ),
        const TimeOfDay(hour: 0, minute: 30),
      );
    });

    test('11:00 PM lands on midnight, not hour 24', () {
      expect(
        AppointmentDraftDefaults.defaultEndTime(
          const TimeOfDay(hour: 23, minute: 0),
        ),
        const TimeOfDay(hour: 0, minute: 0),
      );
    });

    test('every possible start yields a valid TimeOfDay', () {
      // A wrap bug is only reachable in the last hour of the day, which is
      // exactly why it survived: nobody books at 11:30 PM by accident.
      for (var hour = 0; hour < TimeOfDay.hoursPerDay; hour++) {
        for (final minute in [0, 30, 59]) {
          final end = AppointmentDraftDefaults.defaultEndTime(
            TimeOfDay(hour: hour, minute: minute),
          );
          expect(end.hour, inInclusiveRange(0, 23), reason: '$hour:$minute');
          expect(end.minute, inInclusiveRange(0, 59), reason: '$hour:$minute');
        }
      }
    });
  });
}

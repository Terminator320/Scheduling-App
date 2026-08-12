import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/features/calendar/domain/appointment_day_slice.dart';

/// `maxAppointmentSpanDays` now has a third copy — the Dart constant, JS's
/// `MAX_APPOINTMENT_SPAN_DAYS`, and the bound in `firestore.rules`. Dart and CEL
/// cannot share a constant, so this test reading the rules back as text is the
/// only mechanism keeping the two equal, the same way `text_limits_test.dart`
/// and `self_service_fields_test.dart` police their own hand-mirrors.
///
/// It also pins the two properties that make the bound safe to ship: that it is
/// inclusive (a 14-day run at one clock time is a legitimate chain of 24-hour
/// windows and must not be rejected), and that an out-of-range doc written by
/// the console or the Admin SDK stays updatable.
void main() {
  late final rules = File('firestore.rules').readAsStringSync();

  String? bodyOf(String function) => RegExp(
    'function $function\\([^)]*\\)\\s*\\{(.*?)\\n    \\}',
    dotAll: true,
  ).firstMatch(rules)?.group(1);

  group('the appointment span bound mirrors maxAppointmentSpanDays', () {
    test('the rules bound is the same number of days as the Dart cap', () {
      // Scoped to the function body: `liveActivityTokens` carries its own
      // `duration.value(31, 'd')` TTL ceiling earlier in the file.
      final bound = RegExp(
        r"duration\.value\((\d+), 'd'\)",
      ).firstMatch(bodyOf('isValidAppointmentSpan') ?? '')?.group(1);

      expect(bound, isNotNull, reason: 'the span bound was removed');
      expect(int.parse(bound!), maxAppointmentSpanDays);
    });

    test('the bound is inclusive, so a 14-day 24-hour run still saves', () {
      // `<` would reject a run booked at a single clock time (09:00 -> +14d
      // 09:00), which AppointmentFormValidator accepts as exactly 14 days.
      expect(bodyOf('isValidAppointmentSpan'), contains('<= duration.value'));
    });

    test('the bound carries DST headroom over the calendar-day cap', () {
      // The app's cap counts CALENDAR days and `combineDateAndTime` composes
      // LOCAL wall-clock instants, while `duration.value` is absolute. A window
      // containing the autumn fall-back therefore stores an hour MORE than its
      // calendar length — the widest run becomes 14d 1h and a 14-day all-day
      // block 14d 0h59m — so a flat 14d bound refused a booking the form had
      // already accepted. Drop this term and that returns every November.
      expect(
        bodyOf('isValidAppointmentSpan'),
        contains("duration.value(2, 'h')"),
      );
    });

    test('a doc missing either instant is not stranded by the guard', () {
      final guard = bodyOf('isValidAppointmentSpan');

      expect(guard, isNotNull, reason: 'isValidAppointmentSpan was removed');
      expect(guard, contains("!('startTime' in d.keys())"));
      expect(guard, contains("!('endTime' in d.keys())"));
    });
  });

  group('an out-of-range doc stays repairable', () {
    test('update accepts a span that is not widened', () {
      // The Admin SDK bypasses rules, so a doc past the cap can already exist.
      // Without this branch an admin could not even CANCEL it.
      final guard = bodyOf('appointmentSpanNotWidened');

      expect(guard, isNotNull, reason: 'appointmentSpanNotWidened was removed');
      expect(guard, contains('<= resource.data.endTime'));
    });

    test('create bounds the span outright and update offers the escape', () {
      final createBlock = RegExp(
        r'allow create: if isAdmin\(\)\s*&& isValidAppointmentStatus(.*?);',
        dotAll: true,
      ).firstMatch(rules)?.group(1);
      final updateBlock = RegExp(
        r'allow update: if \(isAdmin\(\)(.*?)\|\| \(isAssignedEmployee',
        dotAll: true,
      ).firstMatch(rules)?.group(1);

      expect(createBlock, contains('isValidAppointmentSpan'));
      expect(createBlock, isNot(contains('appointmentSpanNotWidened')));
      expect(updateBlock, contains('isValidAppointmentSpan'));
      expect(updateBlock, contains('appointmentSpanNotWidened'));
    });

    test("an assignee's status flip never reaches the span guard", () {
      // That branch restricts the diff to status + updatedAt, so a corrupt doc
      // can still be marked done from the field.
      final assigneeBranch = RegExp(
        r'\|\| \(isAssignedEmployee\(resource\.data\)(.*?)\);',
        dotAll: true,
      ).firstMatch(rules)?.group(1);

      expect(assigneeBranch, isNotNull);
      expect(assigneeBranch, isNot(contains('AppointmentSpan')));
    });
  });
}

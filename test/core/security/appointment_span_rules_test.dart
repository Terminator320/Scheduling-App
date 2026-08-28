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
      // SCOPED to the appointments block, then matched to the end of the
      // clause. This test is about WHICH span guard each branch carries, not
      // the order the conditions are written in, so it must not pin the clause
      // that follows `isAdmin()` — doing so made it fail when an unrelated
      // guard (`pictureCount`, added with the photo subcollection) was
      // inserted between them. Scoping is what the loosened pattern then
      // needs: `/users` also opens with `allow create: if isAdmin()`, earlier
      // in the file, and an unscoped match silently reads THAT block instead.
      final appointments = rules.substring(
        rules.indexOf('match /appointments/{appointmentId}'),
      );
      final createBlock = RegExp(
        r'allow create: if isAdmin\(\)(.*?);',
        dotAll: true,
      ).firstMatch(appointments)?.group(1);
      final updateBlock = RegExp(
        r'allow update: if \(isAdmin\(\)(.*?)\|\| \(isAssignedEmployee',
        dotAll: true,
      ).firstMatch(appointments)?.group(1);

      expect(createBlock, contains('isValidAppointmentSpan'));
      expect(createBlock, isNot(contains('appointmentSpanNotWidened')));
      expect(updateBlock, contains('isValidAppointmentSpan'));
      expect(updateBlock, contains('appointmentSpanNotWidened'));
    });

    test('each instant is type-checked on CREATE only', () {
      // `isValidAppointmentSpan` short-circuits to true when EITHER key is
      // absent, so a doc carrying only one of them was never type-checked.
      // A non-timestamp `startTime` is excluded from every
      // `orderBy('startTime')`, dropping the job out of the travel sweep, the
      // digest, the mirrors and the Siri snapshot silently.
      //
      // Create-only for the same reason the span bound softens on update: such
      // a doc can already exist via the console, and enforcing it on update
      // would leave it permanently un-updatable — including by the admin
      // trying to cancel it.
      final appointments = rules.substring(
        rules.indexOf('match /appointments/{appointmentId}'),
      );
      final createBlock = RegExp(
        r'allow create: if isAdmin\(\)(.*?);',
        dotAll: true,
      ).firstMatch(appointments)?.group(1);
      final updateBlock = RegExp(
        r'allow update: if \(isAdmin\(\)(.*?)\|\| \(isAssignedEmployee',
        dotAll: true,
      ).firstMatch(appointments)?.group(1);

      expect(createBlock, contains('hasValidAppointmentInstants'));
      expect(updateBlock, isNot(contains('hasValidAppointmentInstants')));

      final body = bodyOf('hasValidAppointmentInstants');
      expect(body, isNotNull, reason: 'the instant type guard was removed');
      expect(body, contains('d.startTime is timestamp'));
      expect(body, contains('d.endTime is timestamp'));
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

  group('the run day fields are bounded, not merely type-checked', () {
    // `dayIndex`/`dayCount` are what a card reads to say "Day 3 of 5". An
    // `is int` alone would let a client write "Day 900 of 4000" — the Dart
    // `_storedRunLabel` and the JS `storedRunLabel` both refuse an incoherent
    // pair, but the rules are the last line of defence.
    test('both fields are present in the appointment validator', () {
      final body = bodyOf('isValidAppointmentData') ?? '';
      expect(body, contains('dayIndex'));
      expect(body, contains('dayCount'));
    });

    test('each is an int floored at 1', () {
      final body = bodyOf('isValidAppointmentData') ?? '';
      expect(body, contains('d.dayIndex is int'));
      expect(body, contains('d.dayIndex >= 1'));
      expect(body, contains('d.dayCount is int'));
      expect(body, contains('d.dayCount >= 1'));
    });

    test('each is capped at maxAppointmentSpanDays', () {
      // A run can never have more days than its span may cover, so this cap
      // and isValidAppointmentSpan's move together.
      final body = bodyOf('isValidAppointmentData') ?? '';
      expect(body, contains('d.dayIndex <= $maxAppointmentSpanDays'));
      expect(body, contains('d.dayCount <= $maxAppointmentSpanDays'));
    });

    test('both stay optional, so an ordinary job still saves', () {
      // The appointment validator has no `hasOnly`; every clause is
      // absent-or-valid. A required field here would reject every one-day job
      // and every document written before the split.
      final body = bodyOf('isValidAppointmentData') ?? '';
      expect(body, contains("!('dayIndex' in d.keys())"));
      expect(body, contains("!('dayCount' in d.keys())"));
    });
  });
}

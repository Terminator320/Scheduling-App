// Pins the single Firestore-date boundary. Every domain model's dates come
// through here, so a dropped branch nulls them silently — a legacy doc's date
// simply disappears rather than failing anywhere a reader would notice.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/core/utils/firestore_parsing.dart';

void main() {
  test('a Timestamp becomes its DateTime', () {
    final moment = DateTime(2026, 8, 11, 9, 30);

    expect(firestoreDateTime(Timestamp.fromDate(moment)), moment);
  });

  test('a DateTime passes through unchanged', () {
    final moment = DateTime(2026, 8, 11, 9, 30);

    expect(firestoreDateTime(moment), same(moment));
  });

  test('a legacy ISO-8601 string still parses', () {
    // Docs written before the Timestamp convention store a string. Dropping
    // this branch would blank their dates with no error anywhere.
    expect(
      firestoreDateTime('2026-08-11T09:30:00.000'),
      DateTime(2026, 8, 11, 9, 30),
    );
  });

  test('an unparseable string is null, not a throw', () {
    expect(firestoreDateTime('not a date'), isNull);
  });

  test('null and an unexpected type are null', () {
    expect(firestoreDateTime(null), isNull);
    expect(firestoreDateTime(42), isNull);
    expect(firestoreDateTime(<String, dynamic>{}), isNull);
  });

  // The lenient sibling, and lenient for the same reason: it runs inside
  // `snapshots().map` on every EmployeeRecord (workStartMinutes /
  // workEndMinutes / maxJobsPerDay) and every ClientRecord (jobCount). A throw
  // on ONE console-written field blanks the whole snapshot — the roster, the
  // employee picker or the client list goes empty with no error on screen.
  group('firestoreInt', () {
    test('an int passes through', () {
      expect(firestoreInt(540), 540);
      expect(firestoreInt(0), 0);
    });

    test('a double is truncated toward zero', () {
      // The Firestore console has one number type, so a hand-typed 540 can
      // arrive as 540.0 — and an edited one as 540.7.
      expect(firestoreInt(540.0), 540);
      expect(firestoreInt(540.7), 540);
      expect(firestoreInt(-3.9), -3);
    });

    test('a numeric string parses, trimming whitespace', () {
      expect(firestoreInt('540'), 540);
      expect(firestoreInt('  540  '), 540);
      expect(firestoreInt('-8'), -8);
    });

    test('null is null so the caller default applies', () {
      // EmployeeRecord reads `firestoreInt(...) ?? kDefaultWorkStartMinutes` —
      // returning 0 here instead of null would silently move every legacy
      // employee's workday to midnight.
      expect(firestoreInt(null), isNull);
      expect(firestoreInt(<String, dynamic>{}), isNull);
    });

    test('an unparseable or wrong-typed value is null, never a throw', () {
      expect(firestoreInt('nine'), isNull);
      expect(firestoreInt(''), isNull);
      expect(firestoreInt('9.5'), isNull);
      expect(firestoreInt(true), isNull);
      expect(firestoreInt(<int>[540]), isNull);
    });

    test('the default is what a missing field resolves to', () {
      const fallback = 480;

      expect(firestoreInt(null) ?? fallback, fallback);
      expect(firestoreInt('not a number') ?? fallback, fallback);
      expect(firestoreInt('600') ?? fallback, 600);
    });
  });
}

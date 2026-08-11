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
}

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';

/// The job time record on the record (2026-09-01).
void main() {
  final started = DateTime(2026, 9, 1, 9, 12);
  final done = DateTime(2026, 9, 1, 11, 40);

  Map<String, dynamic> stored() => {
    'title': 'Leak fix',
    'startTime': Timestamp.fromDate(DateTime(2026, 9, 1, 9)),
    'endTime': Timestamp.fromDate(DateTime(2026, 9, 1, 12)),
    'status': 'done',
    'startedAt': Timestamp.fromDate(started),
    'completedAt': Timestamp.fromDate(done),
  };

  test('fromMap reads the time record', () {
    final record = AppointmentRecord.fromMap('a1', stored());

    expect(record.startedAt, started);
    expect(record.completedAt, done);
  });

  test('a document without them reads as unstarted', () {
    final record = AppointmentRecord.fromMap('a1', {
      'startTime': Timestamp.fromDate(DateTime(2026, 9, 1, 9)),
      'endTime': Timestamp.fromDate(DateTime(2026, 9, 1, 12)),
    });

    expect(record.startedAt, isNull);
    expect(record.completedAt, isNull);
  });

  test('toMap omits both, so a merge write leaves them untouched', () {
    final map = AppointmentRecord.fromMap('a1', stored()).toMap();

    for (final key in const ['startedAt', 'completedAt']) {
      expect(map, isNot(contains(key)), reason: '$key must not be emitted');
    }
  });
}

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/features/calendar/domain/appointment_status_values.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';

/// The job time record and the crew signal on the record (2026-09-01).
void main() {
  final started = DateTime(2026, 9, 1, 9, 12);
  final done = DateTime(2026, 9, 1, 11, 40);
  final signalled = DateTime(2026, 9, 1, 8, 50);

  Map<String, dynamic> stored() => {
    'title': 'Leak fix',
    'startTime': Timestamp.fromDate(DateTime(2026, 9, 1, 9)),
    'endTime': Timestamp.fromDate(DateTime(2026, 9, 1, 12)),
    'status': 'done',
    'startedAt': Timestamp.fromDate(started),
    'completedAt': Timestamp.fromDate(done),
    'crewStatus': 'runningLate',
    'crewStatusAt': Timestamp.fromDate(signalled),
    'crewStatusBy': 'e1',
  };

  test('fromMap reads the time record and the crew signal', () {
    final record = AppointmentRecord.fromMap('a1', stored());

    expect(record.startedAt, started);
    expect(record.completedAt, done);
    expect(record.crewStatus, 'runningLate');
    expect(record.crewStatusAt, signalled);
    expect(record.crewStatusBy, 'e1');
    expect(record.hasCrewSignal, isTrue);
  });

  test('a document without them reads as unstarted and unsignalled', () {
    final record = AppointmentRecord.fromMap('a1', {
      'startTime': Timestamp.fromDate(DateTime(2026, 9, 1, 9)),
      'endTime': Timestamp.fromDate(DateTime(2026, 9, 1, 12)),
    });

    expect(record.startedAt, isNull);
    expect(record.completedAt, isNull);
    expect(record.crewStatus, '');
    expect(record.crewStatusBy, '');
    expect(record.hasCrewSignal, isFalse);
  });

  test('toMap omits all five, so a merge write leaves them untouched', () {
    final map = AppointmentRecord.fromMap('a1', stored()).toMap();

    for (final key in const [
      'startedAt',
      'completedAt',
      'crewStatus',
      'crewStatusAt',
      'crewStatusBy',
    ]) {
      expect(map, isNot(contains(key)), reason: '$key must not be emitted');
    }
  });

  test('the crew vocabulary is exactly the two strings the rules admit', () {
    expect(crewStatusRawValues, {'onMyWay', 'runningLate'});
  });
}

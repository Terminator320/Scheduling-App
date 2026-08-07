import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/siri/domain/schedule_snapshot.dart';

AppointmentRecord _appt({
  required DateTime start,
  String? id = 'a1',
  String status = 'pending',
  String clientName = 'Ada',
  String address = '14 Elm St',
}) => AppointmentRecord(
  id: id,
  startTime: start,
  endTime: start.add(const Duration(hours: 1)),
  status: status,
  clientName: clientName,
  address: address,
);

List<Map<String, dynamic>> _days(Map<String, dynamic> snapshot) =>
    (snapshot['days'] as List).cast<Map<String, dynamic>>();

List<Map<String, dynamic>> _appointmentsOn(
  Map<String, dynamic> snapshot,
  String date,
) =>
    (_days(
              snapshot,
            ).firstWhere((d) => d['date'] == date)['appointments']
            as List)
        .cast<Map<String, dynamic>>();

void main() {
  final now = DateTime(2026, 7, 19, 10, 30);

  Map<String, dynamic> build(
    List<AppointmentRecord> appointments, {
    String role = 'employee',
  }) => buildScheduleSnapshot(
    appointments: appointments,
    role: role,
    now: now,
  );

  group('buildScheduleSnapshot', () {
    test('stamps version, generatedAt and role', () {
      final snapshot = build(const [], role: 'admin');

      expect(snapshot['version'], scheduleSnapshotVersion);
      expect(snapshot['generatedAt'], now.millisecondsSinceEpoch);
      expect(snapshot['role'], 'admin');
    });

    test('emits today plus the 7-day lookahead as ordered day buckets', () {
      final snapshot = build(const []);

      expect(
        _days(snapshot).map((d) => d['date']).toList(),
        [
          '2026-07-19',
          '2026-07-20',
          '2026-07-21',
          '2026-07-22',
          '2026-07-23',
          '2026-07-24',
          '2026-07-25',
          '2026-07-26',
        ],
      );
    });

    test('buckets an appointment on its device-local day', () {
      final snapshot = build([
        _appt(start: DateTime(2026, 7, 21, 14)),
      ]);

      expect(_appointmentsOn(snapshot, '2026-07-20'), isEmpty);
      expect(_appointmentsOn(snapshot, '2026-07-21'), hasLength(1));
    });

    test('keeps a job starting earlier today than now', () {
      final snapshot = build([
        _appt(start: DateTime(2026, 7, 19, 8)),
      ]);

      expect(_appointmentsOn(snapshot, '2026-07-19'), hasLength(1));
    });

    test('drops appointments outside the window', () {
      final snapshot = build([
        _appt(start: DateTime(2026, 7, 18, 9)),
        _appt(start: DateTime(2026, 7, 27, 9)),
      ]);

      expect(
        _days(snapshot).expand((d) => d['appointments'] as List),
        isEmpty,
      );
    });

    test('excludes cancelled visits', () {
      final snapshot = build([
        _appt(start: DateTime(2026, 7, 19, 9), status: 'cancelled'),
        _appt(start: DateTime(2026, 7, 19, 11), status: 'done'),
      ]);

      final today = _appointmentsOn(snapshot, '2026-07-19');
      expect(today, hasLength(1));
      expect(today.single['status'], 'done');
    });

    test('drops records with a null or empty id', () {
      final snapshot = build([
        _appt(id: null, start: DateTime(2026, 7, 19, 9)),
        _appt(id: '', start: DateTime(2026, 7, 19, 10)),
        _appt(id: 'keep', start: DateTime(2026, 7, 19, 11)),
      ]);

      final today = _appointmentsOn(snapshot, '2026-07-19');
      expect(today, hasLength(1));
      expect(today.single['id'], 'keep');
    });

    test('normalizes a legacy confirmed status onto the allowlist', () {
      final snapshot = build([
        _appt(start: DateTime(2026, 7, 19, 9), status: 'confirmed'),
      ]);

      expect(
        _appointmentsOn(snapshot, '2026-07-19').single['status'],
        'pending',
      );
    });

    test('degrades a stored display-only overdue status to pending', () {
      final snapshot = build([
        _appt(start: DateTime(2026, 7, 19, 9), status: 'overdue'),
      ]);

      expect(
        _appointmentsOn(snapshot, '2026-07-19').single['status'],
        'pending',
      );
    });

    test('sorts each day by start time', () {
      final snapshot = build([
        _appt(id: 'late', start: DateTime(2026, 7, 20, 16)),
        _appt(id: 'early', start: DateTime(2026, 7, 20, 8)),
      ]);

      expect(
        _appointmentsOn(snapshot, '2026-07-20').map((a) => a['id']).toList(),
        ['early', 'late'],
      );
    });

    test('caps a day at $scheduleSnapshotPerDayCap and keeps the earliest', () {
      final snapshot = build([
        for (var i = 0; i < scheduleSnapshotPerDayCap + 5; i++)
          _appt(
            id: 'a$i',
            start: DateTime(2026, 7, 20).add(Duration(minutes: i)),
          ),
      ]);

      final day = _appointmentsOn(snapshot, '2026-07-20');
      expect(day, hasLength(scheduleSnapshotPerDayCap));
      expect(day.last['id'], 'a${scheduleSnapshotPerDayCap - 1}');
    });

    test('carries only the fields the intents speak', () {
      final start = DateTime(2026, 7, 19, 9);
      final snapshot = build([_appt(start: start)]);

      expect(_appointmentsOn(snapshot, '2026-07-19').single, {
        'id': 'a1',
        'startMillis': start.millisecondsSinceEpoch,
        'endMillis': start.add(const Duration(hours: 1)).millisecondsSinceEpoch,
        'clientName': 'Ada',
        'title': '',
        'address': '14 Elm St',
        'status': 'pending',
        'isAllDay': false,
      });
    });

    test('a personal all-day block carries its title and the flag', () {
      // No client, midnight → 23:59: Siri names it by title and says
      // "all day" rather than reading two clock times out.
      final snapshot = build([
        AppointmentRecord(
          id: 'p1',
          title: 'Vacation',
          startTime: DateTime(2026, 7, 19),
          endTime: DateTime(2026, 7, 19, 23, 59),
          isPersonal: true,
          isAllDay: true,
        ),
      ]);

      final appointment = _appointmentsOn(snapshot, '2026-07-19').single;
      expect(appointment['clientName'], '');
      expect(appointment['title'], 'Vacation');
      expect(appointment['isAllDay'], isTrue);
    });
  });
}

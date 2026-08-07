import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/home_widget/application/widget_sync_service.dart';

/// Fixed clock: Wednesday 2026-07-08, noon.
final _now = DateTime(2026, 7, 8, 12);

AppointmentRecord _appt({
  required String id,
  required DateTime start,
  DateTime? end,
  String status = 'pending',
  String clientName = 'Client',
  bool isAllDay = false,
}) => AppointmentRecord(
  id: id,
  title: 'Job $id',
  clientName: clientName,
  startTime: start,
  endTime: end ?? start.add(const Duration(hours: 1)),
  status: status,
  isAllDay: isAllDay,
);

String _iso(DateTime d) => d.toUtc().toIso8601String();

void main() {
  group('buildWidgetPayload', () {
    test('todayJobs are future, non-terminal, and sorted', () {
      final payload = buildWidgetPayload([
        _appt(id: 'past', start: DateTime(2026, 7, 8, 9)),
        _appt(id: 'later', start: DateTime(2026, 7, 8, 16)),
        _appt(id: 'soon', start: DateTime(2026, 7, 8, 14)),
        _appt(id: 'done', start: DateTime(2026, 7, 8, 15), status: 'done'),
        _appt(id: 'tomorrow', start: DateTime(2026, 7, 9, 9)),
      ], _now);

      final today = payload['todayJobs'] as List;
      expect(today.map((j) => (j as Map)['id']), ['soon', 'later']);
      expect(payload['tomorrowJobs'] as List, hasLength(1));
    });

    test('an all-day block stays in today until its 23:59 end', () {
      // It starts at midnight, so a start-time test would have dropped it
      // from today the moment the day began.
      final payload = buildWidgetPayload([
        _appt(
          id: 'vacation',
          start: DateTime(2026, 7, 8),
          end: DateTime(2026, 7, 8, 23, 59),
          isAllDay: true,
        ),
      ], _now);

      final today = payload['todayJobs'] as List;
      expect(today.map((j) => (j as Map)['id']), ['vacation']);
      expect((today.single as Map)['isAllDay'], isTrue);
      expect(payload['rolloverAt'], isNull);
    });

    test('each job carries its appointment id for the widget deep-link', () {
      final payload = buildWidgetPayload([
        _appt(id: 'soon', start: DateTime(2026, 7, 8, 14)),
      ], _now);

      expect(((payload['todayJobs'] as List).first as Map)['id'], 'soon');
    });

    test('while today has an open job, rolloverAt is null (stays today)', () {
      final payload = buildWidgetPayload([
        _appt(id: 'soon', start: DateTime(2026, 7, 8, 14)),
        _appt(id: 'tomorrow', start: DateTime(2026, 7, 9, 9)),
      ], _now);

      expect(payload['rolloverAt'], isNull);
      expect(((payload['todayJobs'] as List).single as Map)['id'], 'soon');
      expect(payload['tomorrowJobs'] as List, hasLength(1));
      expect(payload['todayDate'], _iso(DateTime(2026, 7, 8)));
      expect(payload['tomorrowDate'], _iso(DateTime(2026, 7, 9)));
    });

    test('once the last job is complete, rolloverAt is endTime + 1h', () {
      final payload = buildWidgetPayload([
        _appt(
          id: 'done',
          start: DateTime(2026, 7, 8, 9),
          end: DateTime(2026, 7, 8, 10),
          status: 'done',
        ),
        _appt(id: 'tmwLater', start: DateTime(2026, 7, 9, 14)),
        _appt(id: 'tmwFirst', start: DateTime(2026, 7, 9, 9)),
      ], _now);

      // today has no incomplete jobs -> rolls over 1h after the 10:00 end.
      expect(payload['rolloverAt'], _iso(DateTime(2026, 7, 8, 11)));
      expect(payload['todayJobs'] as List, isEmpty);
      expect(
        (payload['tomorrowJobs'] as List).map((j) => (j as Map)['id']),
        ['tmwFirst', 'tmwLater'],
      );
    });

    test('nothing left today rolls over immediately (start of today)', () {
      final payload = buildWidgetPayload([
        _appt(id: 'past', start: DateTime(2026, 7, 8, 9), status: 'done'),
      ], _now);
      // The lone job is done and ended 10:00, so rollover is 11:00 — still past.
      expect(
        DateTime.parse(payload['rolloverAt'] as String).isBefore(_now),
        isTrue,
      );

      final empty = buildWidgetPayload(const [], _now);
      expect(empty['rolloverAt'], _iso(DateTime(2026, 7, 8)));
      expect(empty['todayJobs'] as List, isEmpty);
      expect(empty['tomorrowJobs'] as List, isEmpty);
    });

    test('cancelled today jobs do not hold the rollover', () {
      final payload = buildWidgetPayload([
        _appt(id: 'cxl', start: DateTime(2026, 7, 8, 15), status: 'cancelled'),
      ], _now);
      // Only a cancelled job today -> nothing to finish -> rolls immediately.
      expect(payload['rolloverAt'], _iso(DateTime(2026, 7, 8)));
    });

    test('locale is carried through', () {
      expect(buildWidgetPayload(const [], _now, locale: 'fr')['locale'], 'fr');
    });
  });
}

import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/home_widget/application/widget_sync_service.dart';

/// Fixed clock: Wednesday 2026-07-08, noon.
final _now = DateTime(2026, 7, 8, 12);

AppointmentRecord _appt({
  required String id,
  required DateTime start,
  String status = 'pending',
  String clientName = 'Client',
}) => AppointmentRecord(
  id: id,
  title: 'Job $id',
  clientName: clientName,
  startTime: start,
  endTime: start.add(const Duration(hours: 1)),
  status: status,
);

void main() {
  group('buildWidgetPayload', () {
    test('todays remaining jobs are future, non-terminal, and sorted', () {
      final payload = buildWidgetPayload([
        _appt(id: 'past', start: DateTime(2026, 7, 8, 9)),
        _appt(id: 'later', start: DateTime(2026, 7, 8, 16)),
        _appt(id: 'soon', start: DateTime(2026, 7, 8, 14)),
        _appt(id: 'done', start: DateTime(2026, 7, 8, 15), status: 'done'),
        _appt(id: 'tomorrow', start: DateTime(2026, 7, 9, 9)),
      ], _now);

      final jobs = payload['jobs'] as List;
      expect(payload['todayCount'], 2);
      expect((jobs.first as Map)['title'], 'Job soon');
      expect((jobs.last as Map)['title'], 'Job later');
    });

    test('nextJob can be on a later day when today has none left', () {
      final payload = buildWidgetPayload([
        _appt(id: 'past', start: DateTime(2026, 7, 8, 9)),
        _appt(id: 'tomorrow', start: DateTime(2026, 7, 9, 9)),
      ], _now);

      expect(payload['todayCount'], 0);
      expect((payload['jobs'] as List), isEmpty);
      expect((payload['nextJob'] as Map)['title'], 'Job tomorrow');
    });

    test('no upcoming jobs yields a null nextJob', () {
      final payload = buildWidgetPayload([
        _appt(id: 'past', start: DateTime(2026, 7, 8, 9)),
      ], _now);
      expect(payload['nextJob'], isNull);
    });

    test('locale is carried through', () {
      final payload = buildWidgetPayload(const [], _now, locale: 'fr');
      expect(payload['locale'], 'fr');
    });
  });
}

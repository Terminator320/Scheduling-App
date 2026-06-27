import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/features/calendar/application/event_series_helpers.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';

AppointmentRecord _appt(
  String id,
  DateTime start, {
  String status = 'pending',
}) => AppointmentRecord(
  id: id,
  startTime: start,
  endTime: start.add(const Duration(hours: 1)),
  status: status,
);

void main() {
  final base = DateTime(2026, 6, 1, 9);

  group('futureSeriesRecords', () {
    test('keeps future visits and drops the excluded one', () {
      final series = [
        _appt('a', base),
        _appt('b', base.add(const Duration(days: 7))),
        _appt('c', base.add(const Duration(days: 14))),
      ];
      final result = futureSeriesRecords(series, excludeId: 'a', after: base);
      expect(result.map((e) => e.id), ['b', 'c']);
    });

    test('drops done/cancelled (terminal) visits', () {
      final series = [
        _appt('b', base.add(const Duration(days: 7)), status: 'done'),
        _appt('c', base.add(const Duration(days: 14)), status: 'cancelled'),
        _appt('d', base.add(const Duration(days: 21))),
      ];
      final result = futureSeriesRecords(series, excludeId: 'a', after: base);
      expect(result.map((e) => e.id), ['d']);
    });

    test('drops visits at or before [after]', () {
      final series = [
        _appt('past', base.subtract(const Duration(days: 7))),
        _appt('now', base),
        _appt('future', base.add(const Duration(days: 7))),
      ];
      final result = futureSeriesRecords(series, excludeId: 'x', after: base);
      expect(result.map((e) => e.id), ['future']);
    });
  });

  group('futureSeriesIds', () {
    test('returns the ids of the future non-terminal visits', () {
      final series = [
        _appt('a', base),
        _appt('b', base.add(const Duration(days: 7))),
        _appt('c', base.add(const Duration(days: 14)), status: 'cancelled'),
      ];
      expect(futureSeriesIds(series, excludeId: 'a', after: base), ['b']);
    });
  });

  group('withTimeOfDay', () {
    test('keeps the date but takes the time of day from the source', () {
      final result = withTimeOfDay(
        DateTime(2026, 6, 15),
        DateTime(2000, 1, 1, 14, 30),
      );
      expect(result, DateTime(2026, 6, 15, 14, 30));
    });
  });

  group('placeholderClient', () {
    test('builds a minimal client from the appointment fields', () {
      final appt = _appt('a', base).copyWith(
        clientId: 'cid',
        clientName: 'Jane',
        clientPhone: '555',
        address: '1 St',
      );
      final client = placeholderClient(appt);
      expect(client.id, 'cid');
      expect(client.name, 'Jane');
      expect(client.phone, '555');
      expect(client.address, '1 St');
    });
  });
}

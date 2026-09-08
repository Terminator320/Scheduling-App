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

AppointmentRecord _runDay(
  String id,
  DateTime start, {
  required int dayIndex,
  required int dayCount,
  String status = 'pending',
}) => AppointmentRecord(
  id: id,
  startTime: start,
  endTime: start.add(const Duration(hours: 8)),
  status: status,
  seriesId: 'run',
  dayIndex: dayIndex,
  dayCount: dayCount,
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

  group('a RUN is ordered by dayIndex, not startTime', () {
    // A run member's start date stays editable, so time order and run order
    // can disagree. The stored dayIndex is the run's identity; the scope
    // dialog speaks in run positions, so the selection has to as well.
    List<AppointmentRecord> runOf5({DateTime? day1Start}) => [
      _runDay('d1', day1Start ?? base, dayIndex: 1, dayCount: 5),
      _runDay(
        'd2',
        base.add(const Duration(days: 1)),
        dayIndex: 2,
        dayCount: 5,
      ),
      _runDay(
        'd3',
        base.add(const Duration(days: 2)),
        dayIndex: 3,
        dayCount: 5,
      ),
      _runDay(
        'd4',
        base.add(const Duration(days: 3)),
        dayIndex: 4,
        dayCount: 5,
      ),
      _runDay(
        'd5',
        base.add(const Duration(days: 4)),
        dayIndex: 5,
        dayCount: 5,
      ),
    ];

    test('the tail of day 2 is days 3-5', () {
      final run = runOf5();
      final anchor = run[1];
      expect(
        futureSeriesIds(
          run,
          excludeId: 'd2',
          after: anchor.startTime,
          anchor: anchor,
        ),
        ['d3', 'd4', 'd5'],
      );
    });

    test('day 1 MOVED past its siblings still takes the whole tail', () {
      // Keyed on startTime this returned NOTHING and reported success, leaving
      // days 2-5 live after the admin cancelled "this and the following days".
      final moved = base.add(const Duration(days: 30));
      final run = runOf5(day1Start: moved);
      final anchor = run.first;
      expect(
        futureSeriesIds(
          run,
          excludeId: 'd1',
          after: anchor.startTime,
          anchor: anchor,
        ),
        ['d2', 'd3', 'd4', 'd5'],
      );
    });

    test('a later day does NOT sweep up a day 1 that moved after it', () {
      // The same bug read from the other end: on startTime, the moved day 1
      // looked like a future sibling of day 4.
      final run = runOf5(day1Start: base.add(const Duration(days: 30)));
      final anchor = run[3];
      expect(
        futureSeriesIds(
          run,
          excludeId: 'd4',
          after: anchor.startTime,
          anchor: anchor,
        ),
        ['d5'],
      );
    });

    test('with no anchor the comparison stays on startTime', () {
      // A repeat series shares seriesId but no dayIndex, and time is the
      // right ordering there.
      final series = [
        _appt('a', base),
        _appt('b', base.add(const Duration(days: 7))),
      ];
      expect(
        futureSeriesIds(series, excludeId: 'a', after: base),
        ['b'],
      );
    });

    test('an incoherent stored pair falls back to startTime', () {
      final anchor = _runDay('x', base, dayIndex: 0, dayCount: 5);
      final series = [anchor, _appt('b', base.add(const Duration(days: 1)))];
      expect(
        futureSeriesIds(
          series,
          excludeId: 'x',
          after: base,
          anchor: anchor,
        ),
        ['b'],
      );
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

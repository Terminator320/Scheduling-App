import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/dashboard/domain/dashboard_aggregator.dart';
import 'package:scheduling/features/dashboard/domain/dashboard_period.dart';

/// Fixed clock: Wednesday 2026-07-08, noon. That week's Monday is 2026-07-06.
final _now = DateTime(2026, 7, 8, 12);

AppointmentRecord _appt({
  required String id,
  required DateTime start,
  Duration duration = const Duration(hours: 1),
  String status = 'pending',
}) => AppointmentRecord(
  id: id,
  title: 'Job $id',
  startTime: start,
  endTime: start.add(duration),
  status: status,
  employeeIds: const ['e1'],
);

void main() {
  group('windowFor', () {
    test('today runs midnight to midnight, not from now', () {
      final window = DashboardPeriod.today.windowFor(_now);

      expect(window.start, DateTime(2026, 7, 8));
      expect(window.end, DateTime(2026, 7, 9));
    });

    test(
      'week starts at the ISO Monday, sharing mondayOf with the aggregator',
      () {
        final window = DashboardPeriod.week.windowFor(_now);

        expect(window.start, DashboardAggregator.mondayOf(_now));
        expect(window.start, DateTime(2026, 7, 6));
      },
    );

    test('month starts on the 1st', () {
      expect(DashboardPeriod.month.windowFor(_now).start, DateTime(2026, 7));
    });

    test('every period is to-date — they all end at the end of today', () {
      // Not whole calendar spans: there are no completed jobs in the future,
      // and a whole-month window would run past the data that is fetched.
      for (final period in DashboardPeriod.values) {
        expect(
          period.windowFor(_now).end,
          DateTime(2026, 7, 9),
          reason: '${period.name} should end at the end of today',
        );
      }
    });
  });

  group('every period fits inside the fetched window', () {
    // This is what keeps the control a pure in-memory filter. If it ever
    // fails, the period has to widen the HISTORY half of the range — never
    // the live one, which would undo the 2026-08-08 split.
    final fetched = DashboardAggregator.rangeAround(_now);

    for (final period in DashboardPeriod.values) {
      test('${period.name} needs no data the dashboard has not fetched', () {
        final window = period.windowFor(_now);

        expect(window.start.isBefore(fetched.start), isFalse);
        expect(window.end.isAfter(fetched.end), isFalse);
      });
    }
  });

  group('computePeriodSummary', () {
    PeriodSummaryOf summarize(
      DashboardPeriod period,
      List<AppointmentRecord> appointments, {
      List<DateTime> clients = const [],
    }) {
      final s = DashboardAggregator.computePeriodSummary(
        appointments: appointments,
        clientCreatedDates: clients,
        window: period.windowFor(_now),
      );
      return (
        booked: s.booked,
        completed: s.completed,
        cancelled: s.cancelled,
        newClients: s.newClients,
      );
    }

    test('counts a job on the day it runs and not the day before', () {
      final jobs = [
        _appt(id: 'a', start: DateTime(2026, 7, 8, 9)),
        _appt(id: 'b', start: DateTime(2026, 7, 7, 9)),
      ];

      expect(summarize(DashboardPeriod.today, jobs).booked, 1);
      expect(summarize(DashboardPeriod.week, jobs).booked, 2);
    });

    test('a run that began before today still counts today', () {
      // The regression the whole `runsInRange` rule exists for: testing
      // `startTime` would drop day 3 of a run that started on the 6th.
      final job = _appt(
        id: 'multi',
        start: DateTime(2026, 7, 6, 9),
        duration: const Duration(days: 4, hours: 8),
      );

      expect(summarize(DashboardPeriod.today, [job]).booked, 1);
    });

    test('a job that ended before the period is not counted', () {
      final job = _appt(id: 'old', start: DateTime(2026, 7, 1, 9));

      expect(summarize(DashboardPeriod.today, [job]).booked, 0);
      expect(summarize(DashboardPeriod.month, [job]).booked, 1);
    });

    test('cancelled work counts as cancelled and never as booked', () {
      final jobs = [
        _appt(id: 'a', start: DateTime(2026, 7, 8, 9), status: 'cancelled'),
        _appt(id: 'b', start: DateTime(2026, 7, 8, 9), status: 'done'),
      ];
      final summary = summarize(DashboardPeriod.today, jobs);

      expect(summary.cancelled, 1);
      expect(summary.booked, 1);
      expect(summary.completed, 1);
    });

    test('new clients are counted on the window boundaries half-open', () {
      final clients = [
        DateTime(2026, 7, 8),
        DateTime(2026, 7, 9),
        DateTime(2026, 7, 7, 23, 59),
      ];

      expect(
        summarize(DashboardPeriod.today, const [], clients: clients).newClients,
        1,
      );
    });
  });
}

typedef PeriodSummaryOf = ({
  int booked,
  int completed,
  int cancelled,
  int newClients,
});

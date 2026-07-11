import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/dashboard/domain/dashboard_aggregator.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';

/// Fixed clock: Wednesday 2026-07-08, noon.
final _now = DateTime(2026, 7, 8, 12);

const _e1 = EmployeeRecord(id: 'e1', name: 'Jane', status: 'active');
const _e2 = EmployeeRecord(id: 'e2', name: 'Marc', status: 'active');

AppointmentRecord _appt({
  required String id,
  required DateTime start,
  Duration duration = const Duration(hours: 1),
  String status = 'pending',
  List<String> employeeIds = const ['e1'],
}) => AppointmentRecord(
  id: id,
  title: 'Job $id',
  startTime: start,
  endTime: start.add(duration),
  status: status,
  employeeIds: employeeIds,
);

void main() {
  group('mondayOf', () {
    test('returns Monday midnight for a mid-week day', () {
      expect(
        DashboardAggregator.mondayOf(DateTime(2026, 7, 8, 15, 30)),
        DateTime(2026, 7, 6),
      );
    });

    test('is idempotent on a Monday', () {
      expect(
        DashboardAggregator.mondayOf(DateTime(2026, 7, 6)),
        DateTime(2026, 7, 6),
      );
    });

    test('a late Sunday still belongs to the week that started 6 days ago', () {
      expect(
        DashboardAggregator.mondayOf(DateTime(2026, 7, 12, 23, 59)),
        DateTime(2026, 7, 6),
      );
    });
  });

  group('rangeAround', () {
    test('mid-week: 8 Monday-aligned weeks back through next Monday', () {
      final range = DashboardAggregator.rangeAround(_now);
      expect(range.start, DateTime(2026, 5, 18));
      expect(range.end, DateTime(2026, 7, 13));
    });

    test('Sunday: the +3d arm extends past next Monday to cover 48h flags', () {
      final range = DashboardAggregator.rangeAround(DateTime(2026, 7, 12, 20));
      expect(range.start, DateTime(2026, 5, 18));
      expect(range.end, DateTime(2026, 7, 15));
    });

    test('midnight edge: exactly 00:00 counts as that day', () {
      final range = DashboardAggregator.rangeAround(DateTime(2026, 7, 8));
      expect(range.start, DateTime(2026, 5, 18));
      expect(range.end, DateTime(2026, 7, 13));
    });
  });

  group('displayStatusAt', () {
    test('non-terminal past start (not yet ended) becomes in_progress', () {
      // Starts 11:30, ends 12:30 — now (12:00) is inside the visit.
      final a = _appt(id: 'a', start: DateTime(2026, 7, 8, 11, 30));
      expect(DashboardAggregator.displayStatusAt(a, _now), 'in_progress');
    });

    test('non-terminal past end becomes overdue', () {
      // Starts 9:00, ends 10:00 — now (12:00) is past the end, still open.
      final a = _appt(id: 'a', start: DateTime(2026, 7, 8, 9));
      expect(DashboardAggregator.displayStatusAt(a, _now), 'overdue');
    });

    test('terminal statuses pass through even when started', () {
      final done = _appt(
        id: 'a',
        start: DateTime(2026, 7, 8, 9),
        status: 'done',
      );
      final cancelled = _appt(
        id: 'b',
        start: DateTime(2026, 7, 8, 9),
        status: 'cancelled',
      );
      expect(DashboardAggregator.displayStatusAt(done, _now), 'done');
      expect(DashboardAggregator.displayStatusAt(cancelled, _now), 'cancelled');
    });

    test('future visit keeps its raw status (not promoted to in_progress)', () {
      final a = _appt(
        id: 'a',
        start: DateTime(2026, 7, 8, 14),
        status: 'pending',
      );
      expect(DashboardAggregator.displayStatusAt(a, _now), 'pending');
    });
  });

  group('computeTodayOps', () {
    test('counts today by normalized display status', () {
      final ops = DashboardAggregator.computeTodayOps([
        // Started 11:30, ends 12:30 -> in_progress (not yet ended).
        _appt(id: 'running', start: DateTime(2026, 7, 8, 11, 30)),
        _appt(
          id: 'later',
          start: DateTime(2026, 7, 8, 14),
          status: 'pending',
        ),
        // Legacy raw 'completed' normalizes to done.
        _appt(
          id: 'legacy',
          start: DateTime(2026, 7, 8, 8),
          status: 'completed',
        ),
        _appt(id: 'notToday', start: DateTime(2026, 7, 7, 9)),
      ], _now);
      expect(ops.statusCounts, {
        'in_progress': 1,
        'pending': 1,
        'done': 1,
      });
    });

    test('ended-but-open today visits land in the overdue bucket', () {
      final ops = DashboardAggregator.computeTodayOps([
        // Started 9:00, ended 10:00, still pending -> overdue.
        _appt(id: 'ended', start: DateTime(2026, 7, 8, 9)),
        // Started 11:30, ends 12:30 -> in_progress.
        _appt(id: 'running', start: DateTime(2026, 7, 8, 11, 30)),
      ], _now);
      // Overdue keys on the literal 'overdue' (AppointmentStatus.overdue.raw
      // throws), so computeTodayOps must not round-trip through `.raw`.
      expect(ops.statusCounts, {'overdue': 1, 'in_progress': 1});
    });

    test('unassigned counts empty employeeIds today, excluding cancelled', () {
      final ops = DashboardAggregator.computeTodayOps([
        _appt(
          id: 'open',
          start: DateTime(2026, 7, 8, 15),
          employeeIds: const [],
        ),
        _appt(
          id: 'cancelledOpen',
          start: DateTime(2026, 7, 8, 16),
          status: 'cancelled',
          employeeIds: const [],
        ),
      ], _now);
      expect(ops.unassignedCount, 1);
    });

    test('upcoming is future, non-terminal, sorted, capped at 5', () {
      final appointments = [
        for (var h = 20; h >= 13; h--) // 8 future visits, reverse order
          _appt(id: 'h$h', start: DateTime(2026, 7, 8, h)),
        _appt(id: 'started', start: DateTime(2026, 7, 8, 9)),
        _appt(
          id: 'cancelled',
          start: DateTime(2026, 7, 8, 14, 30),
          status: 'cancelled',
        ),
      ];
      final ops = DashboardAggregator.computeTodayOps(appointments, _now);
      expect(ops.upcoming, hasLength(5));
      expect(ops.upcoming.first.id, 'h13');
      expect(ops.upcoming.last.id, 'h17');
    });
  });

  group('computeWorkload', () {
    test('per-assignee today/week counts, cancelled excluded', () {
      final workload = DashboardAggregator.computeWorkload(
        [
          // Monday of this week, e1 only.
          _appt(id: 'mon', start: DateTime(2026, 7, 6, 9)),
          // Today, both assignees — counts once per assignee.
          _appt(
            id: 'both',
            start: DateTime(2026, 7, 8, 14),
            employeeIds: const ['e1', 'e2'],
          ),
          // Cancelled today — excluded everywhere.
          _appt(
            id: 'cxl',
            start: DateTime(2026, 7, 8, 15),
            status: 'cancelled',
          ),
          // Next Monday — outside this week.
          _appt(id: 'next', start: DateTime(2026, 7, 13, 9)),
        ],
        const [_e1, _e2],
        _now,
      );
      expect(workload, hasLength(2));
      expect(workload[0].employee.id, 'e1');
      expect(workload[0].todayCount, 1);
      expect(workload[0].weekCount, 2);
      expect(workload[1].employee.id, 'e2');
      expect(workload[1].todayCount, 1);
      expect(workload[1].weekCount, 1);
    });

    test('Monday 00:00 exactly belongs to this week', () {
      final workload = DashboardAggregator.computeWorkload(
        [_appt(id: 'edge', start: DateTime(2026, 7, 6))],
        const [_e1],
        _now,
      );
      expect(workload.single.weekCount, 1);
    });
  });

  group('computeWeekBuckets', () {
    test('8 buckets; boundaries land in the newer week; legacy completed '
        'counts as completed', () {
      final buckets = DashboardAggregator.computeWeekBuckets(
        [
          // Exactly the range start -> bucket 0.
          _appt(id: 'first', start: DateTime(2026, 5, 18), status: 'done'),
          // One second before the range start -> dropped.
          _appt(
            id: 'before',
            start: DateTime(2026, 5, 17, 23, 59, 59),
            status: 'done',
          ),
          // Legacy raw.
          _appt(
            id: 'legacy',
            start: DateTime(2026, 5, 20),
            status: 'completed',
          ),
          // Current week.
          _appt(id: 'thisWk', start: DateTime(2026, 7, 7), status: 'done'),
          _appt(
            id: 'cxl',
            start: DateTime(2026, 7, 7, 10),
            status: 'cancelled',
          ),
        ],
        [
          DateTime(2026, 5, 19), // bucket 0
          DateTime(2026, 7, 8, 11), // bucket 7
        ],
        _now,
      );
      expect(buckets, hasLength(8));
      expect(buckets.first.weekStart, DateTime(2026, 5, 18));
      expect(buckets.last.weekStart, DateTime(2026, 7, 6));
      expect(buckets[0].completed, 2); // 'first' + 'legacy'
      expect(buckets[0].newClients, 1);
      expect(buckets[7].completed, 1);
      expect(buckets[7].cancelled, 1);
      expect(buckets[7].newClients, 1);
      final total = buckets.fold(
        0,
        (sum, b) => sum + b.completed + b.cancelled,
      );
      expect(total, 4); // 'before' was dropped
    });
  });

  group('computeBusiestWeekday', () {
    test('tie resolves to the earliest weekday; cancelled excluded', () {
      final busiest = DashboardAggregator.computeBusiestWeekday([
        _appt(id: 'f1', start: DateTime(2026, 6, 5, 9)), // Friday
        _appt(id: 'f2', start: DateTime(2026, 6, 12, 9)), // Friday
        _appt(id: 'm1', start: DateTime(2026, 6, 1, 9)), // Monday
        _appt(id: 'm2', start: DateTime(2026, 6, 8, 9)), // Monday
        _appt(
          id: 'fCxl',
          start: DateTime(2026, 6, 19, 9), // Friday, cancelled
          status: 'cancelled',
        ),
      ], _now);
      expect(busiest, isNotNull);
      expect(busiest!.weekday, DateTime.monday);
      expect(busiest.count, 2);
    });

    test('returns null with nothing to count', () {
      expect(DashboardAggregator.computeBusiestWeekday(const [], _now), isNull);
    });
  });

  group('computeAttentionFlags', () {
    test('pendingSoon: raw pending inside (now, now+48h]', () {
      final flags = DashboardAggregator.computeAttentionFlags([
        _appt(id: 'in47', start: _now.add(const Duration(hours: 47))),
        _appt(id: 'out49', start: _now.add(const Duration(hours: 49))),
        // Already started pending is NOT "starting soon".
        _appt(id: 'started', start: _now.subtract(const Duration(hours: 1))),
        // Raw status must be pending — a done visit starting soon is excluded.
        _appt(
          id: 'doneSoon',
          start: _now.add(const Duration(hours: 5)),
          status: 'done',
        ),
      ], _now);
      expect(flags.pendingSoon.map((a) => a.id), ['in47']);
    });

    test('overdueOpen: ended, raw status non-terminal', () {
      final flags = DashboardAggregator.computeAttentionFlags([
        _appt(
          id: 'overdue',
          start: DateTime(2026, 7, 7, 9),
          status: 'in_progress',
        ),
        _appt(id: 'closed', start: DateTime(2026, 7, 7, 10), status: 'done'),
        _appt(
          id: 'cxl',
          start: DateTime(2026, 7, 7, 11),
          status: 'cancelled',
        ),
        // Started but not ended yet — not overdue.
        _appt(
          id: 'running',
          start: _now.subtract(const Duration(minutes: 30)),
        ),
      ], _now);
      expect(flags.overdueOpen.map((a) => a.id), ['overdue']);
      expect(flags.isAllClear, isFalse);
    });

    test('isAllClear when both lists are empty', () {
      final flags = DashboardAggregator.computeAttentionFlags(const [], _now);
      expect(flags.isAllClear, isTrue);
    });
  });
}

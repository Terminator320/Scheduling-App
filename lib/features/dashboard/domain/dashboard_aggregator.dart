import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/dashboard/domain/dashboard_stats.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';
import 'package:scheduling/shared/widgets/feedback/status_chip.dart';

/// Pure reducers over the one dashboard appointments range. Every function
/// takes `now` explicitly so the whole feature tests with a fixed clock.
///
/// Accepted limitations (see docs/plans/2026-07-08-admin-dashboard.md):
/// overdue flags look back only as far as the 8-week range start, and "today"
/// is fixed at provider build (autoDispose refreshes on reopen, not across
/// midnight while the screen stays open).
class DashboardAggregator {
  DashboardAggregator._();

  static const int weekCount = 8;
  static const Duration pendingSoonWindow = Duration(hours: 48);
  static const int upcomingLimit = 5;

  /// Midnight on the Monday of [day]'s week (ISO week start).
  static DateTime mondayOf(DateTime day) =>
      DateTime(day.year, day.month, day.day - (day.weekday - DateTime.monday));

  /// The single midnight-aligned query range every section reduces off:
  /// 8 ISO weeks back through at least next Monday; the `+3 days` arm keeps
  /// the 48 h pending window covered when `now` is a Sunday.
  static AppointmentDateRange rangeAround(DateTime now) {
    final monday = mondayOf(now);
    final start = DateTime(
      monday.year,
      monday.month,
      monday.day - 7 * (weekCount - 1),
    );
    final nextMonday = DateTime(monday.year, monday.month, monday.day + 7);
    final pendingHorizon = DateTime(now.year, now.month, now.day + 3);
    return AppointmentDateRange(
      start: start,
      end: nextMonday.isAfter(pendingHorizon) ? nextMonday : pendingHorizon,
    );
  }

  /// Testable stand-in for [AppointmentRecord.displayStatus] (the model getter
  /// reads DateTime.now()): terminal statuses pass through; a non-terminal
  /// visit whose start has passed is in_progress.
  ///
  /// DELIBERATELY does NOT reproduce the model's `overdue` branch. This drives
  /// [computeTodayOps]'s status-count map, whose keys round-trip through
  /// `AppointmentStatus.fromRaw(...).raw` — and `AppointmentStatus.overdue.raw`
  /// THROWS (overdue is display-only). The dashboard hero renders only the four
  /// stored statuses; ended-but-open visits are surfaced separately as
  /// [AttentionFlags.overdueOpen]. Do not "sync" this with `displayStatus` by
  /// adding an overdue branch without also removing the `.raw` round-trip, or
  /// [computeTodayOps] will crash.
  static String displayStatusAt(AppointmentRecord appointment, DateTime now) {
    if (_isTerminal(appointment)) return appointment.status;
    if (now.isAfter(appointment.startTime)) return 'in_progress';
    return appointment.status;
  }

  static TodayOps computeTodayOps(
    List<AppointmentRecord> appointments,
    DateTime now,
  ) {
    final dayStart = DateTime(now.year, now.month, now.day);
    final counts = <String, int>{};
    var unassigned = 0;
    final upcoming = <AppointmentRecord>[];
    for (final a in appointments) {
      if (!_startsOnDay(a, dayStart)) continue;
      final display = AppointmentStatus.fromRaw(displayStatusAt(a, now)).raw;
      counts[display] = (counts[display] ?? 0) + 1;
      if (a.employeeIds.isEmpty && !_isCancelled(a)) unassigned++;
      if (a.startTime.isAfter(now) && !_isTerminal(a)) upcoming.add(a);
    }
    upcoming.sort((x, y) => x.startTime.compareTo(y.startTime));
    return TodayOps(
      statusCounts: counts,
      unassignedCount: unassigned,
      upcoming: upcoming.take(upcomingLimit).toList(),
    );
  }

  /// Jobs per employee today / this ISO week, cancelled excluded; a
  /// multi-assignee visit counts once per assignee. [employees] is the
  /// active-only list from `employeesStreamProvider`.
  static List<EmployeeWorkload> computeWorkload(
    List<AppointmentRecord> appointments,
    List<EmployeeRecord> employees,
    DateTime now,
  ) {
    final dayStart = DateTime(now.year, now.month, now.day);
    final weekStart = mondayOf(now);
    final weekEnd = DateTime(
      weekStart.year,
      weekStart.month,
      weekStart.day + 7,
    );
    final today = <String, int>{};
    final week = <String, int>{};
    for (final a in appointments) {
      if (_isCancelled(a)) continue;
      if (a.startTime.isBefore(weekStart) || !a.startTime.isBefore(weekEnd)) {
        continue;
      }
      final inDay = _startsOnDay(a, dayStart);
      for (final id in a.employeeIds) {
        week[id] = (week[id] ?? 0) + 1;
        if (inDay) today[id] = (today[id] ?? 0) + 1;
      }
    }
    return [
      for (final e in employees)
        EmployeeWorkload(
          employee: e,
          todayCount: today[e.id] ?? 0,
          weekCount: week[e.id] ?? 0,
        ),
    ];
  }

  /// The 8 Monday-midnight week starts, oldest first, ending with the
  /// current week.
  static List<DateTime> weekStartsFor(DateTime now) {
    final monday = mondayOf(now);
    return [
      for (var i = weekCount - 1; i >= 0; i--)
        DateTime(monday.year, monday.month, monday.day - 7 * i),
    ];
  }

  static List<WeekBucket> computeWeekBuckets(
    List<AppointmentRecord> appointments,
    List<DateTime> clientCreatedDates,
    DateTime now,
  ) {
    final weekStarts = weekStartsFor(now);
    final horizon = _weekAfter(weekStarts.last);
    final completed = List<int>.filled(weekCount, 0);
    final cancelled = List<int>.filled(weekCount, 0);
    final newClients = List<int>.filled(weekCount, 0);
    for (final a in appointments) {
      final i = _bucketIndex(weekStarts, horizon, a.startTime);
      if (i < 0) continue;
      final s = a.status.toLowerCase();
      if (s == 'done' || s == 'completed') completed[i]++;
      if (s == 'cancelled') cancelled[i]++;
    }
    for (final date in clientCreatedDates) {
      final i = _bucketIndex(weekStarts, horizon, date);
      if (i >= 0) newClients[i]++;
    }
    return [
      for (var i = 0; i < weekCount; i++)
        WeekBucket(
          weekStart: weekStarts[i],
          completed: completed[i],
          cancelled: cancelled[i],
          newClients: newClients[i],
        ),
    ];
  }

  /// Busiest weekday over the whole window, cancelled excluded; ties resolve
  /// to the earliest weekday (Monday first). Null when nothing counts.
  static BusiestWeekday? computeBusiestWeekday(
    List<AppointmentRecord> appointments,
    DateTime now,
  ) {
    final weekStarts = weekStartsFor(now);
    final horizon = _weekAfter(weekStarts.last);
    final counts = List<int>.filled(DateTime.daysPerWeek + 1, 0);
    for (final a in appointments) {
      if (_isCancelled(a)) continue;
      if (_bucketIndex(weekStarts, horizon, a.startTime) < 0) continue;
      counts[a.startTime.weekday]++;
    }
    var bestDay = 0;
    var bestCount = 0;
    for (var day = DateTime.monday; day <= DateTime.sunday; day++) {
      if (counts[day] > bestCount) {
        bestDay = day;
        bestCount = counts[day];
      }
    }
    if (bestCount == 0) return null;
    return BusiestWeekday(weekday: bestDay, count: bestCount);
  }

  static AttentionFlags computeAttentionFlags(
    List<AppointmentRecord> appointments,
    DateTime now,
  ) {
    final soonCutoff = now.add(pendingSoonWindow);
    final pendingSoon = <AppointmentRecord>[];
    final overdueOpen = <AppointmentRecord>[];
    for (final a in appointments) {
      if (a.status.toLowerCase() == 'pending' &&
          a.startTime.isAfter(now) &&
          !a.startTime.isAfter(soonCutoff)) {
        pendingSoon.add(a);
      }
      if (a.endTime.isBefore(now) && !_isTerminal(a)) {
        overdueOpen.add(a);
      }
    }
    pendingSoon.sort((x, y) => x.startTime.compareTo(y.startTime));
    overdueOpen.sort((x, y) => x.startTime.compareTo(y.startTime));
    return AttentionFlags(pendingSoon: pendingSoon, overdueOpen: overdueOpen);
  }

  static DashboardStats computeStats({
    required List<AppointmentRecord> appointments,
    required List<EmployeeRecord> employees,
    required List<DateTime> clientCreatedDates,
    required DateTime now,
  }) => DashboardStats(
    todayOps: computeTodayOps(appointments, now),
    workload: computeWorkload(appointments, employees, now),
    weekBuckets: computeWeekBuckets(appointments, clientCreatedDates, now),
    busiestWeekday: computeBusiestWeekday(appointments, now),
    flags: computeAttentionFlags(appointments, now),
  );

  static bool _isCancelled(AppointmentRecord a) =>
      a.status.toLowerCase() == 'cancelled';

  static bool _isTerminal(AppointmentRecord a) {
    final s = a.status.toLowerCase();
    return s == 'done' || s == 'completed' || s == 'cancelled';
  }

  static bool _startsOnDay(AppointmentRecord a, DateTime dayStart) {
    final dayEnd = DateTime(dayStart.year, dayStart.month, dayStart.day + 1);
    return !a.startTime.isBefore(dayStart) && a.startTime.isBefore(dayEnd);
  }

  static DateTime _weekAfter(DateTime weekStart) =>
      DateTime(weekStart.year, weekStart.month, weekStart.day + 7);

  /// Index of the week bucket containing [t], or -1 outside the window.
  static int _bucketIndex(
    List<DateTime> weekStarts,
    DateTime horizon,
    DateTime t,
  ) {
    if (!t.isBefore(horizon)) return -1;
    for (var i = weekStarts.length - 1; i >= 0; i--) {
      if (!t.isBefore(weekStarts[i])) return i;
    }
    return -1;
  }
}

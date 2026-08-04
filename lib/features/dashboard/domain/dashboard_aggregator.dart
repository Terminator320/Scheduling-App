import 'package:scheduling/core/utils/date_utils_helper.dart';
import 'package:scheduling/features/calendar/domain/appointment_day_slice.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/dashboard/domain/dashboard_stats.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';
import 'package:scheduling/shared/widgets/feedback/status_chip.dart';

/// Pure reducer functions over the dashboard's appointment range, keyed on
/// `now` so tests can control the clock.
class DashboardAggregator {
  DashboardAggregator._();

  static const int weekCount = 8;
  static const Duration pendingSoonWindow = Duration(hours: 48);
  static const int upcomingLimit = 5;

  /// Midnight on the Monday of [day]'s week (ISO week start).
  static DateTime mondayOf(DateTime day) =>
      DateTime(day.year, day.month, day.day - (day.weekday - DateTime.monday));

  /// The query range spans 8 ISO weeks back through next Monday, extended
  /// by 3 days to cover the pending window.
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

  /// Delegates to [AppointmentRecord.displayStatusAt], which owns the ladder —
  /// this used to be a hand-copied mirror and had already drifted (it was
  /// missing the isPersonal carve-out, so the dashboard reported a personal
  /// block as overdue while its card said Scheduled). Use statusCountKey to key
  /// off the result; calling `.raw` directly on overdue would throw.
  static String displayStatusAt(AppointmentRecord appointment, DateTime now) =>
      appointment.displayStatusAt(now);

  /// Stable key for statusCounts. 'overdue' has no stored raw value, so we
  /// just key it on the literal string 'overdue'.
  static String statusCountKey(AppointmentStatus status) =>
      status == AppointmentStatus.overdue ? 'overdue' : status.raw;

  static TodayOps computeTodayOps(
    List<AppointmentRecord> appointments,
    DateTime now,
  ) {
    final dayStart = now.dateOnly;
    final counts = <String, int>{};
    var unassigned = 0;
    final upcoming = <AppointmentRecord>[];
    for (final a in appointments) {
      // Re-scoped through the slice owner: the range stream is a superset,
      // and testing `startTime` alone hid days 2+ of a multi-day run.
      if (!runsOn(a, dayStart)) continue;
      final display = statusCountKey(
        AppointmentStatus.fromRaw(displayStatusAt(a, now)),
      );
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

  /// Counts jobs per employee for today and for this ISO week. Cancelled
  /// visits are excluded, and a multi-assignee visit counts once for each
  /// assignee. [employees] should be the active-only list from
  /// `employeesStreamProvider`.
  static List<EmployeeWorkload> computeWorkload(
    List<AppointmentRecord> appointments,
    List<EmployeeRecord> employees,
    DateTime now,
  ) {
    final dayStart = now.dateOnly;
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
      // Overlap, not "starts this week": a run booked last Friday is still
      // this week's load on the Monday the crew is on it.
      if (!runsInRange(a, weekStart, weekEnd)) continue;
      final inDay = runsOn(a, dayStart);
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
      final status = AppointmentStatus.fromRaw(a.status);
      if (status.isDone) completed[i]++;
      if (status.isCancelled) cancelled[i]++;
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

  /// Finds the busiest weekday over the window, excluding cancelled visits.
  /// Ties go to the earliest weekday, and this returns null when nothing
  /// counts.
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
      if (AppointmentStatus.fromRaw(a.status) == AppointmentStatus.pending &&
          a.startTime.isAfter(now) &&
          !a.startTime.isAfter(soonCutoff)) {
        pendingSoon.add(a);
      }
      if (displayStatusAt(a, now) == 'overdue') {
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
      AppointmentStatus.fromRaw(a.status).isCancelled;

  static bool _isTerminal(AppointmentRecord a) =>
      AppointmentStatus.fromRaw(a.status).isTerminal;

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

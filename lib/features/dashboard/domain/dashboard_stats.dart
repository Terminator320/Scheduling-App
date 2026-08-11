import 'package:flutter/foundation.dart' show immutable;

import 'package:scheduling/features/calendar/domain/appointment_day_slice.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';

/// Today's status counts, unassigned jobs, and the next upcoming visits.
@immutable
class TodayOps {
  const TodayOps({
    required this.statusCounts,
    required this.unassignedCount,
    required this.upcoming,
  });

  /// Keyed by normalized display-status raw value ('pending', 'in_progress', 'done', 'cancelled').
  final Map<String, int> statusCounts;
  final int unassignedCount;

  /// Day-scoped, so a multi-day run is judged by TODAY's window rather than
  /// the morning it first started — and the card can show "Day 3 of 5".
  final List<AppointmentDaySlice> upcoming;

  /// Every visit today regardless of status — the hero's big number.
  int get total => statusCounts.values.fold(0, (sum, n) => sum + n);
}

@immutable
class EmployeeWorkload {
  const EmployeeWorkload({
    required this.employee,
    required this.todayCount,
    required this.weekCount,
  });

  final EmployeeRecord employee;
  final int todayCount;
  final int weekCount;
}

/// One day of the current ISO week: how many jobs are booked on it, and how
/// many the available roster can take.
@immutable
class DayLoad {
  const DayLoad({
    required this.day,
    required this.count,
    required this.capacity,
  });

  final DateTime day;
  final int count;

  /// Summed `maxJobsPerDay` over the staff who work that weekday.
  ///
  /// **Zero means "no capacity is configured", not "no capacity"** — the field
  /// defaults to 0 and most rosters never set it, so a chart that read 0 as a
  /// ceiling would paint every bar over-capacity red. Renderers draw no
  /// capacity line at all in that case.
  final int capacity;

  bool get isOverCapacity => capacity > 0 && count > capacity;
}

@immutable
class WeekBucket {
  const WeekBucket({
    required this.weekStart,
    required this.completed,
    required this.cancelled,
    required this.newClients,
  });

  final DateTime weekStart;
  final int completed;
  final int cancelled;
  final int newClients;
}

/// The KPI numbers for the selected `DashboardPeriod`.
///
/// Deliberately NOT part of [DashboardStats]: everything there answers a
/// "right now" question and is period-independent, while these four move with
/// the segmented control. Keeping them apart is what lets a period change
/// recompute four counters instead of every section on the screen.
@immutable
class PeriodSummary {
  const PeriodSummary({
    required this.booked,
    required this.completed,
    required this.cancelled,
    required this.newClients,
  });

  /// Jobs running in the period, cancelled ones excluded — they are counted
  /// on their own and were never booked business.
  final int booked;
  final int completed;
  final int cancelled;
  final int newClients;
}

@immutable
class BusiestWeekday {
  const BusiestWeekday({required this.weekday, required this.count});

  /// DateTime.monday (1) .. DateTime.sunday (7).
  final int weekday;
  final int count;
}

@immutable
class AttentionFlags {
  const AttentionFlags({
    required this.pendingSoon,
    required this.overdueOpen,
  });

  final List<AppointmentRecord> pendingSoon;
  final List<AppointmentRecord> overdueOpen;

  bool get isAllClear => pendingSoon.isEmpty && overdueOpen.isEmpty;
}

@immutable
class DashboardStats {
  const DashboardStats({
    required this.todayOps,
    required this.workload,
    required this.dailyLoad,
    required this.weekBuckets,
    required this.busiestWeekday,
    required this.flags,
  });

  final TodayOps todayOps;
  final List<EmployeeWorkload> workload;
  final List<DayLoad> dailyLoad;
  final List<WeekBucket> weekBuckets;
  final BusiestWeekday? busiestWeekday;
  final AttentionFlags flags;
}

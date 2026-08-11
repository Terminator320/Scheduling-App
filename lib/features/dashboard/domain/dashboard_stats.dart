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
    required this.weekBuckets,
    required this.busiestWeekday,
    required this.flags,
  });

  final TodayOps todayOps;
  final List<EmployeeWorkload> workload;
  final List<WeekBucket> weekBuckets;
  final BusiestWeekday? busiestWeekday;
  final AttentionFlags flags;
}

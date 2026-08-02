import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/utils/current_day_provider.dart';
import 'package:scheduling/features/calendar/application/appointments_providers.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';

/// Today, as a single-day range. Keyed off `currentDayProvider` rather than
/// `DateTime.now()` so an app left open across midnight rolls over — the same
/// rule the calendar's today-circle and the off-screen mirrors follow.
final todayRangeProvider = Provider<AppointmentDateRange>((ref) {
  final today = ref.watch(currentDayProvider);
  return AppointmentDateRange(
    start: DateTime(today.year, today.month, today.day),
    end: DateTime(today.year, today.month, today.day + 1),
  );
});

/// How many jobs each employee is booked for today, keyed by users-doc id.
///
/// ONE day-range listener reduced in Dart — never one query per roster row.
/// Cancelled visits don't count: the row is answering "how loaded are they",
/// and a cancelled job is not load.
final employeeJobsTodayProvider = Provider<Map<String, int>>((ref) {
  final range = ref.watch(todayRangeProvider);
  final jobs = ref.watch(appointmentsInRangeProvider(range)).value ?? const [];
  final counts = <String, int>{};
  for (final job in jobs) {
    if (job.status == 'cancelled') continue;
    for (final id in job.employeeIds) {
      counts[id] = (counts[id] ?? 0) + 1;
    }
  }
  return counts;
});

/// How many future jobs an employee is still assigned to — the caption under
/// the Disable account button. Autodisposed and family-keyed so it is fetched
/// once per sheet open, not per rebuild.
final futureAssignmentCountProvider = FutureProvider.autoDispose
    .family<int, String>((ref, employeeId) {
      return ref
          .read(appointmentsRepositoryProvider)
          .countFutureAssignments(employeeId);
    });

/// One employee's jobs today, in start order — the detail page's TODAY panel.
final employeeTodayJobsProvider = Provider.autoDispose
    .family<List<AppointmentRecord>, String>((ref, employeeId) {
      final range = ref.watch(todayRangeProvider);
      final jobs =
          ref
              .watch(
                myAppointmentsProvider((employeeId: employeeId, range: range)),
              )
              .value ??
          const [];
      return [
        for (final job in jobs)
          if (job.status != 'cancelled') job,
      ];
    });

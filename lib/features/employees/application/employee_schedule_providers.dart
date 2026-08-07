import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/utils/current_day_provider.dart';
import 'package:scheduling/features/calendar/application/appointments_providers.dart';
import 'package:scheduling/features/calendar/domain/appointment_day_slice.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/employees/application/employees_providers.dart';
import 'package:scheduling/features/employees/domain/models/emergency_contact.dart';

/// Today, as a single-day range. Keyed off `currentDayProvider` rather than
/// `DateTime.now()` so an app left open across midnight rolls over — the same
/// rule the calendar's today-circle and the off-screen mirrors follow.
final todayRangeProvider = Provider<AppointmentDateRange>((ref) {
  return AppointmentDateRange.forDay(ref.watch(currentDayProvider));
});

/// How many jobs each employee is booked for today, keyed by users-doc id.
///
/// ONE day-range listener reduced in Dart — never one query per roster row.
/// Cancelled visits don't count: the row is answering "how loaded are they",
/// and a cancelled job is not load.
///
/// Re-scoped with [runsOn] — the range stream is a 14-day superset.
///
/// `autoDispose` on purpose: a keepAlive watcher of the `autoDispose` range
/// stream is a permanent listener, so its eviction grace could never fire and
/// one visit to the Team tab pinned a live appointments snapshot for the rest
/// of the session.
final employeeJobsTodayProvider = Provider.autoDispose<Map<String, int>>((ref) {
  final range = ref.watch(todayRangeProvider);
  final jobs = ref.watch(appointmentsInRangeProvider(range)).value ?? const [];
  final counts = <String, int>{};
  for (final job in jobs) {
    if (job.status == 'cancelled') continue;
    if (!runsOn(job, range.start)) continue;
    for (final id in job.employeeIds) {
      counts[id] = (counts[id] ?? 0) + 1;
    }
  }
  return counts;
});

/// One person's emergency contact, from `users/{docId}/private/emergency`.
///
/// Autodisposed and family-keyed: it is read only while a detail surface is
/// open. Rules deny this path to everyone but an admin and the person
/// themselves, so a peer's read errors rather than returning empty — surfaces
/// must render it only when they already know the viewer is entitled, and
/// treat an error as "not shown", never as "none on file".
final emergencyContactProvider = StreamProvider.autoDispose
    .family<EmergencyContact, String>((ref, docId) {
      return ref
          .watch(employeesRepositoryProvider)
          .watchEmergencyContact(docId);
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
///
/// Filtered out of the SAME day-range listener the roster rows reduce, never a
/// second per-employee query: the Team tab already holds that stream open, so
/// opening a detail costs no extra read, and the panel can never disagree with
/// the count on the row that opened it.
final employeeTodayJobsProvider = Provider.autoDispose
    .family<List<AppointmentRecord>, String>((ref, employeeId) {
      final range = ref.watch(todayRangeProvider);
      final jobs =
          ref.watch(appointmentsInRangeProvider(range)).value ?? const [];
      final today = [
        for (final job in jobs)
          if (job.status != 'cancelled' &&
              job.employeeIds.contains(employeeId) &&
              runsOn(job, range.start))
            job,
      ];
      // Sort by THIS DAY's window start, not the stored instant. The stream
      // arrives in `orderBy('startTime')` order, so a run that began days ago
      // sorted ahead of everything — a 5-day 17:00 job listed above today's
      // 08:00 one. `notification_policy.js` sorts by the day's clock time for
      // exactly this reason; this is the Dart mirror of that rule.
      return today..sort((a, b) {
        final aStart = sliceFor(a, range.start)?.windowStart ?? a.startTime;
        final bStart = sliceFor(b, range.start)?.windowStart ?? b.startTime;
        return aStart.compareTo(bStart);
      });
    });

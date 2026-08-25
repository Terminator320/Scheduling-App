import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/features/calendar/application/appointments_providers.dart';
import 'package:scheduling/features/calendar/domain/assignee_availability.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/employees/application/employees_providers.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';

/// The span an assignee picker is asking about. A record, so the family key is
/// compared by value and two identical asks share one entry.
typedef AssigneeClashSpan = ({
  DateTime start,
  DateTime end,
  String? excludeAppointmentId,
});

/// Who can't take a job running over [AssigneeClashSpan], keyed by employee doc
/// id.
///
/// **Live where it can be, one-shot where it can't.** When the span sits inside
/// the range the calendar already holds open (`openCalendarRangeProvider`) this
/// reduces THAT stream in Dart — zero extra reads and genuinely live, the way
/// `employeeJobsTodayProvider` reduces a range it does not own. Forking a
/// second listener keyed on a span-derived range is exactly what
/// `forWeekBucketOf` and `forMirrors` carry long comments against.
///
/// The fallback is not optional. Without it, picking a date past the open range
/// makes every clash invisible and the picker silently reports everyone as
/// free — worse than not dimming at all. It is a one-shot read, so dimming
/// there re-resolves when the date or the times change rather than streaming.
///
/// Candidates are the ASSIGNABLE crew, resolved here rather than passed in: a
/// list in the family key is compared by identity, so every roster emission
/// would mint a new key. The roster stream re-runs this instead, which is free
/// on the live path and one small query on the fallback.
final assigneeAvailabilityProvider = FutureProvider.autoDispose
    .family<Map<String, AppointmentRecord>, AssigneeClashSpan>((ref, span) async {
      final employeeIds = [
        for (final e
            in ref.watch(assignableEmployeesProvider).value ??
                const <EmployeeRecord>[])
          e.id,
      ];
      if (employeeIds.isEmpty) return const {};

      final open = ref.watch(openCalendarRangeProvider);
      if (open != null && _covers(open, span)) {
        final jobs = appointmentsOrEmpty(
          ref,
          ref.watch(appointmentsInRangeProvider(open)),
          'APPT-BUSY availability range stream failed',
        );
        return clashesByAssignee(
          clashes: clashingAppointments(
            appointments: jobs,
            start: span.start,
            end: span.end,
            excludeAppointmentId: span.excludeAppointmentId,
          ),
          employeeIds: employeeIds,
        );
      }

      final repository = ref.read(appointmentsRepositoryProvider);
      final clashes = await repository.findClashingAppointments(
        employeeIds: employeeIds,
        start: span.start,
        end: span.end,
        excludeAppointmentId: span.excludeAppointmentId,
      );
      return clashesByAssignee(clashes: clashes, employeeIds: employeeIds);
    });

/// Whether [range]'s live query already covers [span].
///
/// The range query reaches back `fetchStart` — `maxAppointmentSpanDays` before
/// its start — so any job overlapping a span inside the window is already in
/// the stream; only the span's own ends have to fall within it.
bool _covers(AppointmentDateRange range, AssigneeClashSpan span) =>
    !span.start.isBefore(range.start) && !span.end.isAfter(range.end);

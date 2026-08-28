import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/features/calendar/application/appointments_providers.dart';
import 'package:scheduling/features/calendar/domain/assignee_availability.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/employees/application/employees_providers.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';

/// Value-keyed span an assignee picker is checking.
typedef AssigneeClashSpan = ({
  DateTime start,
  DateTime end,
  String? excludeAppointmentId,
});

/// Returns employee ids blocked for the checked span.
final assigneeAvailabilityProvider = FutureProvider.autoDispose
    .family<Map<String, AppointmentRecord>, AssigneeClashSpan>((
      ref,
      span,
    ) async {
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
bool _covers(AppointmentDateRange range, AssigneeClashSpan span) =>
    !span.start.isBefore(range.start) && !span.end.isAfter(range.end);

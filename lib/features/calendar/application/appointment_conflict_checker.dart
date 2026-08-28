import 'package:scheduling/features/calendar/domain/appointments_repository.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';

typedef AppointmentConflictHit = ({
  List<EmployeeRecord> busyEmployees,
  DateTime start,
  DateTime end,
});

/// Finds the first planned booking window whose assignees already have work.
Future<AppointmentConflictHit?> findFirstAppointmentConflict({
  required AppointmentsRepository repo,
  required List<EmployeeRecord> candidates,
  required Iterable<AppointmentRecord> bookings,
  Set<String> excludeAppointmentIds = const {},
  bool excludeOwnBookingIds = false,
}) async {
  if (candidates.isEmpty) return null;

  for (final booking in bookings) {
    final ownId = excludeOwnBookingIds ? booking.id : null;
    final exclusions = {
      ...excludeAppointmentIds,
      if (ownId != null) ownId,
    };
    final busy = await _findBusyEmployees(
      repo: repo,
      candidates: candidates,
      start: booking.startTime,
      end: booking.endTime,
      excludeAppointmentIds: exclusions,
    );
    if (busy.isNotEmpty) {
      return (
        busyEmployees: busy,
        start: booking.startTime,
        end: booking.endTime,
      );
    }
  }
  return null;
}

Future<List<EmployeeRecord>> _findBusyEmployees({
  required AppointmentsRepository repo,
  required List<EmployeeRecord> candidates,
  required DateTime start,
  required DateTime end,
  required Set<String> excludeAppointmentIds,
}) {
  if (excludeAppointmentIds.isEmpty) {
    return repo.findBusyEmployees(
      candidates: candidates,
      start: start,
      end: end,
    );
  }
  if (excludeAppointmentIds.length == 1) {
    return repo.findBusyEmployees(
      candidates: candidates,
      start: start,
      end: end,
      excludeAppointmentId: excludeAppointmentIds.single,
    );
  }
  return _findBusyEmployeesWithExclusions(
    repo: repo,
    candidates: candidates,
    start: start,
    end: end,
    excludeAppointmentIds: excludeAppointmentIds,
  );
}

Future<List<EmployeeRecord>> _findBusyEmployeesWithExclusions({
  required AppointmentsRepository repo,
  required List<EmployeeRecord> candidates,
  required DateTime start,
  required DateTime end,
  required Set<String> excludeAppointmentIds,
}) async {
  final candidateIds = {for (final employee in candidates) employee.id};
  final clashes = await repo.findClashingAppointments(
    employeeIds: candidateIds.toList(),
    start: start,
    end: end,
  );
  final busyIds = <String>{};
  for (final clash in clashes) {
    final id = clash.id;
    if (id != null && excludeAppointmentIds.contains(id)) continue;
    busyIds.addAll(clash.employeeIds.where((id) => candidateIds.contains(id)));
  }
  return [
    for (final employee in candidates)
      if (busyIds.contains(employee.id)) employee,
  ];
}

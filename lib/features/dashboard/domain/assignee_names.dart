import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';

/// Joins the assignee names for [appointment] using [nameMap], falling back
/// to the denormalized `employeeNames` when an assignee isn't in that
/// stream. Returns null if no name can be found at all.
String? resolveAssigneeNames(
  AppointmentRecord appointment,
  Map<String, String> nameMap,
) {
  final names = [
    for (final id in appointment.employeeIds)
      if (nameMap[id] != null) nameMap[id]!,
  ];
  if (names.isNotEmpty) return names.join(', ');
  if (appointment.employeeNames.isNotEmpty) {
    return appointment.employeeNames.join(', ');
  }
  return null;
}

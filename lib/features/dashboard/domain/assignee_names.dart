import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';

/// Comma-joined assignee names for [appointment] from [nameMap], falling back
/// to denormalized `employeeNames` when an assignee is missing from that
/// stream (null if no name is known).
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

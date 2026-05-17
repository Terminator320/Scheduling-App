import 'package:flutter/material.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';

Map<String, Color> buildEmployeeColorMap(List<EmployeeRecord> employees) {
  return {for (final e in employees) e.id: e.color};
}

Color? colorFromMap(AppointmentRecord appt, Map<String, Color> colorMap) {
  if (appt.employeeIds.length != 1) return null;
  return colorMap[appt.employeeIds.first];
}

Color? colorForAppointment(
    AppointmentRecord appt, List<EmployeeRecord> employees) {
  if (appt.employeeIds.length != 1 || employees.isEmpty) return null;
  try {
    return employees.firstWhere((e) => e.id == appt.employeeIds.first).color;
  } on StateError {
    return null;
  }
}

import 'package:flutter/material.dart';
import 'package:scheduling/features/calendar/models/appointment_record.dart';
import 'package:scheduling/features/employees/models/employee_record.dart';

Color? colorForAppointment(AppointmentRecord appt, List<EmployeeRecord> employees) {
  if (appt.employeeIds.length != 1 || employees.isEmpty) return null;
  try {
    return employees
        .firstWhere((e) => e.id == appt.employeeIds.first)
        .color;
  } catch (_) {
    return null;
  }
}
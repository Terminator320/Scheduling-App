import 'package:flutter/material.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';

Color? colorFromMap(AppointmentRecord appt, Map<String, Color> colorMap) {
  if (appt.employeeIds.length != 1) return null;
  return colorMap[appt.employeeIds.first];
}

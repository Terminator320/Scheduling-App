import 'package:flutter/painting.dart' show Color;

import 'package:scheduling/features/calendar/domain/appointment_day_slice.dart';
import 'package:scheduling/features/calendar/domain/assignee_resolver.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';

/// One assignee as an appointment surface renders them.
class AppointmentCrew {
  const AppointmentCrew({required this.name, required this.color});

  final String name;
  final Color? color;
}

/// Resolves an appointment's assignees to render-ready crew entries.
List<AppointmentCrew> crewFor(
  AppointmentRecord appointment, {
  required Map<String, Color> colorMap,
  Map<String, String>? nameMap,
}) {
  final ids = appointment.employeeIds;
  final fallbackNames = appointment.employeeNames;
  final crew = <AppointmentCrew>[];
  for (var i = 0; i < ids.length; i++) {
    final id = ids[i];
    final name = nameMap?[id] ?? assigneeNameAt(fallbackNames, i) ?? '';
    if (name.trim().isEmpty) continue;
    crew.add(AppointmentCrew(name: name, color: colorMap[id]));
  }
  return crew;
}

/// Jobs that should contribute to a day's calendar dots.
Iterable<AppointmentRecord> dottedJobsOn(
  Iterable<AppointmentRecord> dayAppointments,
) => dayAppointments.where(countsAsWork);

/// Per-day dot colors, capped at [max] jobs.
List<Color?> dayJobDotColors(
  Iterable<AppointmentRecord> dayAppointments,
  Map<String, Color> colorMap, {
  int max = 3,
}) {
  final colors = <Color?>[];
  for (final appointment in dottedJobsOn(dayAppointments)) {
    colors.add(_leadCrewColor(appointment, colorMap));
    if (colors.length == max) break;
  }
  return colors;
}

Color? _leadCrewColor(
  AppointmentRecord appointment,
  Map<String, Color> colorMap,
) {
  for (final id in appointment.employeeIds) {
    final color = colorMap[id];
    if (color != null) return color;
  }
  return null;
}

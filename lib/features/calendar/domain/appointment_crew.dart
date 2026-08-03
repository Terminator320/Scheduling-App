import 'package:flutter/painting.dart' show Color;

import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';

/// One assignee as an appointment surface renders them.
///
/// [color] is the **stored** light-theme crew colour — a widget resolves it
/// through `crewColorOf(theme, color.toARGB32())` before painting. A null
/// colour means the assignee no longer resolves to an employee record; the
/// call site substitutes a neutral.
class AppointmentCrew {
  const AppointmentCrew({required this.name, required this.color});

  final String name;
  final Color? color;
}

/// Resolves an appointment's assignees to render-ready crew entries.
///
/// [nameMap] is the live employee name map when the caller has one (the
/// calendar agenda); without it the record's denormalized [AppointmentRecord
/// .employeeNames] are matched positionally, which is what the history and
/// client surfaces use. An assignee with no resolvable name is dropped — a
/// nameless chip is noise.
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
    final name =
        nameMap?[id] ?? (i < fallbackNames.length ? fallbackNames[i] : '');
    if (name.trim().isEmpty) continue;
    crew.add(AppointmentCrew(name: name, color: colorMap[id]));
  }
  return crew;
}

/// The month grid's per-day dots: the distinct people working that day, in
/// first-appointment order, capped at [max].
///
/// Deliberately keyed on the *assignee*, not the appointment — the old
/// per-appointment dots rendered grey for any multi-crew job.
List<Color> dayCrewColors(
  Iterable<AppointmentRecord> dayAppointments,
  Map<String, Color> colorMap, {
  int max = 3,
}) {
  final seen = <String>{};
  final colors = <Color>[];
  for (final appointment in dayAppointments) {
    for (final id in appointment.employeeIds) {
      if (!seen.add(id)) continue;
      final color = colorMap[id];
      if (color == null) continue;
      colors.add(color);
      if (colors.length == max) return colors;
    }
  }
  return colors;
}

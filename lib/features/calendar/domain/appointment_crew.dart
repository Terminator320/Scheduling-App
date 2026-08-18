import 'package:flutter/painting.dart' show Color;

import 'package:scheduling/features/calendar/domain/appointment_status_values.dart';
import 'package:scheduling/features/calendar/domain/assignee_resolver.dart';
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
    final name = nameMap?[id] ?? assigneeNameAt(fallbackNames, i) ?? '';
    if (name.trim().isEmpty) continue;
    crew.add(AppointmentCrew(name: name, color: colorMap[id]));
  }
  return crew;
}

/// The jobs a day's dots stand for: everything running that day **except
/// cancelled visits** (owner call, 2026-08-17).
///
/// A cancelled job is work that is not happening, so counting it towards "how
/// busy is this day" is the one thing the dots must not say — a day whose only
/// visit was called off has to read as free at a glance, not as booked.
/// `done` still dots: that work happened, and the day was busy.
///
/// One owner, and the reason it is a function rather than a `where` at each
/// call site: [dayJobDotColors] paints the dots while `CalendarDayCell`'s
/// semantics label speaks their COUNT ("the dots are colour-only, so the count
/// carries their meaning instead"), so the two are one answer rendered twice
/// and a filter applied to only one of them makes the screen reader describe
/// dots nobody can see.
Iterable<AppointmentRecord> dottedJobsOn(
  Iterable<AppointmentRecord> dayAppointments,
) => dayAppointments.where(
  (appointment) => !isCancelledStatusRaw(appointment.status),
);

/// The month grid's per-day dots: **one per job** that day, in list order,
/// capped at [max] (owner call, 2026-08-04 — the dots read as "how busy is this
/// day", so they count jobs, not the distinct people working them).
///
/// Cancelled jobs are dropped first, through [dottedJobsOn]; the cap is applied
/// to what survives, so three live jobs still show three dots on a day that
/// also holds a cancellation.
///
/// Each entry is the job's FIRST assignee with a resolvable stored crew colour.
/// A **null** entry means that job has no such assignee; the cell paints it with
/// the same neutral an unassigned card uses, so a job is never silently dotless.
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

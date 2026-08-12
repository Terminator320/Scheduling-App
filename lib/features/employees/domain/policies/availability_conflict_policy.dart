import 'package:scheduling/features/calendar/domain/appointment_day_slice.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/calendar/domain/month_grid.dart';

/// Which weekdays a person is switching OFF while still holding booked work.
///
/// Returns **Sunday-indexed** weekday numbers (`0` = Sunday), matching
/// `workingDays` — a Monday-first answer would need a `% 7` conversion at every
/// caller, and one missed conversion shifts the whole warning by a day.
///
/// Nothing is ever auto-unassigned: this only decides what the amber note says.
/// A human moves the jobs.
///
/// Day-scoping goes through [expandToDays], the one owner — never a local
/// weekday derived from `startTime`, which would miss days 2+ of a multi-day
/// run and would not clamp a corrupt span. That is also why this takes the
/// caller's [range]: the appointments come from a range stream that is a
/// 14-day superset of its window, and `expandToDays` is what re-scopes them.
Set<int> daysWithBookedWork({
  required Iterable<AppointmentRecord> appointments,
  required AppointmentDateRange range,
  required List<bool> previousWorkingDays,
  required List<bool> nextWorkingDays,
}) {
  final turnedOff = <int>{
    for (var i = 0; i < 7; i++)
      if (_isWorking(previousWorkingDays, i) && !_isWorking(nextWorkingDays, i))
        i,
  };
  // Adding a day is never a conflict, so the common edit costs no slicing.
  if (turnedOff.isEmpty) return const {};

  final open = [
    for (final appointment in appointments)
      if (!appointment.isClosed) appointment,
  ];
  if (open.isEmpty) return const {};

  final conflicts = <int>{};
  for (final day in expandToDays(open, range).keys) {
    final index = sundayIndexOf(day);
    if (turnedOff.contains(index)) conflicts.add(index);
  }
  return conflicts;
}

/// Which weekdays a person already holds booked work on while being marked
/// unavailable for them.
///
/// The dashboard's question, where [daysWithBookedWork] answers My details':
/// that one compares a PENDING change, this one compares stored availability
/// against reality. It is the same computation with a fully-available
/// baseline — "coming from someone who works every day, which days does this
/// person's actual availability turn off while still holding work?" — so it
/// routes through the one owner rather than re-deriving the day scoping, which
/// is where a `startTime` weekday would miss days 2+ of a multi-day run.
Set<int> daysBookedOutsideAvailability({
  required Iterable<AppointmentRecord> appointments,
  required AppointmentDateRange range,
  required List<bool> workingDays,
}) => daysWithBookedWork(
  appointments: appointments,
  range: range,
  previousWorkingDays: List<bool>.filled(7, true),
  nextWorkingDays: workingDays,
);

bool _isWorking(List<bool> days, int index) =>
    index < days.length && days[index];

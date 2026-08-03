import 'package:flutter/foundation.dart' show immutable;

import 'package:scheduling/core/utils/date_utils_helper.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';

/// The longest span a job may be booked for. Guards [expandToDays] against
/// fanning a corrupt multi-year `endTime` into an unbounded number of slices.
///
/// Also the distance `AppointmentDateRange.fetchStart` reaches back past a
/// range's start, so a job that started up to this many days ago is still
/// fetched even though the query filters on `startTime` alone. The two must
/// stay equal, or a job can start before the fetch window and still overlap
/// it.
const int maxAppointmentSpanDays = 14;

/// One appointment as it appears on ONE of the days it spans.
///
/// The two stored times describe a **daily window** — 9:00 AM to 5:00 PM on
/// each of those days, not one unbroken stretch through the nights. A slice
/// carries that day's concrete window plus its position in the run.
@immutable
class AppointmentDaySlice {
  const AppointmentDaySlice({
    required this.appointment,
    required this.dayIndex,
    required this.dayCount,
    required this.windowStart,
    required this.windowEnd,
  });

  final AppointmentRecord appointment;

  /// 1-based position in the run.
  final int dayIndex;
  final int dayCount;

  /// This day's concrete window. [windowEnd] lands on the following calendar
  /// day when the window crosses midnight.
  final DateTime windowStart;
  final DateTime windowEnd;

  bool get isMultiDay => dayCount > 1;
  bool get isFirstDay => dayIndex == 1;
  bool get isLastDay => dayIndex == dayCount;

  /// The window crosses midnight, so the run counts NIGHTS, not days.
  bool get isOvernight => windowEnd.dateOnly.isAfter(windowStart.dateOnly);
}

/// True when the record's daily window crosses midnight.
///
/// A multi-day booking at the same clock time (Aug 1 09:00 → Aug 3 09:00)
/// must still read as continuous 24-hour windows on each of its days, so
/// equal start/end minutes count as overnight too — a strict `<` would
/// collapse those windows to zero length instead.
bool _isOvernightRecord(AppointmentRecord appointment) {
  final startMinutes =
      appointment.startTime.hour * 60 + appointment.startTime.minute;
  final endMinutes = appointment.endTime.hour * 60 + appointment.endTime.minute;
  return endMinutes <= startMinutes;
}

/// The last day the crew STARTS work — never the morning an overnight run
/// finishes. Keeps the count at `end - start + 1` for day jobs and night
/// shifts alike.
DateTime lastWorkDayOf(AppointmentRecord appointment) =>
    _isOvernightRecord(appointment)
    ? addCalendarDays(appointment.endTime.dateOnly, -1)
    : appointment.endTime.dateOnly;

/// How many days (or nights) the record runs for.
///
/// Can come back below 1 on a corrupt record whose `endTime` precedes its
/// `startTime` — every caller guards with `< 1` rather than trusting this is
/// always a valid count.
int _dayCountOf(AppointmentRecord appointment) =>
    calendarDaysBetween(
      appointment.startTime.dateOnly,
      lastWorkDayOf(appointment),
    ) +
    1;

/// The record as it appears on [day], or null when it doesn't run that day.
AppointmentDaySlice? sliceFor(AppointmentRecord appointment, DateTime day) {
  final count = _dayCountOf(appointment);
  if (count < 1) return null;
  final index = calendarDaysBetween(appointment.startTime.dateOnly, day) + 1;
  if (index < 1 || index > count) return null;
  return _sliceAt(appointment, day: day.dateOnly, index: index, count: count);
}

AppointmentDaySlice _sliceAt(
  AppointmentRecord appointment, {
  required DateTime day,
  required int index,
  required int count,
}) {
  final overnight = _isOvernightRecord(appointment);
  return AppointmentDaySlice(
    appointment: appointment,
    dayIndex: index,
    dayCount: count,
    windowStart: DateTime(
      day.year,
      day.month,
      day.day,
      appointment.startTime.hour,
      appointment.startTime.minute,
    ),
    windowEnd: DateTime(
      day.year,
      day.month,
      day.day + (overnight ? 1 : 0),
      appointment.endTime.hour,
      appointment.endTime.minute,
    ),
  );
}

/// Buckets [records] by the days they run, clipped to [range].
///
/// Slices are generated per WORK day — each day the daily window begins — not
/// per calendar day the stored instant span touches. That one rule is what
/// makes a night shift file under the evening it starts and show nothing on
/// the morning it ends.
///
/// A run longer than [maxAppointmentSpanDays] is clamped to that many slices
/// and its real, un-clamped length is reported through [onSpanClamped]. A
/// corrupt record whose day count comes back below 1 is dropped silently
/// instead — there is no day left for it to render on.
Map<DateTime, List<AppointmentDaySlice>> expandToDays(
  Iterable<AppointmentRecord> records,
  AppointmentDateRange range, {
  void Function(AppointmentRecord appointment, int actualDays)? onSpanClamped,
}) {
  final slicesByDay = <DateTime, List<AppointmentDaySlice>>{};
  for (final appointment in records) {
    final rawCount = _dayCountOf(appointment);
    if (rawCount < 1) continue;
    // A corrupt endTime years out must not explode the index. Clamp, but
    // report it — a silently truncated run reads as a short job.
    final count = rawCount > maxAppointmentSpanDays
        ? maxAppointmentSpanDays
        : rawCount;
    if (count != rawCount) onSpanClamped?.call(appointment, rawCount);

    final startDate = appointment.startTime.dateOnly;
    for (var i = 0; i < count; i++) {
      final day = addCalendarDays(startDate, i);
      if (day.isBefore(range.start) || !day.isBefore(range.end)) continue;
      // The CLAMPED count, not rawCount — otherwise dayIndex can never reach
      // dayCount on a clamped run and isLastDay never fires.
      (slicesByDay[day] ??= <AppointmentDaySlice>[]).add(
        _sliceAt(appointment, day: day, index: i + 1, count: count),
      );
    }
  }
  for (final slices in slicesByDay.values) {
    slices.sort(_byAllDayThenWindowStart);
  }
  return slicesByDay;
}

/// An all-day block owns the whole day, so it reads above the clock; the rest
/// run in clock order. A continuing TIMED job has a real start time today and
/// deliberately takes its place in that order rather than being pinned.
int _byAllDayThenWindowStart(AppointmentDaySlice a, AppointmentDaySlice b) {
  final aAllDay = a.appointment.isAllDay;
  final bAllDay = b.appointment.isAllDay;
  if (aAllDay != bAllDay) return aAllDay ? -1 : 1;
  return a.windowStart.compareTo(b.windowStart);
}

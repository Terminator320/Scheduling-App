import 'dart:math' as math;

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
  bool get isLastDay => dayIndex == dayCount;

  /// The window crosses midnight, so the run counts NIGHTS, not days.
  bool get isOvernight => windowEnd.dateOnly.isAfter(windowStart.dateOnly);
}

/// True when a daily window crosses midnight.
///
/// A multi-day booking at the same clock time (Aug 1 09:00 → Aug 3 09:00)
/// must still read as continuous 24-hour windows on each of its days, so
/// equal start/end minutes count as overnight too — a strict `<` would
/// collapse those windows to zero length instead.
bool _isOvernightWindow(DateTime start, DateTime end) {
  final startMinutes = start.hour * 60 + start.minute;
  final endMinutes = end.hour * 60 + end.minute;
  return endMinutes <= startMinutes;
}

/// The last day the crew STARTS work for a raw daily window — never the
/// morning an overnight run finishes.
///
/// The window form of [lastWorkDayOf], for a caller holding only a resolved
/// start/end pair and no record yet (the booking-conflict dialog, which
/// describes a job that hasn't been saved).
DateTime lastWorkDayOfWindow(DateTime start, DateTime end) =>
    _isOvernightWindow(start, end)
    ? addCalendarDays(end.dateOnly, -1)
    : end.dateOnly;

/// The last day the crew STARTS work — never the morning an overnight run
/// finishes. Keeps the count at `end - start + 1` for day jobs and night
/// shifts alike.
DateTime lastWorkDayOf(AppointmentRecord appointment) =>
    lastWorkDayOfWindow(appointment.startTime, appointment.endTime);

/// How many days (or nights) a daily [start]–[end] window runs for.
///
/// Can come back below 1 on a corrupt pair whose end precedes its start —
/// every caller guards with `< 1` rather than trusting this is a valid count.
int _dayCountOfWindow(DateTime start, DateTime end) =>
    calendarDaysBetween(start.dateOnly, lastWorkDayOfWindow(start, end)) + 1;

/// The concrete window a daily [start]–[end] pair occupies on [day].
({DateTime start, DateTime end}) _windowOn(
  DateTime day,
  DateTime start,
  DateTime end,
) {
  final overnight = _isOvernightWindow(start, end);
  return (
    start: DateTime(day.year, day.month, day.day, start.hour, start.minute),
    end: DateTime(
      day.year,
      day.month,
      day.day + (overnight ? 1 : 0),
      end.hour,
      end.minute,
    ),
  );
}

/// True when [appointment]'s daily window runs on [day].
///
/// The range streams query from `AppointmentDateRange.fetchStart` — up to
/// [maxAppointmentSpanDays] BEFORE the range's start, so that a job already
/// under way is still fetched. That makes the stream a deliberate superset of
/// the range: any surface that wants exactly one day's jobs has to re-scope,
/// and it must do it through here rather than by comparing `startTime` at the
/// call site, which silently reads a fortnight of history as "today".
bool runsOn(AppointmentRecord appointment, DateTime day) =>
    sliceFor(appointment, day) != null;

/// True when [appointment] works on at least one day in `[start, end)`.
///
/// The range sibling of [runsOn], for a surface bucketing by week or month
/// rather than by day. Testing `startTime` against the bounds instead drops a
/// run from the very week it is being worked, whenever it began earlier.
bool runsInRange(AppointmentRecord appointment, DateTime start, DateTime end) {
  final firstDay = appointment.startTime.dateOnly;
  final lastDay = lastWorkDayOf(appointment);
  // Corrupt record — end precedes start, so there is no day it runs.
  if (lastDay.isBefore(firstDay)) return false;
  return firstDay.isBefore(end) && !lastDay.isBefore(start.dateOnly);
}

/// The record as it appears on [day], or null when it doesn't run that day.
AppointmentDaySlice? sliceFor(AppointmentRecord appointment, DateTime day) {
  final count = _dayCountOfWindow(appointment.startTime, appointment.endTime);
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
  final window = _windowOn(day, appointment.startTime, appointment.endTime);
  return AppointmentDaySlice(
    appointment: appointment,
    dayIndex: index,
    dayCount: count,
    windowStart: window.start,
    windowEnd: window.end,
  );
}

/// True when two daily windows have overlapping work on at least one day both
/// of them run.
///
/// The two stored instants are a DAILY WINDOW, not one unbroken stretch, so the
/// raw instant test (`aStart < bEnd && aEnd > bStart`) is wrong for anything
/// multi-day: it reports a 9-5 run across a week as clashing with a 7 pm job
/// inside that week, when nobody is on site at 7 pm on any of those days.
bool dailyWindowsOverlap({
  required DateTime aStart,
  required DateTime aEnd,
  required DateTime bStart,
  required DateTime bEnd,
}) {
  // Every pair, not just matching day indices: an overnight window runs into
  // the FOLLOWING calendar day, so a night shift's first window can overlap a
  // job dated the next morning. Both sides are capped at
  // maxAppointmentSpanDays, so this is at most 14x14 instant comparisons.
  final bWindows = _windowsOf(bStart, bEnd);
  return _windowsOf(aStart, aEnd).any(
    (a) => bWindows.any(
      (b) => a.start.isBefore(b.end) && b.start.isBefore(a.end),
    ),
  );
}

/// Each work day's concrete window for a daily [start]–[end] pair, clamped to
/// [maxAppointmentSpanDays]. Empty for a corrupt pair whose end precedes its
/// start.
List<({DateTime start, DateTime end})> _windowsOf(
  DateTime start,
  DateTime end,
) {
  final count = _dayCountOfWindow(start, end);
  if (count < 1) return const [];
  final days = math.min(count, maxAppointmentSpanDays);
  final firstDay = start.dateOnly;
  return [
    for (var i = 0; i < days; i++)
      _windowOn(addCalendarDays(firstDay, i), start, end),
  ];
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
    final rawCount = _dayCountOfWindow(
      appointment.startTime,
      appointment.endTime,
    );
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

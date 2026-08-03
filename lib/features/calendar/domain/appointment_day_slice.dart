import 'package:flutter/foundation.dart' show immutable;

import 'package:scheduling/core/utils/date_utils_helper.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';

/// The longest span a job may be booked for. Guards [expandToDays] against
/// fanning a corrupt multi-year `endTime` into an unbounded number of slices.
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

/// Calendar days from [from] to [to]. Normalized through UTC so the two
/// DST-shift days can't make a whole-day difference come back as 23 or 25
/// hours and round to the wrong integer.
int calendarDaysBetween(DateTime from, DateTime to) => DateTime.utc(
  to.year,
  to.month,
  to.day,
).difference(DateTime.utc(from.year, from.month, from.day)).inDays;

DateTime addCalendarDays(DateTime day, int days) =>
    DateTime(day.year, day.month, day.day + days);

/// True when the record's daily window crosses midnight.
///
/// Equal times are treated as overnight, which yields a 24-hour booking —
/// the established behaviour for a zero-duration appointment.
bool isOvernightRecord(AppointmentRecord a) {
  final startMinutes = a.startTime.hour * 60 + a.startTime.minute;
  final endMinutes = a.endTime.hour * 60 + a.endTime.minute;
  return endMinutes <= startMinutes;
}

/// The last day the crew STARTS work — never the morning an overnight run
/// finishes. Keeps the count at `end - start + 1` for day jobs and night
/// shifts alike.
DateTime lastWorkDayOf(AppointmentRecord a) => isOvernightRecord(a)
    ? addCalendarDays(a.endTime.dateOnly, -1)
    : a.endTime.dateOnly;

/// How many days (or nights) the record runs for. At least 1.
int dayCountOf(AppointmentRecord a) =>
    calendarDaysBetween(a.startTime.dateOnly, lastWorkDayOf(a)) + 1;

/// The record as it appears on [day], or null when it doesn't run that day.
AppointmentDaySlice? sliceFor(AppointmentRecord a, DateTime day) {
  final count = dayCountOf(a);
  if (count < 1) return null;
  final index = calendarDaysBetween(a.startTime.dateOnly, day) + 1;
  if (index < 1 || index > count) return null;
  return _sliceAt(a, day: day.dateOnly, index: index, count: count);
}

AppointmentDaySlice _sliceAt(
  AppointmentRecord a, {
  required DateTime day,
  required int index,
  required int count,
}) {
  final overnight = isOvernightRecord(a);
  return AppointmentDaySlice(
    appointment: a,
    dayIndex: index,
    dayCount: count,
    windowStart: DateTime(
      day.year,
      day.month,
      day.day,
      a.startTime.hour,
      a.startTime.minute,
    ),
    windowEnd: DateTime(
      day.year,
      day.month,
      day.day + (overnight ? 1 : 0),
      a.endTime.hour,
      a.endTime.minute,
    ),
  );
}

/// Buckets [records] by the days they run, clipped to [range].
///
/// Slices are generated per WORK day — each day the daily window begins — not
/// per calendar day the stored instant span touches. That one rule is what
/// makes a night shift file under the evening it starts and show nothing on
/// the morning it ends.
Map<DateTime, List<AppointmentDaySlice>> expandToDays(
  Iterable<AppointmentRecord> records,
  AppointmentDateRange range, {
  void Function(AppointmentRecord record, int days)? onSpanClamped,
}) {
  final index = <DateTime, List<AppointmentDaySlice>>{};
  for (final a in records) {
    final rawCount = dayCountOf(a);
    if (rawCount < 1) continue;
    // A corrupt endTime years out must not explode the index. Clamp, but
    // report it — a silently truncated run reads as a short job.
    final count = rawCount > maxAppointmentSpanDays
        ? maxAppointmentSpanDays
        : rawCount;
    if (count != rawCount) onSpanClamped?.call(a, rawCount);

    final startDate = a.startTime.dateOnly;
    for (var i = 0; i < count; i++) {
      final day = addCalendarDays(startDate, i);
      if (day.isBefore(range.start) || !day.isBefore(range.end)) continue;
      (index[day] ??= <AppointmentDaySlice>[]).add(
        _sliceAt(a, day: day, index: i + 1, count: rawCount),
      );
    }
  }
  for (final slices in index.values) {
    slices.sort(_byAllDayThenWindowStart);
  }
  return index;
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

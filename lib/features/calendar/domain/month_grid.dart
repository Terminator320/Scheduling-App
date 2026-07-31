import 'package:intl/intl.dart';

/// The most rows any month can need: 6 lead cells + 31 days spills into a
/// sixth week (August 2026 is the case — 31 days starting Saturday). Used to
/// bound layout, never to pad a shorter month with an empty trailing week.
const int monthGridMaxRows = 6;

/// Dart's [DateTime.weekday] is Monday=1..Sunday=7; the grid works in
/// Sunday=0..Saturday=6, matching intl's weekday-symbol arrays.
int _sundayBased(DateTime day) => day.weekday % 7;

int _leadFor(DateTime month, int weekStart) =>
    (_sundayBased(DateTime(month.year, month.month)) - weekStart + 7) % 7;

/// Days in [month]. `day 0` of the next month is the last day of this one.
int _daysInMonth(DateTime month) =>
    DateTime(month.year, month.month + 1, 0).day;

/// Weeks [month] actually occupies at [weekStart] — 4, 5, or 6. The grid renders
/// exactly these; a fixed 6 would trail an all-off-month week, and a fixed 5
/// would drop the end of months like August 2026.
int monthGridRowCount(DateTime month, {required int weekStart}) =>
    ((_leadFor(month, weekStart) + _daysInMonth(month)) / 7).ceil();

/// The days the grid renders for [month], starting at [weekStart]
/// (0 = Sunday … 6 = Saturday). Length is a multiple of 7 —
/// `7 * monthGridRowCount(...)`.
///
/// Built with `DateTime(y, m, d + i)` rather than `add(Duration(days: 1))` so a
/// DST transition can't shift a cell onto the wrong calendar day.
List<DateTime> monthGridDays(DateTime month, {required int weekStart}) {
  final lead = _leadFor(month, weekStart);
  final cells = 7 * monthGridRowCount(month, weekStart: weekStart);
  return [
    for (var i = 0; i < cells; i++)
      DateTime(month.year, month.month, 1 - lead + i),
  ];
}

/// The seven days of [day]'s week, starting at [weekStart].
List<DateTime> weekOf(DateTime day, {required int weekStart}) {
  final lead = (_sundayBased(day) - weekStart + 7) % 7;
  return [
    for (var i = 0; i < 7; i++)
      DateTime(day.year, day.month, day.day - lead + i),
  ];
}

/// The locale's first day of the week as a Sunday-based index.
///
/// intl stores `FIRSTDAYOFWEEK` Monday-based (0 = Monday), so Sunday-first
/// locales report 6.
int weekStartForLocale(String locale) {
  final symbols = DateFormat.yMMMM(locale).dateSymbols;
  return (symbols.FIRSTDAYOFWEEK + 1) % 7;
}

/// Narrow weekday labels ordered from the locale's first day. Never hardcode
/// `S M T W T F S` — it is wrong for fr_CA.
List<String> weekdayLabelsForLocale(String locale) {
  final symbols = DateFormat.yMMMM(locale).dateSymbols;
  final start = weekStartForLocale(locale);
  // NARROWWEEKDAYS is Sunday-indexed.
  return [for (var i = 0; i < 7; i++) symbols.NARROWWEEKDAYS[(start + i) % 7]];
}

bool isSameDate(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// True when [day] belongs to the month the grid is rendering.
bool isInMonth(DateTime day, DateTime month) =>
    day.year == month.year && day.month == month.month;

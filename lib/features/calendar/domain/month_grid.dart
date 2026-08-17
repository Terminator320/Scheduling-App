import 'package:intl/intl.dart';

/// The most rows any month can need: 6 lead cells + 31 days spills into a
/// sixth week (August 2026 is the case — 31 days starting Saturday). Used to
/// bound layout, never to pad a shorter month with an empty trailing week.
const int monthGridMaxRows = 6;

/// Dart's [DateTime.weekday] is Monday=1..Sunday=7; the grid works in
/// Sunday=0..Saturday=6, matching intl's weekday-symbol arrays — and the same
/// indexing `workingDays` is stored in.
///
/// Public because every surface that reads a Sunday-indexed list needs it, and
/// CLAUDE.md's stated hazard is that "one missed conversion shifts a whole
/// roster by a day". It had four spellings before; don't add a fifth.
int sundayIndexOf(DateTime day) => day.weekday % 7;

int _leadFor(DateTime month, int weekStart) =>
    (sundayIndexOf(DateTime(month.year, month.month)) - weekStart + 7) % 7;

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
  // Same count monthGridRowCount gives, reusing the lead already in hand.
  final cells = 7 * ((lead + _daysInMonth(month)) / 7).ceil();
  return [
    for (var i = 0; i < cells; i++)
      DateTime(month.year, month.month, 1 - lead + i),
  ];
}

/// The seven days of [day]'s week, starting at [weekStart].
List<DateTime> weekOf(DateTime day, {required int weekStart}) {
  final lead = (sundayIndexOf(day) - weekStart + 7) % 7;
  return [
    for (var i = 0; i < 7; i++)
      DateTime(day.year, day.month, day.day - lead + i),
  ];
}

/// Cached per locale: resolving the week start builds a `DateFormat` just to
/// read its symbols, and the grid, the pager and the week strip each ask for it
/// on every calendar rebuild. The app ships two locales.
final _weekStartCache = <String, int>{};

/// The locale's first day of the week as a Sunday-based index.
///
/// intl stores `FIRSTDAYOFWEEK` Monday-based (0 = Monday), so Sunday-first
/// locales report 6.
int weekStartForLocale(String locale) => _weekStartCache.putIfAbsent(
  locale,
  () => (_symbolsFormat(locale).dateSymbols.FIRSTDAYOFWEEK + 1) % 7,
);

/// Memoized per locale, for the same reason [_weekStartCache] is: constructing
/// a `DateFormat` verifies the locale and parses a skeleton into pattern
/// fields, and every one of these runs inside a per-cell build.
final _symbolsCache = <String, DateFormat>{};
final _longDateCache = <String, DateFormat>{};
final _weekdayAbbrevCache = <String, DateFormat>{};
final _monthAbbrevCache = <String, DateFormat>{};

DateFormat _symbolsFormat(String locale) =>
    _symbolsCache.putIfAbsent(locale, () => DateFormat.yMMMM(locale));

/// "Wednesday, July 8, 2026" — the calendar cells' semantics label.
///
/// Built once per locale, NOT once per cell: a month grid renders 28-31 in-month
/// cells and the pager keeps cached neighbours, so an unmemoized call cost
/// 30-90 constructions on every day tap, month swipe and stream emission.
DateFormat longDateFormatFor(String locale) =>
    _longDateCache.putIfAbsent(locale, () => DateFormat.yMMMMEEEEd(locale));

/// "Wed" — the collapsed week strip's column heading, and the History date
/// rail's top line.
DateFormat weekdayAbbrevFormatFor(String locale) =>
    _weekdayAbbrevCache.putIfAbsent(locale, () => DateFormat.E(locale));

/// "August 2026" — History's sticky month bar.
///
/// The same skeleton [_symbolsFormat] already builds per locale, exposed rather
/// than constructed a second time.
DateFormat monthYearFormatFor(String locale) => _symbolsFormat(locale);

/// "Aug" — the History date rail's top line in search mode, where results are
/// not a contiguous run of days and a bare weekday says nothing.
DateFormat monthAbbrevFormatFor(String locale) =>
    _monthAbbrevCache.putIfAbsent(locale, () => DateFormat.MMM(locale));

/// Narrow weekday labels ordered from the locale's first day. Never hardcode
/// `S M T W T F S` — it is wrong for fr_CA.
List<String> weekdayLabelsForLocale(String locale) {
  final symbols = _symbolsFormat(locale).dateSymbols;
  final start = weekStartForLocale(locale);
  // NARROWWEEKDAYS is Sunday-indexed.
  return [for (var i = 0; i < 7; i++) symbols.NARROWWEEKDAYS[(start + i) % 7]];
}

/// Abbreviated weekday labels, Sunday-indexed (NOT rotated — callers that need
/// display order rotate themselves). The narrow twin above is right for a
/// seven-cell grid; this one is for prose, where "M, W, F" is unreadable.
List<String> weekdayAbbreviationsForLocale(String locale) {
  final symbols = _symbolsFormat(locale).dateSymbols;
  return [for (var i = 0; i < 7; i++) symbols.SHORTWEEKDAYS[i]];
}

bool isSameDate(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// True when [day] belongs to the month the grid is rendering.
bool isInMonth(DateTime day, DateTime month) =>
    day.year == month.year && day.month == month.month;

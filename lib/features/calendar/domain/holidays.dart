/// Québec statutory holidays, the Greek Orthodox Easter days, and the CCQ
/// construction shutdown — all COMPUTED, never stored or fetched.
///
/// Every entry is a fixed date, an nth-weekday rule, or Easter-derived, so
/// this is pure arithmetic with no dataset, no network call and no yearly
/// maintenance. A bundled table was rejected deliberately: whatever range it
/// covered, the calendar would stop marking holidays the year after with no
/// error and no bug report.
///
/// Design decisions live in `docs/plans/2026-08-29-calendar-holidays.md`.
library;

import 'package:scheduling/core/utils/date_utils_helper.dart';
import 'package:scheduling/l10n/l10n.dart';

/// Which calendar a day belongs to.
///
/// **Declaration order IS the marker precedence** — see [markerSetOn]. The two
/// Easters land on the same date roughly one year in three (2028, 2031, 2034),
/// so a day really can belong to two sets, and the statutory one wins because
/// it is the legally binding one.
enum HolidaySet { statutory, orthodox, construction }

/// The holidays this app knows. A member is the l10n key's identity, so
/// renaming one is a breaking change for the ARB lookup.
enum HolidayName {
  newYear,
  goodFriday,
  easterMonday,
  orthodoxGoodFriday,
  orthodoxEaster,
  orthodoxEasterMonday,
  patriotes,
  nationalHoliday,
  canadaDay,
  constructionHoliday,
  labourDay,
  thanksgiving,
  christmas,
}

/// One holiday on one day. The construction shutdown is emitted as 14 of
/// these rather than a range, so every consumer sees a uniform per-day list.
class Holiday {
  const Holiday(this.date, this.name, this.set);

  /// Midnight local, matching what the calendar surfaces hand in.
  final DateTime date;
  final HolidayName name;
  final HolidaySet set;
}

/// Western (Gregorian) Easter Sunday — the anonymous Gregorian computus.
DateTime gregorianEaster(int year) {
  final a = year % 19;
  final b = year ~/ 100;
  final c = year % 100;
  final d = b ~/ 4;
  final e = b % 4;
  final f = (b + 8) ~/ 25;
  final g = (b - f + 1) ~/ 3;
  final h = (19 * a + b - d - g + 15) % 30;
  final i = c ~/ 4;
  final k = c % 4;
  final l = (32 + 2 * e + 2 * i - h - k) % 7;
  final m = (a + 11 * h + 22 * l) ~/ 451;
  final n = h + l - 7 * m + 114;
  return DateTime(year, n ~/ 31, (n % 31) + 1);
}

/// Orthodox (Julian) Pascha, converted to the Gregorian calendar.
///
/// The offset is 13 days for 1900–2099 and 14 from 2100; deriving it rather
/// than hard-coding 13 is what stops this silently drifting by a day in the
/// next century.
DateTime orthodoxEaster(int year) {
  final a = year % 4;
  final b = year % 7;
  final c = year % 19;
  final d = (19 * c + 15) % 30;
  final e = (2 * a + 4 * b - d + 34) % 7;
  final n = d + e + 114;
  final offset = year ~/ 100 - year ~/ 400 - 2;
  // Calendar arithmetic, never `add(Duration(days:))` — the latter lands an
  // hour off real midnight on the two DST-shift days.
  return DateTime(year, n ~/ 31, (n % 31) + 1 + offset);
}

/// The first day of the CCQ construction shutdown: the Sunday **preceding**
/// July's last Saturday. The run is 14 days from here.
///
/// This is NOT "the Sunday after the third Saturday of July", the formulation
/// most summary sites repeat. That one is right for 2024–2026 and wrong for
/// 2022 and 2023 — exactly the shape of rule that looks verified when you
/// spot-check the current year. Pinned against published CCQ dates in
/// `holidays_test.dart`.
DateTime constructionHolidayStart(int year) {
  final julyEnd = DateTime(year, DateTime.july, 31);
  final backToSaturday = (julyEnd.weekday - DateTime.saturday + 7) % 7;
  return DateTime(year, DateTime.july, 31 - backToSaturday - 6);
}

/// Every holiday in [year], unordered by date.
///
/// Uncached on purpose, because nothing asks it per cell: the calendar's hot
/// path is [holidaysOn], and the memo that matters is the per-year date index
/// behind it — the same hazard `longDateFormatFor` exists to avoid in
/// `month_grid.dart`. `_indexFor` calls this once per year.
List<Holiday> holidaysForYear(int year) => _buildYear(year);

/// The holidays landing on [day], ignoring its time of day.
///
/// Returns a LIST, not a single value: on a coincidence year one day carries
/// both Good Fridays, and picking the first match would make the answer depend
/// on the order the sets happen to be built in.
///
/// The year is resolved from [day] itself, so an off-month cell showing next
/// January from the December grid still answers correctly.
List<Holiday> holidaysOn(DateTime day) {
  final date = day.dateOnly;
  return _indexFor(date.year)[date] ?? const [];
}

/// The set whose colour the day's marker takes, or null when [day] is ordinary.
///
/// [HolidaySet]'s declaration order is the precedence, so statutory wins a
/// shared day.
HolidaySet? markerSetOn(DateTime day) => markerSetFrom(holidaysOn(day));

/// [markerSetOn] over an already-resolved list.
///
/// The month grid needs the holidays for the semantics label anyway, so it
/// looks them up once and reduces here rather than asking twice per cell.
HolidaySet? markerSetFrom(List<Holiday> holidays) {
  HolidaySet? winner;
  for (final holiday in holidays) {
    if (winner == null || holiday.set.index < winner.index) winner = holiday.set;
  }
  return winner;
}

// ---------------------------------------------------------------------------

final _indexCache = <int, Map<DateTime, List<Holiday>>>{};

Map<DateTime, List<Holiday>> _indexFor(int year) =>
    _indexCache.putIfAbsent(year, () {
      final byDate = <DateTime, List<Holiday>>{};
      for (final holiday in holidaysForYear(year)) {
        byDate.putIfAbsent(holiday.date, () => []).add(holiday);
      }
      return byDate;
    });

List<Holiday> _buildYear(int year) {
  final gregorian = gregorianEaster(year);
  final orthodox = orthodoxEaster(year);
  final shutdown = constructionHolidayStart(year);

  return [
    Holiday(DateTime(year), HolidayName.newYear, HolidaySet.statutory),
    Holiday(
      addCalendarDays(gregorian, -2),
      HolidayName.goodFriday,
      HolidaySet.statutory,
    ),
    Holiday(
      addCalendarDays(gregorian, 1),
      HolidayName.easterMonday,
      HolidaySet.statutory,
    ),
    Holiday(
      addCalendarDays(orthodox, -2),
      HolidayName.orthodoxGoodFriday,
      HolidaySet.orthodox,
    ),
    Holiday(orthodox, HolidayName.orthodoxEaster, HolidaySet.orthodox),
    Holiday(
      addCalendarDays(orthodox, 1),
      HolidayName.orthodoxEasterMonday,
      HolidaySet.orthodox,
    ),
    Holiday(_patriotes(year), HolidayName.patriotes, HolidaySet.statutory),
    Holiday(
      _nationalHoliday(year),
      HolidayName.nationalHoliday,
      HolidaySet.statutory,
    ),
    Holiday(_canadaDay(year), HolidayName.canadaDay, HolidaySet.statutory),
    for (var i = 0; i < 14; i++)
      Holiday(
        addCalendarDays(shutdown, i),
        HolidayName.constructionHoliday,
        HolidaySet.construction,
      ),
    Holiday(
      _nthWeekday(year, DateTime.september, DateTime.monday, 1),
      HolidayName.labourDay,
      HolidaySet.statutory,
    ),
    Holiday(
      _nthWeekday(year, DateTime.october, DateTime.monday, 2),
      HolidayName.thanksgiving,
      HolidaySet.statutory,
    ),
    Holiday(
      DateTime(year, 12, 25),
      HolidayName.christmas,
      HolidaySet.statutory,
    ),
  ];
}

/// Journée nationale des patriotes: the Monday **strictly before** May 25.
///
/// The "strictly" is the whole rule. When May 25 is itself a Monday — 2026 is
/// the next one — an "on or before" reading gives the 25th, which is wrong,
/// and it is right in the six years out of seven you would spot-check.
DateTime _patriotes(int year) {
  final may25 = DateTime(year, DateTime.may, 25);
  final back = (may25.weekday - DateTime.monday + 7) % 7;
  return DateTime(year, DateTime.may, 25 - (back == 0 ? 7 : back));
}

/// Fête nationale, moved to June 25 when June 24 is a Sunday.
///
/// The SAME shape as [_canadaDay] below, and deliberately so: the Loi sur la
/// fête nationale (art. 3) carries the identical Sunday rule the LNT gives
/// July 1, and this app marks the day that is actually taken off, not the
/// nominal date. Implementing one and not the other gave two different answers
/// to the same question in a single year — 2029, when June 24 and July 1 are
/// BOTH Sundays, marked Canada Day on the 2nd and left Saint-Jean on the 24th.
DateTime _nationalHoliday(int year) {
  final june24 = DateTime(year, DateTime.june, 24);
  return june24.weekday == DateTime.sunday
      ? DateTime(year, DateTime.june, 25)
      : june24;
}

/// Fête du Canada, which the LNT moves to July 2 when July 1 is a Sunday.
DateTime _canadaDay(int year) {
  final july1 = DateTime(year, DateTime.july);
  return july1.weekday == DateTime.sunday
      ? DateTime(year, DateTime.july, 2)
      : july1;
}

DateTime _nthWeekday(int year, int month, int weekday, int n) {
  final first = DateTime(year, month);
  final delta = (weekday - first.weekday + 7) % 7;
  return DateTime(year, month, 1 + delta + (n - 1) * 7);
}

/// The holiday's display name in the reader's locale.
///
/// Mirrors `jobTemplateLabel` / `statusLabel`: a new [HolidayName] member forces
/// a case here and a key in both ARBs.
String holidayLabel(AppLocalizations l10n, HolidayName name) => switch (name) {
  HolidayName.newYear => l10n.calendar_holidayNewYear,
  HolidayName.goodFriday => l10n.calendar_holidayGoodFriday,
  HolidayName.easterMonday => l10n.calendar_holidayEasterMonday,
  HolidayName.orthodoxGoodFriday => l10n.calendar_holidayOrthodoxGoodFriday,
  HolidayName.orthodoxEaster => l10n.calendar_holidayOrthodoxEaster,
  HolidayName.orthodoxEasterMonday => l10n.calendar_holidayOrthodoxEasterMonday,
  HolidayName.patriotes => l10n.calendar_holidayPatriotes,
  HolidayName.nationalHoliday => l10n.calendar_holidayNationalHoliday,
  HolidayName.canadaDay => l10n.calendar_holidayCanadaDay,
  HolidayName.constructionHoliday => l10n.calendar_holidayConstruction,
  HolidayName.labourDay => l10n.calendar_holidayLabourDay,
  HolidayName.thanksgiving => l10n.calendar_holidayThanksgiving,
  HolidayName.christmas => l10n.calendar_holidayChristmas,
};

/// The caption under the name in the agenda row, or null when the headline
/// already says everything.
///
/// The construction shutdown deliberately has NONE (owner call, 2026-08-29):
/// "Construction holiday" needs no gloss, and an earlier
/// `CCQ shutdown · day 4 of 14` progress line was cut.
String? holidaySetCaption(AppLocalizations l10n, HolidaySet set) =>
    switch (set) {
      HolidaySet.statutory => l10n.calendar_holidaySetStatutory,
      HolidaySet.orthodox => l10n.calendar_holidaySetOrthodox,
      HolidaySet.construction => null,
    };

/// The agenda row's mono all-caps tag.
///
/// This is where "statutory vs observance" actually lives — the grid marker
/// carries only a hue, and on a SELECTED day it is white, so the tag is the
/// one place a reader can tell the two apart in words.
String holidaySetTag(AppLocalizations l10n, HolidaySet set) => switch (set) {
  HolidaySet.statutory ||
  HolidaySet.construction => l10n.calendar_holidayTag,
  HolidaySet.orthodox => l10n.calendar_holidayTagObservance,
};

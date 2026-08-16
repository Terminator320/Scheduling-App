// Narrowed deliberately: nothing here shows UI. `showMaxJobsPicker` and
// `joinWeekdayNames` moved to `../../widgets/fields/work_schedule_pickers.dart`
// — this was the only domain file in the repo that pushed a route, and the
// precedent that would have landed the next `show*Picker` here too.
import 'package:flutter/material.dart' show TimeOfDay, immutable;

import 'package:scheduling/l10n/l10n.dart';

/// Working days are **Sunday-indexed** (`[0]` = Sunday) to match
/// `weekStartForLocale` and `weekdayLabelsForLocale`, which both read
/// intl's Sunday-indexed `NARROWWEEKDAYS`. Storing Monday-first would put a
/// `% 7` conversion at every read and write, and one missed conversion shifts a
/// whole roster's availability by a day.
const List<bool> kDefaultWorkingDays = [
  false,
  true,
  true,
  true,
  true,
  true,
  false,
];

/// 8:00 and 17:00, as minutes from midnight.
const int kDefaultWorkStartMinutes = 480;
const int kDefaultWorkEndMinutes = 1020;

/// A working-day cell in the locale's display order, carrying the storage index
/// it writes back to so the widget never re-derives it.
@immutable
class WorkingDayCell {
  const WorkingDayCell({required this.storedIndex, required this.isWorking});

  final int storedIndex;
  final bool isWorking;
}

TimeOfDay minutesToTimeOfDay(int minutes) {
  final clamped = minutes.clamp(0, 1439);
  return TimeOfDay(hour: clamped ~/ 60, minute: clamped % 60);
}

int timeOfDayToMinutes(TimeOfDay time) => time.hour * 60 + time.minute;

/// Coerces a stored value of any shape into exactly seven flags. A legacy doc
/// has no field at all, and a hand-edited one could hold any length.
List<bool> normalizeWorkingDays(List<bool> stored) {
  if (stored.isEmpty) return kDefaultWorkingDays;
  return [for (var i = 0; i < 7; i++) i < stored.length && stored[i]];
}

/// Rotates the Sunday-indexed flags into the locale's display order.
/// [weekStart] is the Sunday-based index from `weekStartForLocale`.
List<WorkingDayCell> orderedWorkingDays(
  List<bool> workingDays, {
  required int weekStart,
}) {
  final days = normalizeWorkingDays(workingDays);
  return [
    for (var i = 0; i < 7; i++)
      WorkingDayCell(
        storedIndex: (weekStart + i) % 7,
        isWorking: days[(weekStart + i) % 7],
      ),
  ];
}

/// The working week as a phrase — "Mon – Fri", "Mon, Wed, Fri", "Every day",
/// or the no-days fallback. This is what the read-only detail page renders;
/// the seven-cell grid belongs to the edit sheet, where tapping a day is the
/// point.
///
/// Contiguity is judged in the locale's DISPLAY order, so a Monday-first
/// locale reads a Mon–Fri week as one run. Known and accepted quirk: a Sat+Sun
/// worker reads "Sat – Sun" in a Monday-first locale (the two days are
/// adjacent there) and "Sun, Sat" in a Sunday-first one, where they sit at
/// opposite ends. Both are truthful; neither is worth a special case.
///
/// [labels] is Sunday-indexed like the flags — pass
/// `weekdayAbbreviationsForLocale`, NOT the narrow single letters the grid
/// uses ("M, W, F" is unreadable as prose).
String formatWorkingDays(
  AppLocalizations l10n,
  List<bool> workingDays, {
  required int weekStart,
  required List<String> labels,
}) {
  final cells = orderedWorkingDays(workingDays, weekStart: weekStart);
  final working = [
    for (final cell in cells)
      if (cell.isWorking) cell.storedIndex,
  ];

  if (working.isEmpty) return l10n.employees_noWorkingDays;
  if (working.length == 7) return l10n.employees_everyDay;

  // Contiguous in DISPLAY order means every working cell sits in one
  // uninterrupted block of the rotated sequence.
  final firstOn = cells.indexWhere((cell) => cell.isWorking);
  final lastOn = cells.lastIndexWhere((cell) => cell.isWorking);
  final isRun = lastOn - firstOn + 1 == working.length;

  if (isRun) {
    if (working.length == 1) return labels[working.first];
    return '${labels[cells[firstOn].storedIndex]} – '
        '${labels[cells[lastOn].storedIndex]}';
  }
  return [for (final index in working) labels[index]].join(', ');
}

/// The daily cap options: no cap, then 1–12, which covers any real crew day.
const List<int> kMaxJobsOptions = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12];

/// The daily cap as a label — 0 reads as "No cap", anything else as the number.
///
/// The picker's own rows, the admin Team sheet's row and My details' row all
/// state the same value, so the mapping has one owner. Only the option list was
/// extracted here originally; the ternary stayed hand-copied at three sites.
String maxJobsLabel(AppLocalizations l10n, int value) =>
    value == 0 ? l10n.employees_noCap : '$value';

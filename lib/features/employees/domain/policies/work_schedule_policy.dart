import 'package:flutter/material.dart';

import 'package:scheduling/core/adaptive/adaptive_action_sheet.dart';
import 'package:scheduling/features/calendar/domain/month_grid.dart';
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

/// Names a set of STORED (Sunday-indexed) day numbers as prose: "Sun, Wed".
///
/// It resolves the labels itself precisely so the unrotated rule has one owner:
/// `weekdayAbbreviationsForLocale` is Sunday-indexed like [days], and handing a
/// display-ordered list to a caller that indexes by stored number silently
/// names the wrong day. Used by both surfaces that report availability
/// conflicts — the dashboard's Attention list and My details.
String joinWeekdayNames(BuildContext context, Set<int> days) {
  final labels = weekdayAbbreviationsForLocale(
    Localizations.localeOf(context).toString(),
  );
  final sorted = days.toList()..sort();
  return [for (final day in sorted) labels[day]].join(', ');
}

/// The daily cap options: no cap, then 1–12, which covers any real crew day.
const List<int> kMaxJobsOptions = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12];

/// The one daily-cap picker, shared by the admin Team sheet and My details.
///
/// Both offer the same field, so the option list and the `noCap` label rule
/// have one owner — a hand-mirrored copy let a change to either land on one
/// screen only. Resolves to null when the sheet was dismissed.
Future<int?> showMaxJobsPicker(BuildContext context) {
  final l10n = context.l10n;
  return showAdaptiveActionSheet<int>(
    context,
    title: l10n.employees_maxJobsPerDay,
    actions: [
      for (final option in kMaxJobsOptions)
        AdaptiveSheetAction(
          label: option == 0 ? l10n.employees_noCap : '$option',
          value: option,
        ),
    ],
  );
}

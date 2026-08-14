import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/features/calendar/domain/month_grid.dart';
import 'package:scheduling/l10n/l10n.dart';

/// Design metrics (`03-screens-schedule.md`). Every one of these is a 1.0-scale
/// FLOOR — the real height derives from the scaled day number.
const double _kCellMinHeight = 46;
const double _kCellGap = 2;
const double _kCircleMin = 32;
const double _kDotSize = 5;
const double _kDotGap = 3;
const double _kDotRowHeight = _kDotSize + _kDotGap;
const EdgeInsets _kGridPadding = EdgeInsets.fromLTRB(12, 10, 12, 14);

/// One month's grid, sized to the weeks that month actually occupies (4–6).
/// Stateless and provider-free: the screen supplies the per-day dot colours and
/// counts through callbacks.
class CalendarMonthGrid extends StatelessWidget {
  const CalendarMonthGrid({
    required this.month,
    required this.selectedDay,
    required this.today,
    required this.onDaySelected,
    required this.dotColorsFor,
    required this.countFor,
    super.key,
  });

  /// Any day inside the month to render.
  final DateTime month;
  final DateTime selectedDay;

  /// Today, from `currentDayProvider` — never a bare `DateTime.now()`, or the
  /// circle stays on yesterday for an app left open across midnight.
  final DateTime today;

  final ValueChanged<DateTime> onDaySelected;

  /// One STORED crew colour per job that day; the cell resolves them per theme.
  /// A null entry is a job with no colour-resolvable assignee.
  final List<Color?> Function(DateTime day) dotColorsFor;
  final int Function(DateTime day) countFor;

  static double _circleSize(BuildContext context) =>
      math.max(_kCircleMin, MediaQuery.textScalerOf(context).scale(14) * 2.1);

  static double _cellHeight(BuildContext context) => math.max(
    _kCellMinHeight,
    _circleSize(context) + _kDotRowHeight + AppSpacing.sp4,
  );

  static double _weekdayRowHeight(BuildContext context) =>
      math.max(20, MediaQuery.textScalerOf(context).scale(10) * 1.8);

  /// Total painted height for a grid of [rows] weeks, so the pager can bound
  /// its `PageView`. Rows vary by month, so callers must pass the row count of
  /// the month they are sizing — see [rowsFor].
  static double heightFor(BuildContext context, {required int rows}) =>
      _kGridPadding.vertical +
      _weekdayRowHeight(context) +
      AppSpacing.sp4 +
      rows * _cellHeight(context) +
      (rows - 1) * _kCellGap;

  /// The ambient locale's week start. The one place the grid, the pager and the
  /// week strip resolve it from a [BuildContext].
  static int weekStartOf(BuildContext context) =>
      weekStartForLocale(Localizations.localeOf(context).toString());

  /// The row count [month] needs, resolved against the ambient locale's week
  /// start. Convenience for the callers of [heightFor].
  static int rowsFor(BuildContext context, DateTime month) =>
      monthGridRowCount(month, weekStart: weekStartOf(context));

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).toString();
    final weekStart = weekStartForLocale(locale);
    final labels = weekdayLabelsForLocale(locale);
    final days = monthGridDays(month, weekStart: weekStart);
    final rows = days.length ~/ 7;
    final theme = Theme.of(context);
    final cellHeight = _cellHeight(context);
    final circleSize = _circleSize(context);

    return Padding(
      padding: _kGridPadding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: _weekdayRowHeight(context),
            child: ExcludeSemantics(
              child: Row(
                children: [
                  for (var i = 0; i < 7; i++)
                    Expanded(
                      child: Center(
                        child: Text(
                          labels[i],
                          key: ValueKey('calendar-weekday-$i'),
                          style: theme.monoType.fieldLabel.copyWith(
                            color: theme.palette.textMuted,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sp4),
          for (var row = 0; row < rows; row++) ...[
            if (row > 0) const SizedBox(height: _kCellGap),
            SizedBox(
              height: cellHeight,
              child: Row(
                children: [
                  for (var col = 0; col < 7; col++)
                    Expanded(
                      child: CalendarDayCell(
                        day: days[row * 7 + col],
                        month: month,
                        selectedDay: selectedDay,
                        today: today,
                        circleSize: circleSize,
                        dotColors: dotColorsFor(days[row * 7 + col]),
                        count: countFor(days[row * 7 + col]),
                        onTap: onDaySelected,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One day cell. The 32px circle carries the selected fill, not the cell, so
/// selection reads as a round token rather than a stretched oval.
///
/// Off-month cells render their number faintly along with their crew dots, but
/// are not tappable and are excluded from semantics: the design calls them
/// "blank, Ink 15, not tappable" while the program spec widens the fetch range
/// specifically so those trailing days are not dotless. Dots plus a faint
/// number is what satisfies both.
class CalendarDayCell extends StatelessWidget {
  const CalendarDayCell({
    required this.day,
    required this.month,
    required this.selectedDay,
    required this.today,
    required this.circleSize,
    required this.dotColors,
    required this.count,
    required this.onTap,
    super.key,
  });

  final DateTime day;
  final DateTime month;
  final DateTime selectedDay;
  final DateTime today;
  final double circleSize;

  /// One entry per job that day; null paints the unassigned neutral.
  final List<Color?> dotColors;
  final int count;
  final ValueChanged<DateTime> onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final inMonth = isInMonth(day, month);
    final isSelected = inMonth && isSameDate(day, selectedDay);
    final isToday = isSameDate(day, today);

    // Today reads as a RING around its number rather than a blue number (owner
    // call, 2026-08-14): the accent colour was also the picker/field accent, so
    // "today" and "the value you picked" spoke the same language. The ring is
    // `onSurface` — white on the dark theme, ink on the light one — so it stays
    // visible in both; a literal white would vanish on the light surface.
    // Selection still wins: a filled circle under a ring is noise.
    final showTodayRing = isToday && inMonth && !isSelected;

    final Color numberColor;
    if (!inMonth) {
      numberColor = theme.palette.textFaint;
    } else if (isSelected) {
      numberColor = scheme.onPrimary;
    } else {
      numberColor = scheme.onSurface;
    }

    final cellKey = ValueKey(
      'calendar-day-${day.year}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}',
    );

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: circleSize,
          height: circleSize,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isSelected ? scheme.primary : null,
            border: showTodayRing
                ? Border.all(color: scheme.onSurface, width: 1.5)
                : null,
          ),
          child: Text(
            '${day.day}',
            style: TextStyle(
              fontFamily: kFontSans,
              fontSize: 14,
              fontWeight: isSelected || (isToday && inMonth)
                  ? FontWeight.w700
                  : FontWeight.w500,
              color: numberColor,
            ),
          ),
        ),
        SizedBox(
          height: _kDotRowHeight,
          // Kept on the selected day too (owner call, 2026-07-31). The
          // selection circle only fills the number; the dot row sits below it
          // on the plain cell background, so the crew colours stay legible —
          // and hiding them made the day you were looking at the one day whose
          // crew you couldn't see.
          child: dotColors.isEmpty
              ? null
              : Padding(
                  padding: const EdgeInsets.only(top: _kDotGap),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final stored in dotColors)
                        Container(
                          margin: const EdgeInsets.symmetric(horizontal: 1.5),
                          width: _kDotSize,
                          height: _kDotSize,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            // Same neutral the card's crew bar uses for a job
                            // with nobody on it.
                            color: stored == null
                                ? theme.palette.textFaint
                                : crewColorOf(theme, stored.toARGB32()),
                          ),
                        ),
                    ],
                  ),
                ),
        ),
      ],
    );

    if (!inMonth) {
      return ExcludeSemantics(
        key: cellKey,
        child: Center(child: content),
      );
    }

    final dateLabel = longDateFormatFor(
      Localizations.localeOf(context).toString(),
    ).format(day);

    return Semantics(
      button: true,
      selected: isSelected,
      // The dots are colour-only, so the count carries their meaning instead.
      label: count > 0
          ? '$dateLabel, ${context.l10n.calendar_appointmentCount(count)}'
          : dateLabel,
      excludeSemantics: true,
      child: InkResponse(
        key: cellKey,
        onTap: () => onTap(DateTime(day.year, day.month, day.day)),
        radius: circleSize,
        child: Center(child: content),
      ),
    );
  }
}

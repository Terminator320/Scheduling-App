import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/features/calendar/domain/month_grid.dart';

/// Design metrics (`03-screens-schedule.md`). 1.0-scale FLOORS — the real
/// height derives from the scaled day number, exactly like the month grid.
const double _kStripCellMinHeight = 56;
const double _kStripCircleMin = 30;
const double _kStripDot = 4.5;
const double _kStripDotGap = 3;

/// The selected day's week, shown inside the fixed header once the month grid
/// collapses. One dot per day rather than the grid's three: the strip is a
/// wayfinding aid, not a density read.
class CalendarWeekStrip extends StatelessWidget {
  const CalendarWeekStrip({
    required this.weekDays,
    required this.selectedDay,
    required this.today,
    required this.onDaySelected,
    required this.dotColorFor,
    super.key,
  });

  final List<DateTime> weekDays;
  final DateTime selectedDay;

  /// Today, from `currentDayProvider` — never a bare `DateTime.now()`.
  final DateTime today;
  final ValueChanged<DateTime> onDaySelected;

  /// One STORED crew colour for the day, or null for a day with no work.
  final Color? Function(DateTime day) dotColorFor;

  static double _circleSize(BuildContext context) => math.max(
    _kStripCircleMin,
    MediaQuery.textScalerOf(context).scale(14.5) * 2,
  );

  /// Painted height including the leading gap, so the collapse can size its
  /// spacer against the grid it replaces.
  static double heightFor(BuildContext context) =>
      AppSpacing.sp8 + _bodyHeight(context);

  static double _bodyHeight(BuildContext context) => math.max(
    _kStripCellMinHeight,
    _circleSize(context) +
        MediaQuery.textScalerOf(context).scale(9.5) +
        AppSpacing.sp4 +
        _kStripDot +
        _kStripDotGap,
  );

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).toString();
    final abbrev = DateFormat.E(locale);
    final circle = _circleSize(context);

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sp8),
      child: SizedBox(
        height: _bodyHeight(context),
        child: Row(
          children: [
            for (final day in weekDays)
              Expanded(
                child: _StripCell(
                  day: day,
                  isSelected: isSameDate(day, selectedDay),
                  isToday: isSameDate(day, today),
                  label: abbrev.format(day).toUpperCase(),
                  circleSize: circle,
                  dotColor: dotColorFor(day),
                  onTap: onDaySelected,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StripCell extends StatelessWidget {
  const _StripCell({
    required this.day,
    required this.isSelected,
    required this.isToday,
    required this.label,
    required this.circleSize,
    required this.dotColor,
    required this.onTap,
  });

  final DateTime day;
  final bool isSelected;
  final bool isToday;
  final String label;
  final double circleSize;
  final Color? dotColor;
  final ValueChanged<DateTime> onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Semantics(
      button: true,
      selected: isSelected,
      label: DateFormat.yMMMMEEEEd(
        Localizations.localeOf(context).toString(),
      ).format(day),
      excludeSemantics: true,
      child: InkResponse(
        key: ValueKey(
          'calendar-strip-day-${day.year}-'
          '${day.month.toString().padLeft(2, '0')}-'
          '${day.day.toString().padLeft(2, '0')}',
        ),
        onTap: () => onTap(DateTime(day.year, day.month, day.day)),
        radius: circleSize,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              maxLines: 1,
              style: theme.monoType.micro.copyWith(
                color: theme.palette.textMuted,
              ),
            ),
            const SizedBox(height: AppSpacing.sp4),
            Container(
              width: circleSize,
              height: circleSize,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? scheme.primary : null,
              ),
              child: Text(
                '${day.day}',
                style: TextStyle(
                  fontFamily: kFontSans,
                  fontSize: 14.5,
                  fontWeight: isSelected || isToday
                      ? FontWeight.w700
                      : FontWeight.w500,
                  color: isSelected
                      ? scheme.onPrimary
                      : isToday
                      ? theme.palette.primaryAccent
                      : scheme.onSurface,
                ),
              ),
            ),
            SizedBox(
              height: _kStripDot + _kStripDotGap,
              // The selected day's filled circle already carries the state, so
              // it drops its dot — same rule as the month grid's cells.
              child: dotColor == null || isSelected
                  ? null
                  : Padding(
                      padding: const EdgeInsets.only(top: _kStripDotGap),
                      child: Container(
                        key: const ValueKey('calendar-strip-dot'),
                        width: _kStripDot,
                        height: _kStripDot,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: crewColorOf(theme, dotColor!.toARGB32()),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

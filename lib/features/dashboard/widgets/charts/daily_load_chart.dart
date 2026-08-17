import 'package:flutter/material.dart';

import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/features/calendar/domain/month_grid.dart';
import 'package:scheduling/features/dashboard/domain/dashboard_stats.dart';

/// Seven bars — Monday to Sunday of the current week — with an over-capacity
/// day painted in the error colour.
///
/// **The chart rule:** the bars live in their own fixed-height track, and the
/// value and axis labels are siblings OUTSIDE it. Labels sharing the flex
/// column silently clip tall bars, which is how a chart ends up quietly
/// under-reporting its own maximum.
class DailyLoadChart extends StatelessWidget {
  const DailyLoadChart({
    required this.days,
    required this.weekdayLabels,
    super.key,
  });

  final List<DayLoad> days;

  /// Sunday-indexed and UNROTATED — indexed by `sundayIndexOf`, the same way
  /// `workingDays` is. A display-ordered list silently mislabels every bar.
  final List<String> weekdayLabels;

  static const double _trackHeight = 72;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    var maxValue = 0;
    for (final day in days) {
      final ceiling = day.count > day.capacity ? day.count : day.capacity;
      if (ceiling > maxValue) maxValue = ceiling;
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (final day in days)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${day.count}',
                    style: theme.monoType.data.copyWith(
                      color: day.isOverCapacity
                          ? scheme.error
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sp4),
                  SizedBox(
                    height: _trackHeight,
                    child: _Bar(
                      day: day,
                      maxValue: maxValue,
                      trackHeight: _trackHeight,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sp4),
                  Text(
                    weekdayLabels[sundayIndexOf(day.day)],
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.day,
    required this.maxValue,
    required this.trackHeight,
  });

  final DayLoad day;
  final int maxValue;
  final double trackHeight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final height = maxValue == 0 ? 0.0 : trackHeight * day.count / maxValue;
    return Stack(
      alignment: Alignment.bottomCenter,
      children: [
        // The capacity line, drawn only when a capacity is actually
        // configured — `maxJobsPerDay` defaults to 0, and reading that as a
        // ceiling would paint every bar red on the rosters that never set it.
        if (day.capacity > 0 && maxValue > 0)
          Positioned(
            bottom: trackHeight * day.capacity / maxValue,
            left: 0,
            right: 0,
            child: Container(height: 1, color: scheme.outlineVariant),
          ),
        SizedBox(
          height: height,
          width: double.infinity,
          child: DecoratedBox(
            decoration: BoxDecoration(
              // Colour is never the only cue: the count above the bar turns
              // red too, and an over-capacity day is the only one whose bar
              // rises above the capacity line.
              color: day.isOverCapacity ? scheme.error : scheme.primary,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(2),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

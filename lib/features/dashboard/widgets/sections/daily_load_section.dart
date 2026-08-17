import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/features/calendar/domain/month_grid.dart';
import 'package:scheduling/features/dashboard/domain/dashboard_stats.dart';
import 'package:scheduling/features/dashboard/widgets/charts/daily_load_chart.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/primitives/section_label.dart';

/// How many jobs each day of the current week is carrying, against what the
/// available roster can take.
///
/// Its span is named in its own title, so the dashboard's period control
/// deliberately does not scope it.
class DailyLoadSection extends StatelessWidget {
  const DailyLoadSection({required this.days, super.key});

  final List<DayLoad> days;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final locale = Localizations.localeOf(context).toString();
    // One DateFormat for the whole chart, never one per bar.
    final dayNameFormat = DateFormat('EEEE', locale);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel(l10n.dashboard_jobsPerDay),
        const SizedBox(height: AppSpacing.sp8),
        Container(
          decoration: appCardDecoration(
            theme,
            color: theme.colorScheme.surface,
          ),
          padding: const EdgeInsets.all(AppSpacing.sp16),
          // The chart's own text is decorative — a screen reader gets one
          // spoken label per day instead, because an over-capacity day is
          // signalled by colour and would otherwise be silent.
          child: Semantics(
            label: [
              for (final day in days)
                [
                  l10n.dashboard_jobsPerDaySemantics(
                    dayNameFormat.format(day.day),
                    day.count,
                  ),
                  if (day.isOverCapacity) l10n.dashboard_overCapacity,
                ].join(', '),
            ].join('. '),
            child: ExcludeSemantics(
              child: DailyLoadChart(
                days: days,
                weekdayLabels: weekdayAbbreviationsForLocale(locale),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

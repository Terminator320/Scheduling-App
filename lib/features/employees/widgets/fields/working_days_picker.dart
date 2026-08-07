import 'package:flutter/material.dart';

import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/features/calendar/domain/month_grid.dart';
import 'package:scheduling/features/calendar/widgets/views/calendar_month_grid.dart';
import 'package:scheduling/features/employees/domain/policies/work_schedule_policy.dart';

/// Seven toggle cells in the locale's week order.
///
/// Stored flags are Sunday-indexed; the cells carry their own `storedIndex` so
/// the callback writes back to the right slot regardless of where the locale
/// puts the week start. A `Wrap` rather than a `Row` so the strip reflows
/// instead of overflowing at large text scales.
class WorkingDaysPicker extends StatelessWidget {
  const WorkingDaysPicker({
    required this.workingDays,
    required this.onChanged,
    super.key,
  });

  final List<bool> workingDays;
  final ValueChanged<List<bool>> onChanged;

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).toString();
    final weekStart = CalendarMonthGrid.weekStartOf(context);
    final labels = weekdayLabelsForLocale(locale);
    final cells = orderedWorkingDays(workingDays, weekStart: weekStart);

    return Wrap(
      spacing: AppSpacing.sp8,
      runSpacing: AppSpacing.sp8,
      children: [
        for (var i = 0; i < cells.length; i++)
          FilterChip(
            label: Text(labels[i]),
            selected: cells[i].isWorking,
            onSelected: (selected) {
              final next = [...normalizeWorkingDays(workingDays)];
              next[cells[i].storedIndex] = selected;
              onChanged(next);
            },
          ),
      ],
    );
  }
}

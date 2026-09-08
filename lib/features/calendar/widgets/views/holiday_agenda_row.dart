import 'package:flutter/material.dart';

import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/features/calendar/domain/holidays.dart';
import 'package:scheduling/features/calendar/widgets/cards/non_working_time_row.dart';
import 'package:scheduling/features/calendar/widgets/views/calendar_day_circle.dart';
import 'package:scheduling/l10n/l10n.dart';

/// A holiday in the day agenda, wearing the shared non-working-time chrome
/// (`non_working_time_row.dart`) that `_DayOffStrip` wears.
///
/// Reusing that vocabulary is deliberate: a statutory holiday IS non-working
/// time, so it joins a category the app already speaks rather than opening a
/// new one. The one structural difference is that a holiday belongs to nobody
/// in particular, so there is no avatar — the rail slot is reused for the set's
/// marker hue instead of a crew colour, which ties the row back to the grid
/// marker that led the reader here. That is also why this row's rail is an
/// ordinary child rather than the day off's `Positioned` one: with no avatar
/// beside it there is no intrinsic-layout hazard to dodge.
class HolidayAgendaRow extends StatelessWidget {
  const HolidayAgendaRow({required this.holiday, super.key});

  final Holiday holiday;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final caption = holidaySetCaption(l10n, holiday.set);

    // The set's own hue, not the grid's: the row is a full-strength statement
    // about the day, never faint and never whited out by selection.
    final hue = holidayHueFor(theme, holiday.set);

    return Semantics(
      label: [
        holidayLabel(l10n, holiday.name),
        ?caption,
      ].join(', '),
      excludeSemantics: true,
      child: Container(
        constraints: const BoxConstraints(minHeight: kNonWorkingRowMinHeight),
        margin: const EdgeInsets.only(bottom: AppSpacing.sp8),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.sp8,
          AppSpacing.sp8,
          AppSpacing.sp12,
          AppSpacing.sp8,
        ),
        decoration: nonWorkingTimeDecoration(theme),
        child: Row(
          children: [
            Container(
              width: kNonWorkingRailWidth,
              height: 28,
              margin: const EdgeInsets.only(right: AppSpacing.sp12),
              decoration: BoxDecoration(
                color: hue,
                borderRadius: BorderRadius.circular(AppRadius.rFull),
              ),
            ),
            Expanded(
              child: NonWorkingTimeText(
                headline: holidayLabel(l10n, holiday.name),
                caption: caption,
                // Holiday names run long — "Journée nationale des patriotes".
                headlineMaxLines: 2,
              ),
            ),
            const SizedBox(width: AppSpacing.sp8),
            Text(
              holidaySetTag(l10n, holiday.set).toUpperCase(),
              style: theme.monoType.groupLabel,
            ),
          ],
        ),
      ),
    );
  }
}

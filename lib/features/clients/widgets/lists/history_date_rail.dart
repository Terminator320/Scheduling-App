import 'package:flutter/material.dart';

import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/features/calendar/domain/month_grid.dart';

/// The date column down the left of every History row.
///
/// The design carries the date beside the card rather than in a header above
/// it, which is what leaves `AppointmentCard` untouched — it is deliberately
/// the ONE appointment card across every surface, and the two rejected layouts
/// both had to restyle it.
///
/// It is rendered on every row so the cards stay aligned, but it only SPEAKS on
/// the first row of a day (`showDate: false` leaves the column empty).
class HistoryDateRail extends StatelessWidget {
  const HistoryDateRail({
    required this.day,
    required this.showDate,
    required this.inSearch,
    required this.currentYear,
    super.key,
  });

  /// The width the rail reserves. Taken out of a 372px phone, so titles do
  /// truncate sooner than they used to — an accepted cost of B over the two
  /// layouts that would have restyled the card instead.
  static const double width = 44;

  final DateTime day;

  /// False on the second and later rows of the same day.
  final bool showDate;

  /// Search spans every appointment, so its results are not a contiguous run of
  /// days and render flat, with no month bar above them. The rail therefore has
  /// to carry the month itself — a bare `Tue 11` is ambiguous the moment the
  /// hits cross months, let alone years.
  final bool inSearch;

  /// Compared against the row's own year to decide whether the year needs
  /// saying. Comes from `currentDayProvider`, not `DateTime.now()`, so an app
  /// left open across New Year re-renders.
  final int currentYear;

  @override
  Widget build(BuildContext context) {
    if (!showDate) return const SizedBox(width: width);

    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context).toString();
    final top = inSearch
        ? monthAbbrevFormatFor(locale).format(day)
        : weekdayAbbrevFormatFor(locale).format(day);
    // Only in search, and only when the hit is not from this year: inside the
    // month-barred list the year is already overhead, and repeating it here
    // would be a third heading for the same fact.
    final showYear = inSearch && day.year != currentYear;

    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            top.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.clip,
            style: theme.monoType.micro,
          ),
          const SizedBox(height: AppSpacing.sp4),
          Text('${day.day}', style: theme.monoType.metric),
          if (showYear) ...[
            const SizedBox(height: AppSpacing.sp4),
            Text(
              '${day.year}',
              maxLines: 1,
              overflow: TextOverflow.clip,
              style: theme.monoType.micro,
            ),
          ],
        ],
      ),
    );
  }
}

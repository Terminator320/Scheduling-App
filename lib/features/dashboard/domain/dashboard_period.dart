import 'package:flutter/foundation.dart' show immutable;

import 'package:scheduling/core/utils/date_utils_helper.dart';
import 'package:scheduling/features/dashboard/domain/dashboard_aggregator.dart';

/// The span the dashboard's summary numbers are counted over.
///
/// **Three members, not four — Year is deliberately absent.** The dashboard
/// reads its settled weeks through `fetchInRange`, which is capped at 1000
/// docs; a year is ~5,100 jobs at 14/day and ~1,825 even at 5/day, so a Year
/// option would silently compute every figure over a PREFIX. That is the exact
/// failure the 2026-08-08 window split was built to end. Year needs an
/// aggregate read path, and P7b — the project that would have built one — was
/// CANCELLED by owner call 2026-09-06, so its absence is permanent rather than
/// pending. Do not add it back by widening the fetch.
///
/// Every member here fits INSIDE the window the dashboard already fetches, so
/// selecting one costs no query at all — see [windowFor].
enum DashboardPeriod {
  today,
  week,
  month;

  /// The half-open `[start, end)` this period covers.
  ///
  /// **Every period ends at the end of TODAY and differs only in how far back
  /// it starts** — these are to-date windows (week-to-date, month-to-date),
  /// not whole calendar spans. Two reasons, and both matter:
  ///
  /// 1. It is what the numbers mean. They answer "how have we done", and there
  ///    are no completed or cancelled jobs in the future — a whole-month
  ///    window would divide the same completions by a box that is mostly
  ///    unlived, and "new clients this month" would silently include none of
  ///    them.
  /// 2. It is the only shape that fits the data already on screen. The fetched
  ///    window reaches 49 days BACK but only as far FORWARD as next Monday, so
  ///    a whole-month window runs off the end of it — under-counting the rest
  ///    of the month with nothing saying so. A to-date window cannot: its
  ///    start is at most 31 days back and its end is tomorrow.
  ///
  /// That is what keeps the control a pure in-memory filter. A future period
  /// that does NOT fit must widen the history half of the range and never the
  /// live one, or it undoes the 2026-08-08 split.
  DashboardWindow windowFor(DateTime now) {
    final day = now.dateOnly;
    return DashboardWindow(
      start: switch (this) {
        DashboardPeriod.today => day,
        DashboardPeriod.week => DashboardAggregator.mondayOf(now),
        DashboardPeriod.month => DateTime(now.year, now.month),
      },
      end: DateTime(day.year, day.month, day.day + 1),
    );
  }
}

/// A resolved `[start, end)` pair.
///
/// Reducers take one of these rather than a [DashboardPeriod], so the window
/// rule has exactly one owner ([DashboardPeriod.windowFor]) instead of being
/// re-derived inside each reducer — the drift shape that bit `displayStatusAt`
/// and `_who`.
@immutable
class DashboardWindow {
  const DashboardWindow({required this.start, required this.end});

  final DateTime start;
  final DateTime end;

  @override
  bool operator ==(Object other) =>
      other is DashboardWindow && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);
}

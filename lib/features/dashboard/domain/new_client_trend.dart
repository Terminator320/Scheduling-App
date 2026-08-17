import 'package:flutter/foundation.dart' show immutable;

/// The new-clients window split in half — the recent half against the one
/// before it, which is what turns a row of bars into a sentence ("12, and
/// that's 3 more than the four weeks before").
///
/// Pure and clock-free: it reads the same weekly buckets the chart draws, so
/// the headline, the delta and the bars can never describe different windows.
@immutable
class NewClientTrend {
  const NewClientTrend({
    required this.total,
    required this.recent,
    required this.previous,
    required this.halfWeeks,
  });

  /// Every bucket in the window.
  final int total;

  /// The trailing half of the window, and the half before it.
  final int recent;
  final int previous;

  /// How many buckets each half holds — the "vs previous N weeks" figure.
  final int halfWeeks;

  int get delta => recent - previous;

  /// False when there is nothing to compare against: too few buckets, or a
  /// window with no clients at all, where "0 vs 0, no change" is noise.
  bool get hasComparison => halfWeeks > 0 && total > 0;

  /// A window with nothing in it at all — the sparkline is a flat line and is
  /// better not drawn.
  bool get isEmpty => total == 0;
}

/// Splits [weeklyCounts] (oldest first) down the middle.
///
/// An ODD bucket count drops the oldest bucket rather than making the halves
/// different sizes — comparing 4 weeks against 3 and calling the difference a
/// trend would overstate every window by a week's worth of clients.
NewClientTrend newClientTrend(List<int> weeklyCounts) {
  final total = weeklyCounts.fold(0, (sum, v) => sum + v);
  final half = weeklyCounts.length ~/ 2;
  if (half == 0) {
    return NewClientTrend(
      total: total,
      recent: total,
      previous: 0,
      halfWeeks: 0,
    );
  }
  var recent = 0;
  var previous = 0;
  for (var i = 0; i < half; i++) {
    recent += weeklyCounts[weeklyCounts.length - 1 - i];
    previous += weeklyCounts[weeklyCounts.length - 1 - half - i];
  }
  return NewClientTrend(
    total: total,
    recent: recent,
    previous: previous,
    halfWeeks: half,
  );
}

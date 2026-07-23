/// Repeat frequency; occurrences pre-booked up to [horizonMonths] ahead.
enum RepeatInterval {
  none(0),
  fourMonths(4),
  sixMonths(6),
  oneYear(12);

  const RepeatInterval(this.months);

  /// Months between occurrences; 0 means no repeat.
  final int months;

  /// Pre-booking horizon (five years).
  static const int horizonMonths = 60;

  /// Upper bound on occurrences, keeps clear of WriteBatch 500-op limit.
  static const int maxOccurrences = 120;

  /// Firestore string value. [fromRaw] is the only string→interval mapper.
  String get raw => switch (this) {
    RepeatInterval.none => 'none',
    RepeatInterval.fourMonths => 'four_months',
    RepeatInterval.sixMonths => 'six_months',
    RepeatInterval.oneYear => 'one_year',
  };

  static RepeatInterval fromRaw(String raw) =>
      switch (raw.trim().toLowerCase()) {
        'four_months' => RepeatInterval.fourMonths,
        'six_months' => RepeatInterval.sixMonths,
        'one_year' => RepeatInterval.oneYear,
        _ => RepeatInterval.none,
      };

  /// Start times of the pre-booked future occurrences (excludes [first]).
  List<DateTime> occurrenceStartsAfter(DateTime first) {
    if (this == RepeatInterval.none) return const [];
    final starts = [
      for (var m = months; m <= horizonMonths; m += months)
        _addMonthsClamped(first, m),
    ];
    assert(
      starts.length <= maxOccurrences,
      'repeat horizon produces ${starts.length} occurrences '
      '(> $maxOccurrences) — atomic series WriteBatch could exceed 500 ops',
    );
    return starts;
  }

  /// Add months, preserving time-of-day; day clamped to month length.
  static DateTime _addMonthsClamped(DateTime date, int months) {
    final zeroBased = date.month - 1 + months;
    final year = date.year + zeroBased ~/ 12;
    final month = zeroBased % 12 + 1;
    final lastDay = DateTime(year, month + 1, 0).day;
    final day = date.day <= lastDay ? date.day : lastDay;
    return DateTime(year, month, day, date.hour, date.minute);
  }
}

/// End time for repeated occurrence, preserving day-span and time-of-day (DST-safe).
DateTime occurrenceEnd({
  required DateTime originalStart,
  required DateTime originalEnd,
  required DateTime copyStart,
}) {
  // UTC midnights are DST-agnostic for accurate day-span calculation.
  final daySpan =
      DateTime.utc(
            originalEnd.year,
            originalEnd.month,
            originalEnd.day,
          )
          .difference(
            DateTime.utc(
              originalStart.year,
              originalStart.month,
              originalStart.day,
            ),
          )
          .inDays;
  return DateTime(
    copyStart.year,
    copyStart.month,
    copyStart.day + daySpan,
    originalEnd.hour,
    originalEnd.minute,
  );
}

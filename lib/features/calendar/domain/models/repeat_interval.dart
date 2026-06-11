/// How often an appointment repeats. When a repeat is selected, the future
/// occurrences are pre-booked at creation time up to [horizonMonths] ahead
/// (five years), spanning multiple years rather than the current one.
enum RepeatInterval {
  none(0),
  fourMonths(4),
  sixMonths(6),
  oneYear(12);

  const RepeatInterval(this.months);

  /// Months between occurrences; 0 means no repeat.
  final int months;

  /// Pre-booking horizon: occurrences are created up to five years out.
  static const int horizonMonths = 60;

  /// Upper bound on pre-booked occurrences. A rule rewrite books copies +
  /// deletes old futures + updates the anchor in one atomic WriteBatch (hard
  /// limit 500 ops), so 120 copies + 120 deletes + 1 stays well clear. Today's
  /// shortest interval (4 months) yields 15, but this guards a future shorter
  /// interval or longer [horizonMonths] from silently breaching the limit.
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

  /// Adds [months] keeping the time of day; the day-of-month is clamped to
  /// the target month's length (Jan 31 + 1 month → Feb 28).
  static DateTime _addMonthsClamped(DateTime date, int months) {
    final zeroBased = date.month - 1 + months;
    final year = date.year + zeroBased ~/ 12;
    final month = zeroBased % 12 + 1;
    final lastDay = DateTime(year, month + 1, 0).day;
    final day = date.day <= lastDay ? date.day : lastDay;
    return DateTime(year, month, day, date.hour, date.minute);
  }
}

/// End time for a repeated occurrence starting at [copyStart], preserving the
/// original visit's wall-clock day-span and end time-of-day. Use this instead
/// of `copyStart.add(originalEnd - originalStart)`: adding the raw elapsed
/// Duration shifts the stored end ±1h when a copy (or the original) straddles a
/// DST transition.
DateTime occurrenceEnd({
  required DateTime originalStart,
  required DateTime originalEnd,
  required DateTime copyStart,
}) {
  // UTC midnights carry no DST offset, so this is an exact calendar-day count.
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

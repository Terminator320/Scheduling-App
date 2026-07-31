import 'package:intl/intl.dart';

class DateUtilsHelper {
  // Cached per locale since DateFormat parses locale symbols on construction.
  static final Map<String, DateFormat> _timeFormats = {};
  static final Map<String, DateFormat> _dateFormats = {};
  static final Map<String, DateFormat> _dayHeaderFormats = {};
  static final Map<String, DateFormat> _whenLineFormats = {};

  static String get _locale => Intl.defaultLocale ?? 'en_CA';

  static String formatTime(DateTime date) {
    final format = _timeFormats.putIfAbsent(
      _locale,
      () => DateFormat.jm(_locale),
    );
    return format.format(date);
  }

  static String formatDate(DateTime date) {
    final format = _dateFormats.putIfAbsent(
      _locale,
      () => DateFormat.yMMMd(_locale),
    );
    return format.format(date);
  }

  /// "Tuesday, June 23" day header — the history day groups and the calendar
  /// agenda both render it.
  static String formatDayHeader(DateTime date) {
    final format = _dayHeaderFormats.putIfAbsent(
      _locale,
      () => DateFormat('EEEE, MMMM d', _locale),
    );
    return format.format(date);
  }

  /// The detail sheet's mono when-line: `TUE 4 AUG · 10:30 – 12:00`.
  /// Uppercased for the mono ramp; the locale supplies the day and month names.
  ///
  /// An all-day block passes its localized label as [allDayLabel] and gets
  /// `TUE 4 AUG · ALL DAY` — its stored instants are a real midnight → 23:59
  /// span, which would otherwise read as a suspiciously precise workday.
  static String formatWhenLine(
    DateTime start,
    DateTime end, {
    String? allDayLabel,
  }) {
    final format = _whenLineFormats.putIfAbsent(
      _locale,
      () => DateFormat('EEE d MMM', _locale),
    );
    final day = format.format(start).toUpperCase();
    if (allDayLabel != null) return '$day · ${allDayLabel.toUpperCase()}';
    return '$day · ${formatTime(start)} – ${formatTime(end)}';
  }
}

extension DateOnly on DateTime {
  /// Midnight of this date in the same zone, centralizing the day-floor.
  DateTime get dateOnly => DateTime(year, month, day);
}

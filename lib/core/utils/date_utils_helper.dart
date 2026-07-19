import 'package:intl/intl.dart';

class DateUtilsHelper {
  // DateFormat parses its locale's symbols on construction, so the formatters
  // are cached per locale instead of rebuilt on every call — these run twice
  // per appointment row inside list item builders.
  static final Map<String, DateFormat> _timeFormats = {};
  static final Map<String, DateFormat> _dateFormats = {};
  static final Map<String, DateFormat> _dayHeaderFormats = {};

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

  /// "Tuesday, June 23" day-group header for the history list.
  static String formatDayHeader(DateTime date) {
    final format = _dayHeaderFormats.putIfAbsent(
      _locale,
      () => DateFormat('EEEE, MMMM d', _locale),
    );
    return format.format(date);
  }
}

extension DateOnly on DateTime {
  /// Midnight of this date in the same zone (drops time-of-day). Centralizes
  /// the `DateTime(year, month, day)` day-floor so a caller can't forget to
  /// zero a component.
  DateTime get dateOnly => DateTime(year, month, day);
}

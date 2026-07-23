import 'package:intl/intl.dart';

class DateUtilsHelper {
  // Cached per locale since DateFormat parses locale symbols on construction.
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
  /// Midnight of this date in the same zone, centralizing the day-floor.
  DateTime get dateOnly => DateTime(year, month, day);
}

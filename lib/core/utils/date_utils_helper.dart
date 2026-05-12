import 'package:intl/intl.dart';

class DateUtilsHelper {
  static String get _locale => Intl.defaultLocale ?? 'en_CA';

  static String formatTime(DateTime date) {
    return DateFormat.jm(_locale).format(date);
  }

  static String formatDate(DateTime date) {
    return DateFormat.yMMMd(_locale).format(date);
  }
}

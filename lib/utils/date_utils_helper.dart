import 'package:intl/intl.dart';

class DateUtilsHelper {

  static String formatTime(DateTime date) {
    return DateFormat('h:mm a').format(date); // "3:05 PM"
  }

  static String formatDate(DateTime date) {
    return DateFormat('MMM d, yyyy').format(date); // "Apr 8, 2026"
  }

  static String formatPrettyDate(DateTime date) {
    return DateFormat('EEEE, MMM d, h:mm a').format(date); // "Tuesday, Apr 8, 2:30 PM"
  }

  static String getMonthName(int month) {
    return DateFormat('MMM').format(DateTime(0, month)); // "Jan", "Feb"...
  }






}
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Which crew member the admin calendar is narrowed to, or null for everyone.
class CalendarCrewFilter extends Notifier<String?> {
  @override
  String? build() => null;

  String? get selection => state;

  set selection(String? employeeId) => state = employeeId;

  void clear() => state = null;
}

final calendarCrewFilterProvider =
    NotifierProvider<CalendarCrewFilter, String?>(CalendarCrewFilter.new);

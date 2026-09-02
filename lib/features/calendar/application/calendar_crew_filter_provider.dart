import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Which crew member the admin calendar is narrowed to, or null for everyone.
///
/// Session-scoped and deliberately NOT persisted: a filter that survived a
/// restart would hide most of the schedule with nothing on screen explaining
/// why, and the banner that names the person is only drawn while the calendar
/// that set it is up.
class CalendarCrewFilter extends Notifier<String?> {
  @override
  String? build() => null;

  String? get selection => state;

  set selection(String? employeeId) => state = employeeId;

  void clear() => state = null;
}

final calendarCrewFilterProvider =
    NotifierProvider<CalendarCrewFilter, String?>(CalendarCrewFilter.new);

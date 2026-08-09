import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:scheduling/core/utils/date_utils_helper.dart';
import 'package:scheduling/core/utils/firestore_parsing.dart';
import 'package:scheduling/features/calendar/domain/appointment_day_slice.dart';
import 'package:scheduling/features/calendar/domain/appointment_status_values.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_image.dart';
import 'package:scheduling/features/calendar/domain/models/repeat_interval.dart';

part 'appointment_record.freezed.dart';

@freezed
abstract class AppointmentRecord with _$AppointmentRecord {
  const factory AppointmentRecord({
    required DateTime startTime,
    required DateTime endTime,
    String? id,
    @Default('') String title,
    @Default('') String clientId,
    @Default('') String clientName,
    @Default('') String clientPhone,
    @Default(<String>[]) List<String> employeeIds,
    @Default(<String>[]) List<String> employeeNames,
    @Default('') String address,
    @Default('') String notes,
    @Default('') String materialsNeeded,
    @Default('pending') String status,
    // A personal job — time blocked off for the crew rather than a visit to a
    // client. Client and address are not collected for one, so every consumer
    // that speaks a client name has to fall back to the title.
    @Default(false) bool isPersonal,
    // No time was put in, so the block owns the whole day. `startTime`/
    // `endTime` are still real instants (midnight → 23:59) so every existing
    // range query, sort and index keeps working — this flag only changes how
    // the day is SHOWN.
    @Default(false) bool isAllDay,
    @Default(RepeatInterval.none) RepeatInterval repeat,
    // Links the occurrences of one repeat series (the first visit's doc id).
    @Default('') String seriesId,
    DateTime? createdAt,
    DateTime? updatedAt,
    @Default(<AppointmentImage>[]) List<AppointmentImage> pictures,
  }) = _AppointmentRecord;
  const AppointmentRecord._();

  factory AppointmentRecord.fromMap(String id, Map<String, dynamic> data) {
    return AppointmentRecord(
      id: id,
      title: (data['title'] ?? '').toString(),
      startTime: firestoreDateTime(data['startTime']) ?? DateTime.now(),
      endTime: firestoreDateTime(data['endTime']) ?? DateTime.now(),
      clientId: (data['clientId'] ?? '').toString(),
      clientName: (data['clientName'] ?? '').toString(),
      clientPhone: (data['clientPhone'] ?? '').toString(),
      employeeIds: _parseStringList(data['employeeIds']),
      employeeNames: _parseStringList(data['employeeNames']),
      address: (data['address'] ?? '').toString(),
      notes: (data['notes'] ?? '').toString(),
      materialsNeeded: (data['materialsNeeded'] ?? '').toString(),
      status: (data['status'] ?? 'pending').toString(),
      isPersonal: data['isPersonal'] == true,
      isAllDay: data['isAllDay'] == true,
      repeat: RepeatInterval.fromRaw((data['repeat'] ?? '').toString()),
      seriesId: (data['seriesId'] ?? '').toString(),
      createdAt: firestoreDateTime(data['createdAt']),
      updatedAt: firestoreDateTime(data['updatedAt']),
      pictures: _parseImageList(data['pictures']),
    );
  }

  Map<String, dynamic> toMap() => {
    'title': title,
    'startTime': startTime,
    'endTime': endTime,
    'clientId': clientId,
    'clientName': clientName,
    'clientPhone': clientPhone,
    'employeeIds': employeeIds,
    'employeeNames': employeeNames,
    'address': address,
    'notes': notes,
    'pictures': pictures.map((p) => p.toMap()).toList(),
    'materialsNeeded': materialsNeeded,
    'status': status,
    'isPersonal': isPersonal,
    'isAllDay': isAllDay,
    'repeat': repeat.raw,
    'seriesId': seriesId,
  };

  /// A display status computed from the current time — never stored. Keep this
  /// in sync with functions/notification_utils.js.
  String get displayStatus => displayStatusAt(DateTime.now());

  /// The job is closed — `cancelled`, or `done` in either of its spellings.
  ///
  /// These are the only statuses the clock ladder below can neither produce nor
  /// erase, which is what makes this the one status test a pure module can ask
  /// without a clock. The vocabulary itself lives in
  /// `appointment_status_values.dart` — shared with the History query's
  /// `whereIn`, which is where it had drifted — and is deliberately reachable
  /// without pulling Material in through `status_chip.dart`, so
  /// `appointment_day_slice.dart` can sort on it.
  bool get isClosed => isTerminalStatusRaw(status);

  /// The clock-derived ladder, keyed on [now] so callers that already hold a
  /// clock (the dashboard reducers) share this one owner instead of re-deriving
  /// it — they drifted apart once already, and a personal block then showed as
  /// Scheduled on its card and Overdue on the dashboard.
  String displayStatusAt(DateTime now) {
    if (isClosed) return status;
    // A personal block is not a job being worked: it stays on its stored
    // status (which reads "Scheduled") instead of flipping to In Progress at
    // its start and Overdue at its end. The server's overdue sweep skips these
    // for the same reason — the two must agree.
    if (isPersonal) return status;
    if (now.isAfter(endTime)) return 'overdue';
    if (now.isAfter(startTime)) return 'in_progress';
    return status;
  }

  static List<String> _parseStringList(dynamic value) {
    if (value is List) return value.whereType<String>().toList();
    if (value is String && value.isNotEmpty) return [value];
    return const [];
  }

  static List<AppointmentImage> _parseImageList(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Map<Object?, Object?>>()
        .map(
          (item) => AppointmentImage.fromMap(Map<String, dynamic>.from(item)),
        )
        .toList();
  }
}

/// How many days beyond today the two off-screen schedule mirrors fetch.
///
/// One owner for both, so [AppointmentDateRange.forMirrors] produces a single
/// range value and they share one Firestore listener. `Siri`'s
/// `scheduleSnapshotLookaheadDays` is this value.
const int mirrorLookaheadDays = 7;

@immutable
class AppointmentDateRange {
  const AppointmentDateRange({required this.start, required this.end});

  factory AppointmentDateRange.visibleMonth(DateTime focusedDay) {
    final firstOfMonth = DateTime(focusedDay.year, focusedDay.month);
    final firstOfNextMonth = DateTime(focusedDay.year, focusedDay.month + 1);
    // Calendar arithmetic, for the same reason `forDay` uses it: a Duration
    // lands an hour off real midnight on the two DST-shift days, which clipped
    // a day off the overscan (Oct 2026 ended at Nov 14 23:00, so Nov 15 fell
    // outside) and left `fetchStart` carrying the drift.
    return AppointmentDateRange(
      start: addCalendarDays(firstOfMonth, -_gridOverscanDays),
      end: addCalendarDays(firstOfNextMonth, _gridOverscanDays),
    );
  }

  /// One calendar day, midnight to the next midnight (exclusive).
  ///
  /// The single owner of that arithmetic. It is **calendar** arithmetic, not a
  /// fixed 24h: `add(Duration(days: 1))` lands an hour off real midnight on the
  /// two DST-shift days, which both mis-buckets a late-evening job AND forks a
  /// second listener, because a range that should equal another day-range
  /// consumer's no longer does — `appointmentsInRangeProvider` is keyed by
  /// value, so an hour of drift opens a whole second Firestore query for the
  /// same day.
  factory AppointmentDateRange.forDay(DateTime day) {
    final start = day.dateOnly;
    return AppointmentDateRange(
      start: start,
      end: DateTime(start.year, start.month, start.day + 1),
    );
  }

  /// A stable 7-day fetch window containing [day].
  ///
  /// For a surface that pages one day at a time but re-scopes in Dart anyway
  /// (the day route, via `sliceFor`). `forDay` is the wrong window there:
  /// `fetchStart` widens ONE day into a 15-day query, so arrowing across a
  /// week opened seven overlapping 15-day listeners — each kept warm by the
  /// eviction grace — instead of one 21-day listener covering the lot.
  ///
  /// Bucketed on a fixed epoch boundary rather than the locale's week start,
  /// because this is a FETCH window, not a display week: a locale-dependent
  /// bucket would give two surfaces looking at the same day unequal ranges,
  /// and `appointmentsInRangeProvider` is keyed by value, so that forks a
  /// second Firestore query for the same documents.
  factory AppointmentDateRange.forWeekBucketOf(DateTime day) {
    final d = day.dateOnly;
    // UTC-normalized, so the two DST-shift days can't move a day into the
    // neighbouring bucket and fork a listener.
    final offset = calendarDaysBetween(DateTime(1970), d) % 7;
    final start = addCalendarDays(d, -offset);
    return AppointmentDateRange(start: start, end: addCalendarDays(start, 7));
  }

  /// The ONE window both off-screen schedule mirrors fetch.
  ///
  /// The Siri snapshot needs today + 7 days; the home-screen widget needs only
  /// today + tomorrow. Both are held open for the whole session by
  /// `AppSyncListeners`, and both ask the same `myAppointmentsProvider` family
  /// — which is keyed by range VALUE — so two different ranges meant two
  /// permanent Firestore listeners per signed-in user, streaming overlapping
  /// documents forever, with the widget's window a strict subset of the
  /// snapshot's. `buildWidgetPayload` re-scopes to today/tomorrow in Dart
  /// anyway, so the wider list feeds it unchanged.
  ///
  /// Same reasoning as [AppointmentDateRange.forWeekBucketOf]: two surfaces
  /// looking at the same data must produce EQUAL ranges, or they fork a second
  /// query.
  factory AppointmentDateRange.forMirrors(DateTime today) {
    final start = today.dateOnly;
    return AppointmentDateRange(
      start: start,
      end: addCalendarDays(start, mirrorLookaheadDays + 1),
    );
  }

  /// The window the calendar screen actually needs: the visible month's grid
  /// **plus the selected day**, which the agenda below the grid is showing.
  ///
  /// Paging months moves [focusedDay] and leaves [selectedDay] behind, so a
  /// month-only window stops covering the selected day after a swipe or two —
  /// its jobs then drop out of the fetch and the agenda reports "0 jobs" for a
  /// day that has some.
  factory AppointmentDateRange.forCalendar({
    required DateTime focusedDay,
    required DateTime selectedDay,
  }) {
    final month = AppointmentDateRange.visibleMonth(focusedDay);
    final day = AppointmentDateRange.forDay(selectedDay);
    return AppointmentDateRange(
      start: day.start.isBefore(month.start) ? day.start : month.start,
      end: day.end.isAfter(month.end) ? day.end : month.end,
    );
  }

  /// How far back the range QUERY must reach. A job that started up to
  /// [maxAppointmentSpanDays] ago can still be running inside this window, and
  /// the query filters on `startTime` alone — so without this the calendar
  /// simply never sees it.
  ///
  /// Deliberately a derived getter and NOT a constructor field: `==` stays
  /// keyed on [start]/[end], so two surfaces asking for the same day still
  /// produce equal ranges and share one Firestore listener. Widening at a call
  /// site instead would fork a second query for the same day.
  DateTime get fetchStart =>
      DateTime(start.year, start.month, start.day - maxAppointmentSpanDays);

  /// The month grid renders only the weeks the month occupies, so it shows at
  /// most 6 leading and 6 trailing days — but the fetch keeps a wider ±14
  /// window: it is a superset of every grid shape, and narrowing it buys one
  /// query's worth of documents at the cost of dotless edge cells if the grid
  /// ever grows a row back.
  static const int _gridOverscanDays = 14;

  final DateTime start;
  final DateTime end;

  @override
  bool operator ==(Object other) =>
      other is AppointmentDateRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);
}

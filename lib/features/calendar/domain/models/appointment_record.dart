import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:scheduling/core/utils/date_utils_helper.dart';
import 'package:scheduling/core/utils/firestore_parsing.dart';
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

  /// The clock-derived ladder, keyed on [now] so callers that already hold a
  /// clock (the dashboard reducers) share this one owner instead of re-deriving
  /// it — they drifted apart once already, and a personal block then showed as
  /// Scheduled on its card and Overdue on the dashboard.
  String displayStatusAt(DateTime now) {
    final s = status.toLowerCase();
    if (s == 'done' || s == 'completed' || s == 'cancelled') return status;
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

@immutable
class AppointmentDateRange {
  const AppointmentDateRange({required this.start, required this.end});

  factory AppointmentDateRange.visibleMonth(DateTime focusedDay) {
    final firstOfMonth = DateTime(focusedDay.year, focusedDay.month);
    final firstOfNextMonth = DateTime(focusedDay.year, focusedDay.month + 1);
    return AppointmentDateRange(
      start: firstOfMonth.subtract(_gridOverscan),
      end: firstOfNextMonth.add(_gridOverscan),
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
    final dayStart = selectedDay.dateOnly;
    // Exclusive upper bound, matching visibleMonth's.
    final dayEnd = DateTime(
      selectedDay.year,
      selectedDay.month,
      selectedDay.day + 1,
    );
    return AppointmentDateRange(
      start: dayStart.isBefore(month.start) ? dayStart : month.start,
      end: dayEnd.isAfter(month.end) ? dayEnd : month.end,
    );
  }

  /// The month grid renders only the weeks the month occupies, so it shows at
  /// most 6 leading and 6 trailing days — but the fetch keeps a wider ±14
  /// window: it is a superset of every grid shape, and narrowing it buys one
  /// query's worth of documents at the cost of dotless edge cells if the grid
  /// ever grows a row back.
  static const Duration _gridOverscan = Duration(days: 14);

  final DateTime start;
  final DateTime end;

  @override
  bool operator ==(Object other) =>
      other is AppointmentDateRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);
}

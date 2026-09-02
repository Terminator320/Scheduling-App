import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:scheduling/core/utils/date_utils_helper.dart';
import 'package:scheduling/core/utils/firestore_parsing.dart';
import 'package:scheduling/features/calendar/domain/appointment_day_slice.dart';
import 'package:scheduling/features/calendar/domain/appointment_status_values.dart';
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
    // What the CREW recorded on site, as distinct from [notes], which the
    // dispatcher writes when booking. Two fields on purpose: they are written
    // by different people under different rules, and one field would mean an
    // assignee's write had to be allowed to overwrite the brief they were
    // given.
    @Default('') String fieldNotes,
    @Default('') String materialsNeeded,
    @Default('pending') String status,
    // Personal jobs block crew time without client fields.
    @Default(false) bool isPersonal,
    // All-day jobs still store real start/end instants.
    @Default(false) bool isAllDay,
    // Day off is meaningful only through [isTimeOff].
    @Default(false) bool isDayOff,
    @Default(RepeatInterval.none) RepeatInterval repeat,
    // Links repeat occurrences or split days for one multi-day run.
    @Default('') String seriesId,
    // Multi-day run labels; read through `AppointmentDaySlice.sliceFor`.
    @Default(0) int dayIndex,
    @Default(0) int dayCount,
    DateTime? createdAt,
    DateTime? updatedAt,
    // Parent-card photo indicator, owned by server recounts after create.
    @Default(0) int pictureCount,
    // The job time record. Both are stamped SERVER-SIDE by the appointment
    // write trigger on the status transition (`lifecycleStamps` in
    // `functions/notification_policy.js`), never by a client.
    DateTime? startedAt,
    DateTime? completedAt,
    // What an assignee last signalled on the way to the job; one of
    // `crewStatusRawValues` or empty. Written only through
    // `updateCrewStatus`, by the person named in [crewStatusBy].
    @Default('') String crewStatus,
    DateTime? crewStatusAt,
    @Default('') String crewStatusBy,
  }) = _AppointmentRecord;
  const AppointmentRecord._();

  factory AppointmentRecord.fromMap(String id, Map<String, dynamic> data) {
    final fallbackTime = DateTime.now();
    return AppointmentRecord(
      id: id,
      title: (data['title'] ?? '').toString(),
      startTime: firestoreDateTime(data['startTime']) ?? fallbackTime,
      endTime: firestoreDateTime(data['endTime']) ?? fallbackTime,
      clientId: (data['clientId'] ?? '').toString(),
      clientName: (data['clientName'] ?? '').toString(),
      clientPhone: (data['clientPhone'] ?? '').toString(),
      employeeIds: firestoreStringList(data['employeeIds']),
      employeeNames: firestoreStringList(data['employeeNames']),
      address: (data['address'] ?? '').toString(),
      notes: (data['notes'] ?? '').toString(),
      fieldNotes: (data['fieldNotes'] ?? '').toString(),
      materialsNeeded: (data['materialsNeeded'] ?? '').toString(),
      status: (data['status'] ?? 'pending').toString(),
      isPersonal: data['isPersonal'] == true,
      isAllDay: data['isAllDay'] == true,
      isDayOff: data['isDayOff'] == true,
      repeat: RepeatInterval.fromRaw((data['repeat'] ?? '').toString()),
      seriesId: (data['seriesId'] ?? '').toString(),
      dayIndex: _parseCount(data['dayIndex']),
      dayCount: _parseCount(data['dayCount']),
      createdAt: firestoreDateTime(data['createdAt']),
      updatedAt: firestoreDateTime(data['updatedAt']),
      pictureCount: _parseCount(data['pictureCount']),
      startedAt: firestoreDateTime(data['startedAt']),
      completedAt: firestoreDateTime(data['completedAt']),
      crewStatus: (data['crewStatus'] ?? '').toString(),
      crewStatusAt: firestoreDateTime(data['crewStatusAt']),
      crewStatusBy: (data['crewStatusBy'] ?? '').toString(),
    );
  }

  /// Whether an assignee has signalled on the way to this job.
  bool get hasCrewSignal => crewStatus.isNotEmpty;

  /// Whether this job should show the card photo indicator.
  bool get hasPictures => pictureCount > 0;

  /// True for personal day-off blocks that count as unavailable, not work.
  bool get isTimeOff => isPersonal && isDayOff;

  /// Parses display counts fail-closed to zero.
  static int _parseCount(dynamic value) {
    if (value is int) return value < 0 ? 0 : value;
    if (value is num) return value < 0 ? 0 : value.toInt();
    return 0;
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
    'fieldNotes': fieldNotes,
    'materialsNeeded': materialsNeeded,
    'status': status,
    'isPersonal': isPersonal,
    'isAllDay': isAllDay,
    'isDayOff': isDayOff,
    'repeat': repeat.raw,
    'seriesId': seriesId,
    // Single-day jobs omit run labels. Both halves are gated on the PAIR being
    // coherent, not on `isRunMember` alone: `dayIndex` defaults to 0 when the
    // source doc had none, and the rules bound it at `>= 1`, so a doc carrying
    // `dayCount: 5` with no `dayIndex` would re-serialize as `dayIndex: 0` and
    // be refused — permanently, on every edit including the cancel that would
    // clear it. Only a console or Admin-SDK write can produce that pair, and
    // dropping the labels repairs it where emitting a rejected value strands
    // it. Same asymmetry as `appointmentSpanNotWidened`.
    if (hasRunLabels) 'dayIndex': dayIndex,
    if (hasRunLabels) 'dayCount': dayCount,
    // `startedAt`, `completedAt` and the three `crewStatus*` fields are
    // deliberately NOT here. Every client path that re-serializes a record
    // writes through `.update()` / `txn.update()`, which MERGES, so the stored
    // values survive an admin edit untouched — while `addAppointments` and
    // `rewriteSeries` copies are NEW documents that must not inherit another
    // job's time record or crew signal. The stamps have one server-side owner
    // and the signal has one write path (`updateCrewStatus`).
  };

  /// Whether the stored run pair is coherent enough to write back.
  bool get hasRunLabels => isRunMember && dayIndex >= 1 && dayIndex <= dayCount;

  /// One day of a multi-day run, whose length is fixed at booking.
  bool get isRunMember => dayCount > 1;

  /// Clock-derived display status; keep synced with notification functions.
  String get displayStatus => displayStatusAt(DateTime.now());

  /// Stored terminal status check.
  bool get isClosed => isTerminalStatusRaw(status);

  /// Applies the clock-derived status ladder at [now].
  String displayStatusAt(DateTime now) {
    if (isClosed) return status;
    // Day off completes itself after its end time.
    if (isTimeOff) return now.isAfter(endTime) ? 'done' : status;
    // Personal blocks stay on their stored status.
    if (isPersonal) return status;
    if (now.isAfter(endTime)) return 'overdue';
    if (now.isAfter(startTime)) return 'in_progress';
    return status;
  }
}

/// Shared lookahead for off-screen schedule mirrors.
const int mirrorLookaheadDays = 7;

@immutable
class AppointmentDateRange {
  const AppointmentDateRange({required this.start, required this.end});

  factory AppointmentDateRange.visibleMonth(DateTime focusedDay) {
    final firstOfMonth = DateTime(focusedDay.year, focusedDay.month);
    final firstOfNextMonth = DateTime(focusedDay.year, focusedDay.month + 1);
    // Calendar arithmetic keeps DST shifts from moving midnight.
    return AppointmentDateRange(
      start: addCalendarDays(firstOfMonth, -_gridOverscanDays),
      end: addCalendarDays(firstOfNextMonth, _gridOverscanDays),
    );
  }

  /// One calendar day, midnight to the next midnight, exclusive.
  factory AppointmentDateRange.forDay(DateTime day) {
    final start = day.dateOnly;
    return AppointmentDateRange(
      start: start,
      end: DateTime(start.year, start.month, start.day + 1),
    );
  }

  /// Stable 7-day fetch bucket containing [day].
  factory AppointmentDateRange.forWeekBucketOf(DateTime day) {
    final d = day.dateOnly;
    // UTC-normalized so DST cannot move a day into another bucket.
    final offset = calendarDaysBetween(DateTime(1970), d) % 7;
    final start = addCalendarDays(d, -offset);
    return AppointmentDateRange(start: start, end: addCalendarDays(start, 7));
  }

  /// Shared fetch window for off-screen schedule mirrors.
  factory AppointmentDateRange.forMirrors(DateTime today) {
    final start = today.dateOnly;
    return AppointmentDateRange(
      start: start,
      end: addCalendarDays(start, mirrorLookaheadDays + 1),
    );
  }

  /// Calendar fetch window covering both the visible month and selected day.
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

  /// The smallest range covering both this one and [other].
  ///
  /// Value-equal to `this` whenever [other] already sits inside it, so a
  /// consumer that unions a sub-range onto the calendar's window keeps the
  /// same listener key in the common case.
  AppointmentDateRange union(AppointmentDateRange other) {
    final newStart = other.start.isBefore(start) ? other.start : start;
    final newEnd = other.end.isAfter(end) ? other.end : end;
    if (newStart == start && newEnd == end) return this;
    return AppointmentDateRange(start: newStart, end: newEnd);
  }

  /// Query start widened for long appointments that overlap this range.
  DateTime get fetchStart =>
      DateTime(start.year, start.month, start.day - maxAppointmentSpanDays);

  /// Off-month fetch padding for visible grid dots.
  static const int _gridOverscanDays = 7;

  final DateTime start;
  final DateTime end;

  @override
  bool operator ==(Object other) =>
      other is AppointmentDateRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);
}

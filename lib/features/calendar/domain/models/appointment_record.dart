import 'package:freezed_annotation/freezed_annotation.dart';

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
    'repeat': repeat.raw,
    'seriesId': seriesId,
  };

  /// Time-derived status for display only — NEVER written to Firestore (the
  /// rules allowlist is pending/in_progress/done/cancelled). Terminal stored
  /// states win; otherwise a visit reads `in_progress` while it's happening and
  /// `overdue` once its end time has passed without being marked done.
  /// Server mirror: `selectOverdueCandidates` / `OPEN_LIKE` in
  /// functions/notification_utils.js drive the overdue push prompt from the
  /// same rule — keep them in sync when changing this logic (a status unknown
  /// to that allowlist shows Overdue here but is never swept server-side).
  String get displayStatus {
    final s = status.toLowerCase();
    if (s == 'done' || s == 'completed' || s == 'cancelled') return status;
    final now = DateTime.now();
    if (now.isAfter(endTime)) return 'overdue';
    if (now.isAfter(startTime)) return 'in_progress';
    return status;
  }

  static List<String> _parseStringList(dynamic value) {
    if (value is List) return List<String>.from(value);
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
      start: firstOfMonth.subtract(const Duration(days: 7)),
      end: firstOfNextMonth.add(const Duration(days: 7)),
    );
  }

  final DateTime start;
  final DateTime end;

  @override
  bool operator ==(Object other) =>
      other is AppointmentDateRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);
}

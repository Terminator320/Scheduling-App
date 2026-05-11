import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:scheduling/features/calendar/domain/models/appointment_image.dart';

part 'appointment_record.freezed.dart';

/// Firestore collection: `appointments`
///
/// Example doc shape:
/// ```json
/// {
///   "title": "Kitchen sink leak",
///   "startTime": Timestamp,
///   "endTime": Timestamp,
///   "clientId": "<clients/{id}>",
///   "clientName": "Acme Inc",
///   "clientPhone": "+1-514-555-0101",
///   "employeeIds": ["<users/{id}>", ...],
///   "employeeNames": ["Jane Doe", ...],
///   "address": "12-1245 Rue de Bleury, Montréal, QC",
///   "notes": "Bring 1/2 inch wrench",
///   "materialsNeeded": "PVC fittings",
///   "status": "pending",  // 'pending' | 'confirmed' | 'in_progress' | 'done' | 'cancelled'
///   "pictures": [ AppointmentImage, ... ],
///   "createdAt": Timestamp,
///   "updatedAt": Timestamp
/// }
/// ```
///
/// Employees see only docs where `employeeIds` contains their user doc id —
/// CLAUDE.md invariant enforced both client-side and in `firestore.rules`.
@freezed
abstract class AppointmentRecord with _$AppointmentRecord {

  const factory AppointmentRecord({
    required DateTime startTime, required DateTime endTime, String? id,
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
    DateTime? createdAt,
    DateTime? updatedAt,
    @Default(<AppointmentImage>[]) List<AppointmentImage> pictures,
  }) = _AppointmentRecord;
  const AppointmentRecord._();

  factory AppointmentRecord.fromMap(String id, Map<String, dynamic> data) {
    return AppointmentRecord(
      id: id,
      title: (data['title'] ?? '').toString(),
      startTime: _parseDateTime(data['startTime']) ?? DateTime.now(),
      endTime: _parseDateTime(data['endTime']) ?? DateTime.now(),
      clientId: (data['clientId'] ?? '').toString(),
      clientName: (data['clientName'] ?? '').toString(),
      clientPhone: (data['clientPhone'] ?? '').toString(),
      employeeIds: _parseStringList(data['employeeIds']),
      employeeNames: _parseStringList(data['employeeNames']),
      address: (data['address'] ?? '').toString(),
      notes: (data['notes'] ?? '').toString(),
      materialsNeeded: (data['materialsNeeded'] ?? '').toString(),
      status: (data['status'] ?? 'pending').toString(),
      createdAt: _parseDateTime(data['createdAt']),
      updatedAt: _parseDateTime(data['updatedAt']),
      pictures: _parseImageList(data['pictures']),
    );
  }

  /// Serializes for a Firestore `update`. The repository injects
  /// `createdAt`/`updatedAt` server timestamps where appropriate.
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
  };

  /// `pending`/`confirmed` get auto-promoted to `in_progress` once the start
  /// time has passed. Terminal statuses (`done`, `completed`, `cancelled`) are
  /// always returned verbatim.
  String get displayStatus {
    final s = status.toLowerCase();
    if (s == 'done' || s == 'completed' || s == 'cancelled') return status;
    if (DateTime.now().isAfter(startTime)) return 'in_progress';
    return status;
  }

  static DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    // Avoid importing cloud_firestore — check Firestore Timestamp by type name.
    final typeName = value.runtimeType.toString();
    if (typeName == 'Timestamp') {
      // ignore: avoid_dynamic_calls
      return (value as dynamic).toDate() as DateTime;
    }
    return null;
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
        .map((item) => AppointmentImage.fromMap(Map<String, dynamic>.from(item)))
        .toList();
  }
}

/// Date window used by the calendar to load only the visible month plus a
/// one-week buffer. Pure Dart so it's testable without Firestore.
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

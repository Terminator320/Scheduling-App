import 'package:flutter/material.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'employee_record.freezed.dart';

/// Firestore collection: `users` (employees + admins live in the same
/// collection, distinguished by `role`).
///
/// Example doc shape:
/// ```json
/// {
///   "name": "Jane Doe",
///   "email": "jane@example.com",
///   "phone": "+1-514-555-0101",
///   "colorValue": "4280391411",
///   "role": "employee",        // 'admin' | 'employee'
///   "status": "active",        // 'invited' | 'active' | 'disabled'
///   "uid": "<firebase auth uid, blank until activated>",
///   "createdAt": Timestamp
/// }
/// ```
///
/// `colorValue` is stored as a stringified `int` — preserved verbatim across
/// the freezed migration so existing documents keep working without backfill.
@freezed
abstract class EmployeeRecord with _$EmployeeRecord {

  const factory EmployeeRecord({
    required String id,
    @Default('') String name,
    @Default('') String email,
    @Default('') String phone,
    @Default(Color(0xFF2196F3)) Color color,
    @Default('employee') String role,
    @Default('') String status,
    @Default('') String uid,
  }) = _EmployeeRecord;
  const EmployeeRecord._();

  factory EmployeeRecord.fromMap(String id, Map<String, dynamic> data) {
    final colorValue =
        int.tryParse((data['colorValue'] ?? '').toString()) ??
        Colors.blue.toARGB32();

    return EmployeeRecord(
      id: id,
      name: (data['name'] ?? '').toString(),
      email: (data['email'] ?? '').toString(),
      phone: (data['phone'] ?? '').toString(),
      color: Color(colorValue),
      role: (data['role'] ?? 'employee').toString(),
      status: (data['status'] ?? '').toString(),
      uid: (data['uid'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toMap() => {
    'name': name,
    'email': email,
    'phone': phone,
    'colorValue': color.toARGB32().toString(),
    'role': role,
    'status': status,
    'uid': uid,
  };

  String get initials {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  bool get isAdmin => role == 'admin';
  bool get isActive => status == 'active';
  bool get isDisabled => status == 'disabled';
}

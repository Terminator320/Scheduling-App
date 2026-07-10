import 'package:flutter/material.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'employee_record.freezed.dart';

@freezed
abstract class EmployeeRecord with _$EmployeeRecord {
  const factory EmployeeRecord({
    required String id,
    @Default('') String name,
    @Default('') String email,
    @Default('') String phone,
    // NOTE: legacy default (Material blue) for docs stored before the color
    // palette existed — changing it recolors those employees; keep as-is.
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

  bool get isAdmin => role == 'admin';
  bool get isActive => status == 'active';
  bool get isDisabled => status == 'disabled';
}

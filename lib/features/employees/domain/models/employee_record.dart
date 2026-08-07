import 'package:flutter/material.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:scheduling/core/utils/firestore_parsing.dart';
import 'package:scheduling/features/employees/domain/models/job_title.dart';
import 'package:scheduling/features/employees/domain/policies/work_schedule_policy.dart';

part 'employee_record.freezed.dart';

@freezed
abstract class EmployeeRecord with _$EmployeeRecord {
  const factory EmployeeRecord({
    required String id,
    @Default('') String name,
    @Default('') String firstName,
    @Default('') String lastName,
    @Default('') String email,
    @Default('') String phone,
    // Legacy default (Material blue) for docs predating the color palette —
    // changing this recolors those employees.
    @Default(Color(0xFF2196F3)) Color color,
    @Default('employee') String role,
    @Default('') String status,
    @Default('') String uid,
    @Default(JobTitle.unset) JobTitle jobTitle,
    @Default(kDefaultWorkingDays) List<bool> workingDays,
    @Default(kDefaultWorkStartMinutes) int workStartMinutes,
    @Default(kDefaultWorkEndMinutes) int workEndMinutes,
    // 0 means no cap.
    @Default(0) int maxJobsPerDay,
    @Default(false) bool onCall,
    // NOTE: emergencyContact/emergencyPhone are NOT here — they live in
    // users/{docId}/private/emergency so rules can gate them to the admin and
    // the person themselves. See EmergencyContact.
    // Server timestamp, same read-only contract as ClientRecord.createdAt.
    DateTime? createdAt,
  }) = _EmployeeRecord;
  const EmployeeRecord._();

  factory EmployeeRecord.fromMap(String id, Map<String, dynamic> data) {
    final colorValue =
        int.tryParse((data['colorValue'] ?? '').toString()) ??
        Colors.blue.toARGB32();
    final storedDays = (data['workingDays'] as List?)
        ?.map((v) => v == true)
        .toList();

    return EmployeeRecord(
      id: id,
      name: (data['name'] ?? '').toString(),
      firstName: (data['firstName'] ?? '').toString(),
      lastName: (data['lastName'] ?? '').toString(),
      email: (data['email'] ?? '').toString(),
      phone: (data['phone'] ?? '').toString(),
      color: Color(colorValue),
      role: (data['role'] ?? 'employee').toString(),
      status: (data['status'] ?? '').toString(),
      uid: (data['uid'] ?? '').toString(),
      jobTitle: JobTitle.fromRaw(data['jobTitle'] as String?),
      workingDays: normalizeWorkingDays(storedDays ?? const []),
      workStartMinutes:
          (data['workStartMinutes'] as num?)?.toInt() ??
          kDefaultWorkStartMinutes,
      workEndMinutes:
          (data['workEndMinutes'] as num?)?.toInt() ?? kDefaultWorkEndMinutes,
      maxJobsPerDay: (data['maxJobsPerDay'] as num?)?.toInt() ?? 0,
      onCall: data['onCall'] == true,
      createdAt: firestoreDateTime(data['createdAt']),
    );
  }

  /// Editable fields only. `createdAt` is function-owned and deliberately
  /// absent — see its declaration.
  ///
  /// `uid` and `status` are absent for the same reason: `uid` is on the
  /// `/users` update denylist in `firestore.rules`, and `status` belongs to
  /// deactivate/reactivate. Emitting either would make a whole-record write
  /// fail with an opaque `permission-denied`.
  Map<String, dynamic> toMap() => {
    'name': name,
    'firstName': firstName,
    'lastName': lastName,
    'email': email,
    'phone': phone,
    'colorValue': color.toARGB32().toString(),
    'role': role,
    'jobTitle': jobTitle.raw,
    'workingDays': workingDays,
    'workStartMinutes': workStartMinutes,
    'workEndMinutes': workEndMinutes,
    'maxJobsPerDay': maxJobsPerDay,
    'onCall': onCall,
  };

  bool get isAdmin => role == 'admin';
  bool get isActive => status == 'active';
  bool get isDisabled => status == 'disabled';

  /// The account exists with a real `uid` but setup has never been completed —
  /// the person is still on the password their admin handed them.
  ///
  /// This is the one non-active status the auth gates route rather than sign
  /// out, so it is an EXACT match: an empty or unknown status must keep
  /// falling through to the sign-out branch, exactly as `isDisabled` does.
  bool get isInvited => status == 'invited';
}

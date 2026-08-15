import 'package:flutter/material.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:scheduling/core/theme/design_tokens.dart';
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
    // A crewPalette member, not Material blue: an off-palette hue is also
    // outside the dark-theme override map, so a doc that never picked a colour
    // rendered unlifted in dark.
    @Default(AppColors.crewDefault) Color color,
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
    // Per-person opt-out for the traffic-aware "time to leave" push. Defaults
    // to TRUE and an absent field reads as true, matching `wantsTravelAlerts`
    // in `functions/travel_utils.js` — every doc written before this field
    // existed has no value, and a default of false would silence the fleet.
    // Opting out degrades to the fixed 30-minute reminder; it does not drop
    // the notification.
    @Default(true) bool travelAlertsEnabled,
    // NOTE: emergencyContact/emergencyPhone are NOT here — they live in
    // users/{docId}/private/emergency so rules can gate them to the admin and
    // the person themselves. See EmergencyContact.
    // Server timestamp, same read-only contract as ClientRecord.createdAt —
    // though unlike that one it has no reader yet (ClientRecord's drives the
    // dashboard trends). Parsed so the field is available and never written
    // back: toMap() must not emit it.
    DateTime? createdAt,
  }) = _EmployeeRecord;
  const EmployeeRecord._();

  factory EmployeeRecord.fromMap(String id, Map<String, dynamic> data) {
    final colorValue =
        int.tryParse((data['colorValue'] ?? '').toString()) ??
        AppColors.crewDefault.toARGB32();
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
      // Lenient like every other field here, and for a sharper reason: this
      // factory runs inside three `users` snapshot streams AND on the sign-in
      // path, so one console-edited doc holding a numeric jobTitle or a string
      // "480" would throw app-wide — crew picker, day route, live-map roster
      // and calendar dots at once — and lock that person out of signing in.
      jobTitle: JobTitle.fromRaw(data['jobTitle']?.toString()),
      workingDays: normalizeWorkingDays(storedDays ?? const []),
      workStartMinutes:
          firestoreInt(data['workStartMinutes']) ?? kDefaultWorkStartMinutes,
      workEndMinutes:
          firestoreInt(data['workEndMinutes']) ?? kDefaultWorkEndMinutes,
      maxJobsPerDay: firestoreInt(data['maxJobsPerDay']) ?? 0,
      onCall: data['onCall'] == true,
      // `!= false`, never `== true`: an absent field must read as ON.
      travelAlertsEnabled: data['travelAlertsEnabled'] != false,
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
  ///
  /// `email` is absent for a sharper one: it is the person's SIGN-IN identity,
  /// and it moves through `changeEmployeeEmail` — which owns Auth and
  /// Firestore together — or not at all. A whole-record write carrying it
  /// would rewrite the doc while Auth kept the old address, the exact desync
  /// that callable exists to end, and it is the key `updateEmployee`'s
  /// uniqueness query reads. `updateEmployee` writes the normalized address
  /// itself, after the callable has committed.
  Map<String, dynamic> toMap() => {
    'name': name,
    'firstName': firstName,
    'lastName': lastName,
    'phone': phone,
    'colorValue': color.toARGB32().toString(),
    'role': role,
    'jobTitle': jobTitle.raw,
    'workingDays': workingDays,
    'workStartMinutes': workStartMinutes,
    'workEndMinutes': workEndMinutes,
    'maxJobsPerDay': maxJobsPerDay,
    'onCall': onCall,
    // NOTE: `travelAlertsEnabled` is deliberately NOT emitted. It is the
    // person's own notification preference, written only by
    // `updateSelfDetails` — an admin save must leave it exactly as it was, and
    // emitting it here would let a future whole-record write flip somebody
    // else's push setting.
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

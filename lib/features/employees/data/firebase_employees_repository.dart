import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import 'package:scheduling/core/utils/retry.dart';
import 'package:scheduling/features/employees/domain/employees_failure.dart';
import 'package:scheduling/features/employees/domain/employees_repository.dart';
import 'package:scheduling/features/employees/domain/models/emergency_contact.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';
import 'package:scheduling/features/employees/domain/models/invite_preview.dart';
import 'package:scheduling/features/employees/domain/policies/employee_name_policy.dart';
import 'package:scheduling/features/employees/domain/policies/work_schedule_policy.dart';

/// Shared bound on every `users` stream to prevent unbounded snapshots.
const _userStreamLimit = 500;

const _callableTimeout = Duration(seconds: 20);

class FirebaseEmployeesRepository implements EmployeesRepository {
  FirebaseEmployeesRepository(
    FirebaseFirestore firestore, {
    FirebaseFunctions? functions,
  }) : _users = firestore.collection('users'),
       _functions = functions ?? FirebaseFunctions.instance;

  final CollectionReference<Map<String, dynamic>> _users;
  final FirebaseFunctions _functions;

  @override
  Stream<List<EmployeeRecord>> watchAllUsers() {
    return retryStream(
      () => _users
          .orderBy('name')
          .limit(_userStreamLimit)
          .snapshots()
          .map(
            (snapshot) => snapshot.docs
                .map((doc) => EmployeeRecord.fromMap(doc.id, doc.data()))
                .toList(),
          ),
      retryWhen: _isAuthPropagationDenied,
    );
  }

  @override
  Stream<List<EmployeeRecord>> watchEmployees() {
    return retryStream(
      () => _users
          .where('role', whereIn: ['employee', 'admin'])
          .where('status', isEqualTo: 'active')
          // NOTE: no orderBy (watchAllUsers' orderBy excludes docs without name, dropping unnamed active employees).
          .limit(_userStreamLimit)
          .snapshots()
          .map(
            (snapshot) => snapshot.docs
                .map((doc) => EmployeeRecord.fromMap(doc.id, doc.data()))
                .toList(),
          ),
      retryWhen: _isAuthPropagationDenied,
    );
  }

  @override
  Stream<List<EmployeeRecord>> watchAssignableUsers() {
    return retryStream(
      () => _users
          .where('status', isEqualTo: 'active')
          .limit(_userStreamLimit)
          .snapshots()
          .map(
            (snapshot) => snapshot.docs
                .map((doc) => EmployeeRecord.fromMap(doc.id, doc.data()))
                .toList(),
          ),
      retryWhen: _isAuthPropagationDenied,
    );
  }

  @override
  Future<String> createEmployeeInvite({
    required String name,
    required String firstName,
    required String lastName,
    required String email,
    required String phone,
    required String colorValue,
    required String jobTitle,
    required bool isAdmin,
  }) async {
    try {
      final res = await _functions
          .httpsCallable(
            'createEmployeeInvite',
            options: HttpsCallableOptions(timeout: _callableTimeout),
          )
          .call<dynamic>({
            'name': name.trim(),
            'firstName': firstName.trim(),
            'lastName': lastName.trim(),
            'email': email.trim().toLowerCase(),
            'phone': phone.trim(),
            'colorValue': colorValue,
            'jobTitle': jobTitle,
            'isAdmin': isAdmin,
          });
      final data = (res.data as Map?)?.cast<String, dynamic>();
      final code = data?['code'] as String?;
      if (code == null || code.isEmpty) {
        throw const EmployeesFailureUnknown();
      }
      return code;
    } on FirebaseFunctionsException catch (e) {
      if (e.message == 'email-exists') {
        throw const EmployeesFailureEmailAlreadyExists();
      }
      rethrow;
    }
  }

  @override
  Future<void> revokeInvite(String inviteDocId) async {
    try {
      await _functions
          .httpsCallable(
            'revokeInvite',
            options: HttpsCallableOptions(timeout: _callableTimeout),
          )
          .call<dynamic>({'inviteDocId': inviteDocId});
    } on FirebaseFunctionsException catch (e) {
      if (e.message == 'invite-not-pending' ||
          e.message == 'invite-not-found') {
        throw const EmployeesFailureInviteNoLongerPending();
      }
      rethrow;
    }
  }

  @override
  Future<InvitePreview> previewInvite(String code) async {
    // No error mapping here — a thrown FirebaseFunctionsException propagates
    // raw, exactly like redeemSignupCode below. The auth layer's
    // AuthService.previewInvite is the one that knows the callable's error
    // vocabulary and maps it to AuthFailure.
    final res = await _functions
        .httpsCallable(
          'previewInvite',
          options: HttpsCallableOptions(timeout: _callableTimeout),
        )
        .call<dynamic>({'code': code});
    // Loose cast first — a callable's nested map arrives as
    // Map<dynamic, dynamic> on Android.
    final data = (res.data as Map?)?.cast<String, dynamic>();
    if (data == null) throw const EmployeesFailureUnknown();
    return InvitePreview.fromMap(data);
  }

  @override
  Future<void> redeemSignupCode(
    String code, {
    String firstName = '',
    String lastName = '',
    String phone = '',
    bool termsAccepted = false,
    bool locationConsent = false,
  }) async {
    await _functions
        .httpsCallable(
          'redeemSignupCode',
          options: HttpsCallableOptions(timeout: _callableTimeout),
        )
        // All six keys, always: the server reads the strings leniently
        // (empty == absent) and the flags as `=== true`, so a conditional
        // payload shape would be a second thing to test for no benefit.
        .call<dynamic>({
          'code': code,
          'firstName': firstName,
          'lastName': lastName,
          'phone': phone,
          'termsAccepted': termsAccepted,
          'locationConsent': locationConsent,
        });
  }

  @override
  Future<void> updateEmployee({
    required String docId,
    required EmployeeRecord employee,
  }) async {
    final normalizedEmail = employee.email.trim().toLowerCase();

    // Check uniqueness up front. This isn't atomic, but the server-side
    // invite flow is the real authority here.
    final existing = await _users
        .where('email', isEqualTo: normalizedEmail)
        .get();

    final emailUsedByAnotherEmployee = existing.docs.any(
      (doc) => doc.id != docId,
    );

    if (emailUsedByAnotherEmployee) {
      throw const EmployeesFailureEmailAlreadyExists();
    }

    final targetInQuery = existing.docs.where((doc) => doc.id == docId);
    final emailAtCheck = targetInQuery.isNotEmpty
        ? normalizedEmail
        : (await _users.doc(docId).get()).data()?['email'] as String?;

    // Field-scoped allowlist. `uid` is rejected by firestore.rules and `status`
    // belongs to deactivate/reactivate — neither may appear here regardless of
    // what the record carries.
    final updateData = <String, dynamic>{
      'name': composeEmployeeName(
        firstName: employee.firstName,
        lastName: employee.lastName,
        fallback: employee.name,
      ),
      'firstName': employee.firstName.trim(),
      'lastName': employee.lastName.trim(),
      'email': normalizedEmail,
      'phone': employee.phone.trim(),
      'colorValue': employee.color.toARGB32().toString(),
      'role': employee.role,
      'jobTitle': employee.jobTitle.raw,
      'workingDays': normalizeWorkingDays(employee.workingDays),
      'workStartMinutes': employee.workStartMinutes,
      'workEndMinutes': employee.workEndMinutes,
      'maxJobsPerDay': employee.maxJobsPerDay,
      'onCall': employee.onCall,
      // Scrub, not write: the emergency pair moved to
      // users/{docId}/private/emergency, and any value left on the parent doc
      // by a pre-move build is still readable by every active peer. Deleting
      // the keys on each save heals the fleet the way the client `mobile`
      // promotion does. Safe to send when they're already absent, and
      // `isValidUserData` passes a removed key. Drop this once no doc can
      // still carry them.
      'emergencyContact': FieldValue.delete(),
      'emergencyPhone': FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    // This is the best client-side hardening we can do: commit inside a
    // transaction that re-reads the doc and aborts if the email changed
    // since the uniqueness check — say, a concurrent admin edit.
    final ref = _users.doc(docId);
    await ref.firestore.runTransaction<void>((txn) async {
      final snapshot = await txn.get(ref);
      final currentEmail = snapshot.data()?['email'] as String?;
      if (currentEmail != emailAtCheck) {
        // Concurrent edit — surface a retryable "try again" instead of
        // committing on top of state the uniqueness check never saw.
        throw const EmployeesFailureUnknown();
      }
      txn.update(ref, updateData);
    });
  }

  /// `users/{docId}/private/emergency` — one doc, fixed id.
  DocumentReference<Map<String, dynamic>> _emergencyDoc(String docId) =>
      _users.doc(docId).collection('private').doc('emergency');

  @override
  Stream<EmergencyContact> watchEmergencyContact(String docId) {
    if (docId.isEmpty) return Stream.value(EmergencyContact.empty);
    return retryStream(
      () => _emergencyDoc(
        docId,
      ).snapshots().map((snap) => EmergencyContact.fromMap(snap.data())),
      retryWhen: _isAuthPropagationDenied,
    );
  }

  @override
  Future<void> saveEmergencyContact(
    String docId,
    EmergencyContact contact,
  ) async {
    // set(merge) rather than update(): the doc doesn't exist until the first
    // save, and update() on a missing doc throws not-found.
    await _emergencyDoc(docId).set({
      ...contact.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  @override
  Future<UserUidMatch?> findUserByUid(String uid) async {
    final result = await _users.where('uid', isEqualTo: uid).limit(1).get();
    if (result.docs.isEmpty) return null;
    final doc = result.docs.first;
    return UserUidMatch(id: doc.id, data: doc.data());
  }

  @override
  Future<void> deactivateEmployee(String docId) async {
    await _users.doc(docId).update({
      'status': 'disabled',
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> reactivateEmployee(String docId) async {
    await _users.doc(docId).update({
      'status': 'active',
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Stream<Map<String, dynamic>> watchUserDoc(String uid) {
    if (uid.isEmpty) return Stream.value(const {});
    return retryStream(
      () => _users
          .where('uid', isEqualTo: uid)
          .limit(1)
          .snapshots()
          .where((snapshot) {
            // Skip the transient empty snapshot you get from a cold cache —
            // reporting it as deleted would falsely sign the user out. An
            // authoritative empty snapshot from the server still gets
            // through, so a real deletion still gets flagged.
            return snapshot.docs.isNotEmpty || !snapshot.metadata.isFromCache;
          })
          .map((snapshot) {
            if (snapshot.docs.isEmpty) return const <String, dynamic>{};
            return snapshot.docs.first.data();
          }),
      retryWhen: _isAuthPropagationDenied,
    );
  }
}

// Twin of `_isAuthPropagationDenied` in
// `lib/features/calendar/data/firebase_appointments_repository.dart` — keep
// them in sync. Retries a permission-denied on the first users listen, since
// a freshly signed-in token can lag behind auth state; a genuine denial
// still comes through once retries are exhausted.
bool _isAuthPropagationDenied(Object error) =>
    error is FirebaseException && error.code == 'permission-denied';

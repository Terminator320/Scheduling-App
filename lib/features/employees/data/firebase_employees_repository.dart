import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import 'package:scheduling/core/utils/retry.dart';
import 'package:scheduling/features/employees/domain/employees_failure.dart';
import 'package:scheduling/features/employees/domain/employees_repository.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';

/// Shared bound on every `users` stream to prevent unbounded snapshots.
const _userStreamLimit = 500;

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
    required String email,
    required String phone,
    required String colorValue,
  }) async {
    try {
      final res = await _functions
          .httpsCallable(
            'createEmployeeInvite',
            options: HttpsCallableOptions(timeout: const Duration(seconds: 20)),
          )
          .call<dynamic>({
            'name': name.trim(),
            'email': email.trim().toLowerCase(),
            'phone': phone.trim(),
            'colorValue': colorValue,
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
  Future<void> redeemSignupCode(String code) async {
    await _functions
        .httpsCallable(
          'redeemSignupCode',
          options: HttpsCallableOptions(timeout: const Duration(seconds: 20)),
        )
        .call<dynamic>({'code': code});
  }

  @override
  Future<void> updateEmployee({
    required String docId,
    required String name,
    required String email,
    required String phone,
    required String colorValue,
    bool? isAdmin,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();

    // Pre-check uniqueness (not atomic, but server-side invite flow is authoritative).
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

    final updateData = <String, dynamic>{
      'name': name.trim(),
      'email': normalizedEmail,
      'phone': phone.trim(),
      'colorValue': colorValue,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (isAdmin != null) {
      updateData['role'] = isAdmin ? 'admin' : 'employee';
    }

    // Best-available client-side hardening: commit inside a transaction that
    // re-reads the doc and aborts if its email moved since the uniqueness
    // check (e.g. a concurrent admin edit).
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

  @override
  Future<void> deleteEmployee(String docId) async {
    await _users.doc(docId).delete();
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
            // Skip the transient empty from-cache snapshot on a cold cache —
            // reporting it as deleted would falsely sign the user out; an
            // authoritative empty from the server still passes through to flag
            // a real deletion.
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
// `lib/features/calendar/data/firebase_appointments_repository.dart` (keep in
// sync): retries a permission-denied on the first users listen, since a
// freshly signed-in token can lag auth state — a genuine denial still
// surfaces after retrying.
bool _isAuthPropagationDenied(Object error) =>
    error is FirebaseException && error.code == 'permission-denied';

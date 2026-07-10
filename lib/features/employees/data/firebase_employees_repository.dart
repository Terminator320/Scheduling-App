import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import 'package:scheduling/core/utils/retry.dart';
import 'package:scheduling/features/employees/domain/employees_failure.dart';
import 'package:scheduling/features/employees/domain/employees_repository.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';

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
          .limit(500)
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
          // Bounded like watchAllUsers so a runaway users collection can't
          // stream an unbounded snapshot to every client.
          .limit(500)
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
          .httpsCallable('createEmployeeInvite')
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
    await _functions.httpsCallable('redeemSignupCode').call<dynamic>({
      'code': code,
    });
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

    // Uniqueness pre-check. The Firestore client SDK cannot run queries inside
    // a transaction, so this read-then-write is not atomic: another doc could
    // claim [normalizedEmail] between this query and the commit below. That
    // residual race is accepted client-side — the server-side invite flow
    // (functions/createEmployeeInvite) is the authoritative uniqueness guard.
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
    // re-reads the target doc and aborts when its email moved underneath the
    // uniqueness check (e.g. another admin edited the same employee
    // concurrently), so this write can't silently overwrite it with a value
    // that was never re-validated.
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
            // Skip the transient empty from-cache snapshot that precedes the
            // server result on a cold cache. Reporting it as an empty (deleted)
            // doc would falsely sign the user out and stop the role from
            // upgrading past the cached employee guess. An authoritative empty
            // (from the server) still passes through to flag a real deletion.
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
// `lib/features/calendar/data/firebase_appointments_repository.dart` — keep in
// sync. A freshly signed-in user's ID token and `usersByUid` role bridge can
// lag the auth state, so the first users listen comes back permission-denied
// even though the read is authorized. Without the retry, one such error
// permanently breaks role upgrades and disable/delete detection for the
// session. Re-subscribing after a short delay succeeds; a genuine denial
// survives every retry and surfaces as before.
bool _isAuthPropagationDenied(Object error) =>
    error is FirebaseException && error.code == 'permission-denied';

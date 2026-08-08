import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import 'package:scheduling/core/utils/retry.dart';
import 'package:scheduling/features/employees/domain/employees_failure.dart';
import 'package:scheduling/features/employees/domain/employees_repository.dart';
import 'package:scheduling/features/employees/domain/models/emergency_contact.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';
import 'package:scheduling/features/employees/domain/models/new_account_credentials.dart';
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
      retryWhen: isAuthPropagationDenied,
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
      retryWhen: isAuthPropagationDenied,
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
      retryWhen: isAuthPropagationDenied,
    );
  }

  @override
  Future<NewAccountCredentials> createEmployeeAccount({
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
            'createEmployeeAccount',
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
      if (data == null) throw const EmployeesFailureUnknown();
      final credentials = NewAccountCredentials.fromMap(data);
      // A blank half is unusable to the admin and would render an empty
      // credential dialog — fail loudly instead of showing nothing.
      if (!credentials.isComplete) throw const EmployeesFailureUnknown();
      return credentials;
    } on FirebaseFunctionsException catch (e) {
      if (e.message == 'email-exists') {
        throw const EmployeesFailureEmailAlreadyExists();
      }
      rethrow;
    }
  }

  @override
  Future<void> deleteEmployeeAccount(String docId) async {
    try {
      await _functions
          .httpsCallable(
            'deleteEmployeeAccount',
            options: HttpsCallableOptions(timeout: _callableTimeout),
          )
          .call<dynamic>({'docId': docId});
    } on FirebaseFunctionsException catch (e) {
      if (e.message == 'account-not-pending' ||
          e.message == 'account-not-found') {
        throw const EmployeesFailureAccountNoLongerPending();
      }
      rethrow;
    }
  }

  @override
  Future<void> completeEmployeeSetup({
    String firstName = '',
    String lastName = '',
    String phone = '',
    bool termsAccepted = false,
    bool locationConsent = false,
  }) async {
    await _functions
        .httpsCallable(
          'completeEmployeeSetup',
          options: HttpsCallableOptions(timeout: _callableTimeout),
        )
        // All five keys, always: the server reads the strings leniently
        // (empty == absent) and the flags as `=== true`, so a conditional
        // payload shape would be a second thing to test for no benefit.
        .call<dynamic>({
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
    final ref = _users.doc(docId);
    final stored = (await ref.get()).data();
    final storedEmail = stored?['email'] as String? ?? '';
    final storedUid = stored?['uid'] as String? ?? '';

    // What we believe the doc holds going into the commit below.
    var emailAtCheck = storedEmail;

    if (normalizedEmail != storedEmail) {
      if (storedUid.isEmpty) {
        // No Auth account behind this doc, so the email is ours to write.
        // Uniqueness isn't atomic here; the transaction below re-checks.
        final existing = await _users
            .where('email', isEqualTo: normalizedEmail)
            .get();
        if (existing.docs.any((doc) => doc.id != docId)) {
          throw const EmployeesFailureEmailAlreadyExists();
        }
      } else {
        // The sign-in identity moves through the callable, which owns BOTH
        // stores. It runs FIRST and the write below merely re-states what it
        // committed — the reverse order is the bug this closes: a
        // Firestore-only change leaves the person signing in at the old
        // address while every admin surface shows the new one.
        await _changeAuthEmail(docId: docId, email: normalizedEmail);
        emailAtCheck = normalizedEmail;
      }
    }

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
    await ref.firestore.runTransaction<void>((txn) async {
      final snapshot = await txn.get(ref);
      // Same `?? ''` normalization the pre-flight read uses: a doc with no
      // `email` field reads as null here and would never equal the `''` the
      // check above settled on, so the guard would abort EVERY save on such a
      // doc rather than only a concurrent one.
      final currentEmail = (snapshot.data()?['email'] as String?) ?? '';
      if (currentEmail != emailAtCheck) {
        // Concurrent edit — surface a retryable "try again" instead of
        // committing on top of state the uniqueness check never saw.
        throw const EmployeesFailureUnknown();
      }
      txn.update(ref, updateData);
    });
  }

  /// Moves the sign-in email in Firebase Auth AND on the users doc.
  ///
  /// Private on purpose: `updateEmployee` is the only caller, so "an email edit
  /// always moves both stores" is a property of the save path rather than a
  /// second method a call site could forget to pair with it.
  Future<void> _changeAuthEmail({
    required String docId,
    required String email,
  }) async {
    try {
      await _functions
          .httpsCallable(
            'changeEmployeeEmail',
            options: HttpsCallableOptions(timeout: _callableTimeout),
          )
          .call<dynamic>({'docId': docId, 'email': email});
    } on FirebaseFunctionsException catch (e) {
      if (e.message == 'email-exists') {
        throw const EmployeesFailureEmailAlreadyExists();
      }
      // A concurrent admin edit landed between our read and the commit. Same
      // "try again" the local transaction guard raises for the same race.
      if (e.message == 'email-changed') {
        throw const EmployeesFailureUnknown();
      }
      rethrow;
    }
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
      retryWhen: isAuthPropagationDenied,
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

  /// Memo of the doc id [watchUserDoc] resolved, keyed by the uid it was for.
  /// See [cachedUserDocId].
  String? _cachedUserDocId;
  String? _cachedUserDocUid;

  @override
  String? cachedUserDocId(String uid) =>
      _cachedUserDocUid == uid ? _cachedUserDocId : null;

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
            // Remember the id this snapshot already carries. Without it,
            // activeUserIdentityProvider re-queried the same doc by uid on
            // every emission purely to learn something this stream had.
            _cachedUserDocUid = uid;
            _cachedUserDocId = snapshot.docs.first.id;
            return snapshot.docs.first.data();
          }),
      retryWhen: isAuthPropagationDenied,
    );
  }
}

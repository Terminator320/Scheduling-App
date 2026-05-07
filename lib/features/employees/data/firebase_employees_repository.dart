import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

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
    return _users
        .orderBy('name')
        .limit(500)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => EmployeeRecord.fromMap(doc.id, doc.data()))
              .toList(),
        );
  }

  @override
  Stream<List<EmployeeRecord>> watchEmployees() {
    return _users
        .where('role', whereIn: ['employee', 'admin'])
        .where('status', isEqualTo: 'active')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => EmployeeRecord.fromMap(doc.id, doc.data()))
              .toList(),
        );
  }

  @override
  Stream<List<EmployeeRecord>> watchAssignableUsers() {
    return _users
        .where('status', isEqualTo: 'active')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => EmployeeRecord.fromMap(doc.id, doc.data()))
              .toList(),
        );
  }

  @override
  Future<EmployeeRecord?> getEmployeeById(String docId) async {
    final doc = await _users.doc(docId).get();
    if (!doc.exists) return null;
    return EmployeeRecord.fromMap(doc.id, doc.data() ?? {});
  }

  @override
  Future<void> addEmployee({
    required String name,
    required String email,
    required String phone,
    required String colorValue,
    required bool isAdmin,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();

    final existing = await _users
        .where('email', isEqualTo: normalizedEmail)
        .limit(1)
        .get();

    if (existing.docs.isNotEmpty) {
      throw const EmployeesFailureEmailAlreadyExists();
    }

    await _users.add({
      'name': name.trim(),
      'email': normalizedEmail,
      'phone': phone.trim(),
      'role': isAdmin ? 'admin' : 'employee',
      'status': 'invited',
      'uid': '',
      'colorValue': colorValue,
      'createdAt': FieldValue.serverTimestamp(),
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

    final existing = await _users
        .where('email', isEqualTo: normalizedEmail)
        .get();

    final emailUsedByAnotherEmployee = existing.docs.any(
      (doc) => doc.id != docId,
    );

    if (emailUsedByAnotherEmployee) {
      throw const EmployeesFailureEmailAlreadyExists();
    }

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

    await _users.doc(docId).update(updateData);
  }

  @override
  Future<void> deleteEmployee(String docId) async {
    await _users.doc(docId).delete();
  }

  @override
  Future<InvitedEmployeeMatch?> findInvitedEmployeeForCurrentUser() async {
    final response = await _functions
        .httpsCallable('resolveMyInvite')
        .call<dynamic>();
    final payload = (response.data as Map?)?.cast<String, dynamic>();
    if (payload == null || payload['found'] != true) return null;
    final docId = payload['docId'] as String?;
    final data = (payload['data'] as Map?)?.cast<String, dynamic>();
    if (docId == null || data == null) return null;
    return InvitedEmployeeMatch(docId: docId, data: data);
  }

  @override
  Future<UserUidMatch?> findUserByUid(String uid) async {
    final result = await _users.where('uid', isEqualTo: uid).limit(1).get();
    if (result.docs.isEmpty) return null;
    final doc = result.docs.first;
    return UserUidMatch(id: doc.id, data: doc.data());
  }

  @override
  Future<void> activateEmployee({
    required String docId,
    required String uid,
  }) async {
    await _users.doc(docId).update({
      'uid': uid,
      'status': 'active',
      'updatedAt': FieldValue.serverTimestamp(),
    });
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
    return _users
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
        });
  }
}

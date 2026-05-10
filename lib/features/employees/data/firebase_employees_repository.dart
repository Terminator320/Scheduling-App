import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:scheduling/features/employees/domain/employees_repository.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';

class FirebaseEmployeesRepository implements EmployeesRepository {
  FirebaseEmployeesRepository(
    FirebaseFirestore firestore, {
    FirebaseAuth? auth,
  }) : _users = firestore.collection('users'),
       _auth = auth ?? FirebaseAuth.instance;

  final CollectionReference<Map<String, dynamic>> _users;
  final FirebaseAuth _auth;

  @override
  Stream<List<EmployeeRecord>> watchAllUsers() {
    return _users
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
      throw Exception('Employee email already exists');
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
      throw Exception('Employee email already exists');
    }

    final updateData = <String, dynamic>{
      'name': name.trim(),
      'email': normalizedEmail,
      'phone': phone.trim(),
      'colorValue': colorValue,
    };

    if (isAdmin != null) {
      updateData['role'] = isAdmin == true ? 'admin' : 'employee';
    }

    await _users.doc(docId).update(updateData);
  }

  @override
  Future<void> deleteEmployee(String docId) async {
    await _users.doc(docId).delete();
  }

  @override
  Future<InvitedEmployeeMatch?> findInvitedEmployeeByEmail(String email) async {
    final normalizedEmail = email.trim().toLowerCase();

    final result = await _users
        .where('email', isEqualTo: normalizedEmail)
        .where('role', isEqualTo: 'employee')
        .where('status', isEqualTo: 'invited')
        .limit(1)
        .get();

    if (result.docs.isEmpty) return null;
    final doc = result.docs.first;
    return InvitedEmployeeMatch(docId: doc.id, data: doc.data());
  }

  @override
  Future<UserUidMatch?> findUserByUid(String uid) async {
    final result = await _users.where('uid', isEqualTo: uid).limit(1).get();
    if (result.docs.isEmpty) return null;
    final doc = result.docs.first;
    return UserUidMatch(id: doc.id, data: doc.data());
  }

  @override
  Future<bool> isUserAdmin(String uid) async {
    if (uid.isEmpty) return false;
    final match = await findUserByUid(uid);
    if (match == null) return false;
    return (match.data['role'] ?? '') == 'admin';
  }

  @override
  Future<void> activateEmployee({
    required String docId,
    required String uid,
  }) async {
    await _users.doc(docId).update({'uid': uid, 'status': 'active'});
  }

  @override
  Future<void> deactivateEmployee(String docId) async {
    await _users.doc(docId).update({'status': 'disabled'});
  }

  @override
  Future<void> reactivateEmployee(String docId) async {
    await _users.doc(docId).update({'status': 'active'});
  }

  @override
  Stream<String> loggedInUserNameStream() {
    final user = _auth.currentUser;
    if (user == null) return Stream.value('');

    return _users
        .where('uid', isEqualTo: user.uid)
        .limit(1)
        .snapshots()
        .map((snapshot) {
          if (snapshot.docs.isEmpty) return '';
          final data = snapshot.docs.first.data();
          return (data['name'] ?? '').toString().trim();
        });
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/employee_record.dart';

class UserService {
  static final CollectionReference<Map<String, dynamic>> _users =
  FirebaseFirestore.instance.collection('users');

  static Future<void> addEmployee({
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
      'role': 'employee',
      'status': 'invited',
      'isAdmin': isAdmin,
      'uid': '',
      'colorValue': colorValue,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  static Stream<List<EmployeeRecord>> employeesStream() {
    return _users.where('role', isEqualTo: 'employee').snapshots().map(
          (snapshot) {
        return snapshot.docs
            .map((doc) => EmployeeRecord.fromMap(doc.id, doc.data()))
            .toList();
      },
    );
  }

  static Future<void> updateEmployee({
    required String docId,
    required String name,
    required String email,
    required String phone,
    required String colorValue,
    bool? isAdmin,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();

    final existing =
    await _users.where('email', isEqualTo: normalizedEmail).get();

    final emailUsedByAnotherEmployee =
    existing.docs.any((doc) => doc.id != docId);

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
      updateData['isAdmin'] = isAdmin;
    }

    await _users.doc(docId).update(updateData);
  }

  static Future<void> deleteEmployee(String docId) async {
    await _users.doc(docId).delete();
  }

  static Future<QueryDocumentSnapshot<Map<String, dynamic>>?>
  findInvitedEmployeeByEmail(String email) async {
    final normalizedEmail = email.trim().toLowerCase();

    final result = await _users
        .where('email', isEqualTo: normalizedEmail)
        .where('role', isEqualTo: 'employee')
        .where('status', isEqualTo: 'invited')
        .limit(1)
        .get();

    if (result.docs.isEmpty) return null;
    return result.docs.first;
  }

  static Future<QueryDocumentSnapshot<Map<String, dynamic>>?> findUserByUid(
      String uid,
      ) async {
    final result = await _users.where('uid', isEqualTo: uid).limit(1).get();

    if (result.docs.isEmpty) return null;
    return result.docs.first;
  }

  static Future<bool> canGrantAdminForUid(String uid) async {
    if (uid.isEmpty) return false;

    final userDoc = await findUserByUid(uid);
    if (userDoc == null) return false;

    final data = userDoc.data();
    return (data['role'] ?? '').toString() == 'admin';
  }

  static Future<void> activateEmployee({
    required String docId,
    required String uid,
  }) async {
    await _users.doc(docId).update({
      'uid': uid,
      'status': 'active',
    });
  }

  static Stream<String> loggedInUserNameStream() {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return Stream.value('User');
    }

    return _users.where('uid', isEqualTo: user.uid).limit(1).snapshots().map(
          (snapshot) {
        if (snapshot.docs.isEmpty) return 'User';

        final data = snapshot.docs.first.data();
        final name = (data['name'] ?? '').toString().trim();

        return name.isNotEmpty ? name : 'User';
      },
    );
  }
}
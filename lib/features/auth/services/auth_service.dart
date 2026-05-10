import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:scheduling/core/services/user_cache_service.dart';
import 'package:scheduling/features/employees/data/firebase_employees_repository.dart';
import 'package:scheduling/features/employees/domain/employees_repository.dart';

class AuthService {
  // Optional injection allows tests to pass fakes without hitting Firebase.
  AuthService({
    FirebaseAuth? firebaseAuth,
    EmployeesRepository? employeesRepository,
  }) : _auth = firebaseAuth ?? FirebaseAuth.instance,
       _employees =
           employeesRepository ??
           FirebaseEmployeesRepository(FirebaseFirestore.instance);

  final FirebaseAuth _auth;
  final EmployeesRepository _employees;

  User? get currentUser => _auth.currentUser;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  Future<UserCredential> signIn({
    required String email,
    required String password,
  }) {
    return _auth.signInWithEmailAndPassword(
      email: email.trim().toLowerCase(),
      password: password.trim(),
    );
  }

  Future<UserCredential> register({
    required String email,
    required String password,
  }) {
    return _auth.createUserWithEmailAndPassword(
      email: email.trim().toLowerCase(),
      password: password.trim(),
    );
  }

  Future<void> sendPasswordResetEmail(String email) {
    return _auth.sendPasswordResetEmail(email: email.trim().toLowerCase());
  }

  // Kept for backwards compatibility with existing call sites.
  Future<void> sendResetPassword(String email) {
    return sendPasswordResetEmail(email);
  }

  Future<UserCredential> createEmployeeAccount({
    required String email,
    required String password,
  }) async {
    final invitedEmployee = await _employees.findInvitedEmployeeByEmail(email);

    // Employees must be pre-invited by an admin; reject unknown emails up front.
    if (invitedEmployee == null) {
      throw FirebaseAuthException(
        code: 'not-authorized',
        message: 'This email was not added by the admin.',
      );
    }

    final credential = await register(
      email: email.trim().toLowerCase(),
      password: password.trim(),
    );

    await _employees.activateEmployee(
      docId: invitedEmployee.docId,
      uid: credential.user!.uid,
    );

    return credential;
  }

  Future<void> signOut() async {
    await UserCacheService().clear();
    await _auth.signOut();
  }
}

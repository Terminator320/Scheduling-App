import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:scheduling/features/auth/data/auth_cache.dart';
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
    // /users is gated by isSignedIn() — register first, look up the invite
    // after auth, and roll back the auth account if no invite is found so it
    // doesn't orphan and block re-signup with the same email.
    final credential = await register(
      email: email.trim().toLowerCase(),
      password: password.trim(),
    );

    InvitedEmployeeMatch? invitedEmployee;
    try {
      invitedEmployee = await _employees.findInvitedEmployeeByEmail(email);
    } catch (e) {
      await credential.user?.delete();
      rethrow;
    }

    if (invitedEmployee == null) {
      await credential.user?.delete();
      throw FirebaseAuthException(
        code: 'not-authorized',
        message: 'This email was not added by the admin.',
      );
    }

    await _employees.activateEmployee(
      docId: invitedEmployee.docId,
      uid: credential.user!.uid,
    );

    return credential;
  }

  Future<void> signOut() async {
    // Sign out remote first; the local cache is only useful when it matches a
    // signed-in `uid`, so clearing it unconditionally in `finally` is safe and
    // prevents a desynced "no remote user, cached uid" state on next launch.
    try {
      await _auth.signOut();
    } finally {
      await AuthCache().clear();
    }
  }
}

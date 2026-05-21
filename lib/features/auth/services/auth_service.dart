import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/features/auth/data/auth_cache.dart';
import 'package:scheduling/features/auth/domain/auth_failure.dart';
import 'package:scheduling/features/employees/data/firebase_employees_repository.dart';
import 'package:scheduling/features/employees/domain/employees_repository.dart';

class AuthService {
  AuthService({
    FirebaseAuth? firebaseAuth,
    EmployeesRepository? employeesRepository,
    AppLogger? logger,
  }) : _auth = firebaseAuth ?? FirebaseAuth.instance,
       _employees =
           employeesRepository ??
           FirebaseEmployeesRepository(FirebaseFirestore.instance),
       _logger = logger ?? AppLogger();

  final FirebaseAuth _auth;
  final EmployeesRepository _employees;
  final AppLogger _logger;

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

  Future<UserCredential> createEmployeeAccount({
    required String email,
    required String password,
  }) async {
    final credential = await register(
      email: email.trim().toLowerCase(),
      password: password.trim(),
    );

    InvitedEmployeeMatch? invitedEmployee;
    try {
      invitedEmployee = await _employees.findInvitedEmployeeByEmail(email);
    } catch (e, st) {
      // TODO(pre-ship): remove once signup failures on release APK are diagnosed.
      _logger.warn(
        'createEmployeeAccount: findInvitedEmployeeByEmail failed',
        e,
        st,
      );
      await _rollbackOrFailLoud(credential, reason: 'invite-lookup-failed');
      rethrow;
    }

    if (invitedEmployee == null) {
      await _rollbackOrFailLoud(credential, reason: 'no-invite-found');
      throw const AuthFailureNotAuthorized();
    }

    await credential.user!.sendEmailVerification();

    return credential;
  }

  // Best-effort cleanup of the Auth user we just registered. When this delete
  // fails (App Check hiccup, network blip, requires-recent-login edge case)
  // the user is left orphaned: an Auth identity with no Firestore users doc
  // backing it, which blocks future Create-Account attempts with the same
  // email. Log the failure so Crashlytics surfaces it, and throw a distinct
  // failure so the UI tells the admin how to recover.
  Future<void> _rollbackOrFailLoud(
    UserCredential credential, {
    required String reason,
  }) async {
    final user = credential.user;
    if (user == null) return;
    try {
      await user.delete();
    } catch (e, st) {
      _logger.warn(
        'createEmployeeAccount: rollback delete failed ($reason); '
        'orphan Auth user left for uid=${user.uid}',
        e,
        st,
      );
      throw const AuthFailureAccountCreationIncomplete();
    }
  }

  Future<void> tryActivateInvitedEmployee(User user) async {
    await user.reload();
    if (!user.emailVerified) return;
    final email = user.email;
    if (email == null) return;
    final invite = await _employees.findInvitedEmployeeByEmail(email);
    if (invite == null) return;
    await _employees.activateEmployee(docId: invite.docId, uid: user.uid);
  }

  Future<void> signOut() async {
    try {
      await _auth.signOut();
    } finally {
      await AuthCache().clear();
    }
  }
}

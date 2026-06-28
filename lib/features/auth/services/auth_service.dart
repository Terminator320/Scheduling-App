import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
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
    AuthCache? authCache,
    AppLogger? logger,
  }) : _auth = firebaseAuth ?? FirebaseAuth.instance,
       _employees =
           employeesRepository ??
           FirebaseEmployeesRepository(FirebaseFirestore.instance),
       _authCache = authCache ?? AuthCache(),
       _logger = logger ?? AppLogger();

  final FirebaseAuth _auth;
  final EmployeesRepository _employees;
  final AuthCache _authCache;
  final AppLogger _logger;

  User? get currentUser => _auth.currentUser;

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

  /// Invited-employee signup. Registers (or adopts an existing account), then
  /// redeems the admin-issued one-time code, which activates the account
  /// server-side. On redemption failure the freshly-created Auth user is rolled
  /// back so no orphan is left.
  Future<void> signUpWithCode({
    required String email,
    required String password,
    required String code,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    UserCredential credential;
    var freshlyCreated = true;
    try {
      credential = await register(email: normalizedEmail, password: password);
    } on FirebaseAuthException catch (e) {
      if (e.code != 'email-already-in-use') rethrow;
      credential = await signIn(email: normalizedEmail, password: password);
      freshlyCreated = false;
    }

    try {
      await _employees.redeemSignupCode(code.trim());
    } catch (e, st) {
      _logger.warn('signUpWithCode: redeemSignupCode failed', e, st);
      final failure = _mapRedemptionError(e);
      if (freshlyCreated) {
        await _rollbackOrFailLoud(
          credential,
          email: normalizedEmail,
          password: password,
          reason: 'code-redemption-failed',
        );
      } else {
        await _signOutQuietly();
      }
      throw failure;
    }
  }

  AuthFailure _mapRedemptionError(Object e) {
    if (e is FirebaseFunctionsException) {
      switch (e.message) {
        case 'code-expired':
          return const AuthFailureSignupCodeExpired();
        case 'code-email-mismatch':
          return const AuthFailureSignupEmailMismatch();
        case 'invalid-code':
          return const AuthFailureInvalidSignupCode();
      }
      if (e.code == 'resource-exhausted') {
        return const AuthFailureTooManyRequests();
      }
      if (e.code == 'unavailable' || e.code == 'deadline-exceeded') {
        return const AuthFailureNetwork();
      }
    }
    return const AuthFailureUnknown();
  }

  // Cleanup of the Auth user we just created. The global account guard signs
  // out any signed-in user with no Firestore users doc (which is exactly this
  // half-created user before redemption), so by the time we get here
  // `currentUser` is often already null and a plain `user.delete()` throws
  // `no-current-user`, leaving an orphan. We re-authenticate with the same
  // credentials before deleting so the cleanup actually lands. If it still
  // fails, sign out, log the orphan for Crashlytics, and throw a distinct
  // failure so the UI tells the admin how to recover.
  Future<void> _rollbackOrFailLoud(
    UserCredential credential, {
    required String email,
    required String password,
    required String reason,
  }) async {
    try {
      await _deleteFreshlyCreatedUser(
        credential: credential,
        email: email,
        password: password,
      );
    } catch (e, st) {
      final uid = _auth.currentUser?.uid ?? credential.user?.uid;
      _logger.warn(
        'signUpWithCode: rollback delete failed ($reason); '
        'orphan Auth user left for uid=$uid',
        e,
        st,
      );
      await _signOutQuietly();
      throw const AuthFailureAccountCreationIncomplete();
    }
  }

  // Deletes the just-created user, re-authenticating first when the session was
  // already torn down (current user null) or the delete needs a recent login.
  Future<void> _deleteFreshlyCreatedUser({
    required UserCredential credential,
    required String email,
    required String password,
  }) async {
    var user = _auth.currentUser ?? credential.user;
    if (_auth.currentUser == null) {
      user = (await signIn(email: email, password: password)).user;
    }
    if (user == null) return;
    try {
      await user.delete();
    } on FirebaseAuthException catch (e) {
      if (e.code != 'requires-recent-login' && e.code != 'no-current-user') {
        rethrow;
      }
      final reauthed = (await signIn(email: email, password: password)).user;
      await reauthed?.delete();
    }
  }

  Future<void> _signOutQuietly() async {
    try {
      await _auth.signOut();
    } catch (_) {}
  }

  Future<void> signOut() async {
    try {
      await _auth.signOut();
    } finally {
      await _authCache.clear();
    }
  }
}

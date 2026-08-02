import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/core/providers/firebase_providers.dart';
import 'package:scheduling/features/auth/data/auth_cache.dart';
import 'package:scheduling/features/auth/domain/auth_failure.dart';
import 'package:scheduling/features/employees/application/employees_providers.dart';
import 'package:scheduling/features/employees/data/firebase_employees_repository.dart';
import 'package:scheduling/features/employees/domain/employees_repository.dart';

/// App-wide [AuthService], wired through providers for testability.
final authServiceProvider = Provider<AuthService>(
  (ref) => AuthService(
    firebaseAuth: ref.watch(firebaseAuthProvider),
    employeesRepository: ref.watch(employeesRepositoryProvider),
    authCache: ref.watch(authCacheProvider),
    logger: ref.watch(loggerProvider),
  ),
);

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

  /// Completes the signed-in employee's own account setup.
  ///
  /// ORDER IS THE GUARANTEE. The password is replaced FIRST, then the account
  /// is activated. The server cannot see a password, so "you must replace the
  /// shared default" is true only because activation is refused until this
  /// method gets past [User.updatePassword]. Swap the two and an interrupted
  /// setup leaves an active account still on the default password.
  ///
  /// A failure after the password change is safe: the account stays `invited`,
  /// so the next sign-in routes back here and simply asks again — the screen
  /// never assumes the current password is still the default.
  Future<void> completeAccountSetup({
    required String newPassword,
    String firstName = '',
    String lastName = '',
    String phone = '',
    bool termsAccepted = false,
    bool locationConsent = false,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw const AuthFailureSessionExpired();

    try {
      await user.updatePassword(newPassword.trim());
    } catch (e, st) {
      final failure = _mapSetupError(e);
      _logger.authFailure(
        'completeAccountSetup: updatePassword failed',
        failure,
        e,
        st,
      );
      throw failure;
    }

    try {
      await _employees.completeEmployeeSetup(
        firstName: firstName.trim(),
        lastName: lastName.trim(),
        phone: phone.trim(),
        termsAccepted: termsAccepted,
        locationConsent: locationConsent,
      );
    } catch (e, st) {
      final failure = _mapSetupError(e);
      // No rollback of the password change: the new password is the one the
      // person just chose and typed twice. Reverting it to the shared default
      // would be strictly worse than leaving them `invited` with a password
      // that works.
      _logger.authFailure(
        'completeAccountSetup: completeEmployeeSetup failed',
        failure,
        e,
        st,
      );
      throw failure;
    }
  }

  AuthFailure _mapSetupError(Object e) {
    if (e is FirebaseAuthException) {
      switch (e.code) {
        case 'weak-password':
          return const AuthFailureWeakPassword();
        case 'requires-recent-login':
        case 'user-token-expired':
        case 'user-not-found':
          return const AuthFailureSessionExpired();
        case 'network-request-failed':
          return const AuthFailureNetwork();
      }
    }
    if (e is FirebaseFunctionsException) {
      // The account was already activated — a replayed call, or two devices
      // finishing setup at once. The password change above still landed, so
      // this is not something to make the person fix.
      if (e.message == 'setup-not-pending') {
        return const AuthFailureSetupAlreadyComplete();
      }
      if (e.message == 'account-not-found') {
        return const AuthFailureNoAccountRecord();
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

  Future<void> _signOutQuietly() async {
    try {
      await _auth.signOut();
    } catch (e, st) {
      _logger.warn('signUp rollback: quiet signOut failed', e, st);
    }
  }

  Future<void> signOut() async {
    try {
      await _auth.signOut();
    } finally {
      // Best-effort cache clear — if the keystore fails here it shouldn't fail
      // signOut too, since we check the cached uid again on next launch.
      try {
        await _authCache.clear();
      } catch (e, st) {
        _logger.warn('signOut: auth cache clear failed', e, st);
      }
    }
  }
}

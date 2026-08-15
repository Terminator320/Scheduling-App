import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/core/providers/firebase_providers.dart';
import 'package:scheduling/core/validators/email_format.dart';
import 'package:scheduling/features/auth/data/auth_cache.dart';
import 'package:scheduling/features/auth/data/auth_error_mapper.dart';
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
      email: normalizeEmail(email),
      password: password.trim(),
    );
  }

  Future<void> sendPasswordResetEmail(String email) {
    return _auth.sendPasswordResetEmail(email: normalizeEmail(email));
  }

  /// Whether the signed-in address has been verified.
  ///
  /// Load-bearing during setup: the account is minted on a SHARED starting
  /// password, so signing in proves nothing about who you are.
  /// `completeEmployeeSetup` refuses without a verified email, which is what
  /// keeps a stranger who knows the address stuck on the setup screen instead
  /// of activating the account and leaving the `invited` state (where the
  /// rules grant nothing).
  bool get isEmailVerified => _auth.currentUser?.emailVerified ?? false;

  /// Sends Firebase's own verification email to the signed-in address.
  Future<void> sendVerificationEmail() async {
    final user = _auth.currentUser;
    if (user == null) throw const AuthFailureSessionExpired();
    try {
      await user.sendEmailVerification();
    } catch (e, st) {
      final failure = _mapSetupError(e);
      _logger.authFailure(
        'sendVerificationEmail failed',
        failure,
        e,
        st,
      );
      throw failure;
    }
  }

  /// Re-reads the account and, once verified, forces a fresh ID token.
  ///
  /// The token refresh is the half that matters: `completeEmployeeSetup` reads
  /// `email_verified` off the **token**, which was minted at sign-in. A bare
  /// [User.reload] updates the local object and leaves the callable still
  /// seeing `false`, so setup would keep failing after the person had done
  /// everything right.
  Future<bool> refreshEmailVerified() async {
    final user = _auth.currentUser;
    if (user == null) return false;
    await user.reload();
    final refreshed = _auth.currentUser;
    if (refreshed == null || !refreshed.emailVerified) return false;
    await refreshed.getIdToken(true);
    return true;
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

  /// Only the codes whose meaning CHANGES during setup are handled here;
  /// everything else falls through to the shared [AuthErrorMapper] rather than
  /// being re-tabulated. A second copy of that table would silently bucket any
  /// code it forgot into `AuthFailureUnknown`, which is `isExpected: false` and
  /// so files a Crashlytics non-fatal for an ordinary user mistake.
  AuthFailure _mapSetupError(Object e) {
    if (e is FirebaseAuthException) {
      switch (e.code) {
        // The shared mapper calls these "requires recent login" / "no such
        // user"; mid-setup they all mean the same thing to the person, which
        // is that the session backing this screen is gone.
        case 'requires-recent-login':
        case 'user-token-expired':
        case 'user-not-found':
          return const AuthFailureSessionExpired();
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
      // The screen gates on this before submitting, so reaching it means the
      // token still carried the pre-verification claim — which the "Check
      // again" action fixes by forcing a refresh.
      if (e.message == 'email-not-verified') {
        return const AuthFailureEmailNotVerified();
      }
      if (e.code == 'resource-exhausted') {
        return const AuthFailureTooManyRequests();
      }
      if (e.code == 'unavailable' || e.code == 'deadline-exceeded') {
        return const AuthFailureNetwork();
      }
    }
    return AuthErrorMapper.map(e);
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
        _logger.warn('ACCT-SIGNOUT auth cache clear failed', e, st);
      }
    }
  }
}

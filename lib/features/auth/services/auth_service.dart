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

  /// Completes the signed-in employee's own account setup.
  ///
  /// ORDER IS THE GUARANTEE. The password is replaced FIRST, then the account
  /// is activated. The server cannot see a password, so "you must replace the
  /// starting password" is true only because activation is refused until this
  /// method gets past [User.updatePassword]. Swap the two and an interrupted
  /// setup leaves an active account still on the starting password the admin
  /// read out.
  ///
  /// A failure after the password change is safe: the account stays `invited`,
  /// so the next sign-in routes back here and simply asks again — the screen
  /// never assumes the current password is still the starting one.
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

    await _refuseIfStillTheStartingPassword(user, newPassword.trim());

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
      // person just chose and typed twice. Reverting it to the generated
      // starting password would be strictly worse than leaving them `invited`
      // with a password that works.
      _logger.authFailure(
        'completeAccountSetup: completeEmployeeSetup failed',
        failure,
        e,
        st,
      );
      throw failure;
    }
  }

  /// Refuses a "new" password that is the one the admin issued.
  ///
  /// The client never sees the generated starting password, so it cannot be
  /// compared as a string — but it can be TESTED: reauthenticating with the
  /// typed value succeeds only while that value is still the account's current
  /// credential. Success therefore means they retyped what they were given.
  ///
  /// Without this, setup completes on an unchanged password and the account
  /// goes `active` on a credential the admin (and anyone they read it aloud to)
  /// still holds. Every generated password satisfies the setup validator by
  /// construction — 12 characters with an uppercase, a lowercase and a digit is
  /// exactly `PasswordRequirement.allMetBy` now that `symbol` is gone — so
  /// nothing else on this screen can catch it. It replaces the deleted
  /// `kDefaultStartingPassword` comparison, which only worked while the
  /// starting password was a shared constant.
  ///
  /// Checked HERE rather than on the screen so it covers both routes into
  /// setup: sign-in (which holds the typed password) and a cold start through
  /// `SplashScreen` (which does not).
  ///
  /// A wrong-password refusal is the PASS case. Anything else is a real
  /// failure and is mapped normally — never swallowed into "looks different",
  /// which would let the case this exists for through whenever the network
  /// hiccuped.
  Future<void> _refuseIfStillTheStartingPassword(
    User user,
    String candidate,
  ) async {
    final email = user.email;
    if (email == null || email.isEmpty) return;
    try {
      await user.reauthenticateWithCredential(
        EmailAuthProvider.credential(email: email, password: candidate),
      );
    } on FirebaseAuthException catch (e) {
      if (_isWrongPasswordCode(e.code)) return;
      final failure = _mapSetupError(e);
      _logger.authFailure(
        'completeAccountSetup: starting-password check failed',
        failure,
        e,
        StackTrace.current,
      );
      throw failure;
    }
    // Reauth SUCCEEDED, so the password is unchanged.
    const failure = AuthFailureStartingPasswordReused();
    _logger.breadcrumb(
      'completeAccountSetup: refused the starting password '
      '(${failure.runtimeType})',
    );
    throw failure;
  }

  /// The codes Firebase uses for "that password is not this account's".
  /// `invalid-credential` is the modern umbrella code and is what current
  /// Identity Platform returns; the other two still arrive from older SDK
  /// paths. Missing one would turn the pass case into a hard failure that
  /// blocks setup entirely, so all three are listed.
  static bool _isWrongPasswordCode(String code) =>
      code == 'wrong-password' ||
      code == 'invalid-credential' ||
      code == 'invalid-login-credentials';

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
      // Old-backend compatibility, and ONLY that: the guard was removed
      // 2026-08-21, so a live backend never sends this. It survives for the
      // rollout window in docs/DEPLOYMENT.md §3 — a backend rolled back under
      // a shipped app build — where without it the code falls through to
      // AuthFailureUnknown, whose isExpected is false, and every retry by a
      // person who cannot possibly succeed files a Crashlytics non-fatal.
      if (e.message == 'email-not-verified') {
        return const AuthFailureSetupNotAvailableYet();
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
    Object? signOutError;
    StackTrace? signOutStack;
    try {
      await _auth.signOut();
    } catch (e, st) {
      signOutError = e;
      signOutStack = st;
    } finally {
      // Best-effort cache clear — if the keystore fails here it shouldn't fail
      // signOut too, since we check the cached uid again on next launch.
      try {
        await _authCache.clear();
      } catch (e, st) {
        _logger.warn('ACCT-SIGNOUT auth cache clear failed', e, st);
      }
    }
    if (signOutError == null) return;
    if (_auth.currentUser == null) {
      _logger.warn(
        'ACCT-SIGNOUT local signOut threw after auth state cleared',
        signOutError,
        signOutStack,
      );
      return;
    }
    Error.throwWithStackTrace(signOutError, signOutStack!);
  }
}

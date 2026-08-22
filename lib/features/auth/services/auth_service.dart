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

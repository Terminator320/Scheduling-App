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
import 'package:scheduling/features/employees/domain/models/invite_preview.dart';

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

  /// Handles invited-employee signup — registers or adopts the account,
  /// redeems the signup code, and rolls back the Auth user if redemption fails.
  ///
  /// The acceptance profile and the two consent flags ride through to
  /// `redeemSignupCode`, which stamps them onto the invited users doc inside
  /// the activation transaction. They default to empty/false so the pre-P4b
  /// call shape still compiles and still activates.
  Future<void> signUpWithCode({
    required String email,
    required String password,
    required String code,
    String firstName = '',
    String lastName = '',
    String phone = '',
    bool termsAccepted = false,
    bool locationConsent = false,
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
      await _employees.redeemSignupCode(
        code.trim(),
        firstName: firstName.trim(),
        lastName: lastName.trim(),
        phone: phone.trim(),
        termsAccepted: termsAccepted,
        locationConsent: locationConsent,
      );
    } catch (e, st) {
      final failure = _mapRedemptionError(e);
      // A wrong or expired code is the user mistyping, not a defect — keep the
      // trail, skip the non-fatal.
      _logger.authFailure(
        'signUpWithCode: redeemSignupCode failed',
        failure,
        e,
        st,
      );
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

  /// Resolves what an unredeemed signup [code] was issued for, before the
  /// holder has an account — mirrors [signUpWithCode]'s error mapping via
  /// [_mapRedemptionError]. The tables match: every case that mapper handles
  /// can come back from `previewInvite` too, except `code-email-mismatch`,
  /// which never will — that callable is unauthenticated, so there's no
  /// caller email yet for the server to compare it against.
  Future<InvitePreview> previewInvite(String code) async {
    try {
      return await _employees.previewInvite(code.trim());
    } catch (e) {
      throw _mapRedemptionError(e);
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

  // Deletes the freshly-created Auth user. The global account guard may have
  // already signed it out since there's no doc yet, so we reauth before
  // deleting to avoid leaving an orphan.
  Future<void> _rollbackOrFailLoud(
    UserCredential credential, {
    required String email,
    required String password,
    required String reason,
  }) async {
    try {
      await _deleteFreshlyCreatedUser(email: email, password: password);
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

  // Delete user, re-authenticating if the session was torn down or recent login is needed.
  Future<void> _deleteFreshlyCreatedUser({
    required String email,
    required String password,
  }) async {
    var user = _auth.currentUser;
    user ??= (await signIn(email: email, password: password)).user;
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

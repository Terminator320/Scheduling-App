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

  Future<UserCredential> createEmployeeAccount({
    required String email,
    required String password,
  }) async {
    // A previous attempt can orphan an Auth user (the invite lookup or the
    // rollback delete failed), and that orphan then blocks re-registration
    // with `email-already-in-use`. Adopt it by signing in so we can re-check
    // the invite and resend verification instead of dead-ending the user.
    // signIn rethrows wrong-password / invalid-credential when the email is
    // someone else's, which surfaces as the usual auth failure.
    UserCredential credential;
    var freshlyCreated = true;
    try {
      credential = await register(email: email, password: password);
    } on FirebaseAuthException catch (e) {
      if (e.code != 'email-already-in-use') rethrow;
      credential = await signIn(email: email, password: password);
      freshlyCreated = false;
    }

    final user = credential.user!;

    InvitedEmployeeMatch? invitedEmployee;
    try {
      invitedEmployee = await _employees.findInvitedEmployeeForCurrentUser();
    } catch (e, st) {
      _logger.warn(
        'createEmployeeAccount: findInvitedEmployeeForCurrentUser failed',
        e,
        st,
      );
      // Only roll back an account we freshly created this call — never delete
      // an adopted pre-existing account on a transient lookup failure.
      if (freshlyCreated) {
        await _rollbackOrFailLoud(credential, reason: 'invite-lookup-failed');
      } else {
        await _signOutQuietly();
      }
      rethrow;
    }

    if (invitedEmployee != null) {
      await user.sendEmailVerification();
      return credential;
    }

    // No invite matches this email. An adopted account that's already
    // provisioned (has a `users` doc keyed by uid) is a real account — tell
    // them to sign in, never delete it. Only a true orphan gets cleaned up.
    if (!freshlyCreated) {
      final provisioned = await _employees.findUserByUid(user.uid);
      if (provisioned != null) {
        await _signOutQuietly();
        throw const AuthFailureEmailAlreadyInUse();
      }
    }
    await _rollbackOrFailLoud(credential, reason: 'no-invite-found');
    throw const AuthFailureNotAuthorized();
  }

  // Best-effort cleanup of the Auth user we just created. When this delete
  // fails (App Check hiccup, network blip, requires-recent-login edge case)
  // the user is left orphaned: an Auth identity with no Firestore users doc
  // backing it, which blocks future Create-Account attempts with the same
  // email. Sign the session out so we never leave a half-signed-in orphan,
  // log the failure for Crashlytics, and throw a distinct failure so the UI
  // tells the admin how to recover.
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
      await _signOutQuietly();
      throw const AuthFailureAccountCreationIncomplete();
    }
  }

  Future<void> _signOutQuietly() async {
    try {
      await _auth.signOut();
    } catch (_) {}
  }

  // Best-effort resend of the email-verification link. Returns false (instead
  // of throwing) when the send fails — e.g. Firebase rate-limits repeated
  // requests — so the caller can fall back to a plain "please verify" message.
  Future<bool> resendVerificationEmail(User user) async {
    try {
      await user.sendEmailVerification();
      return true;
    } catch (e, st) {
      _logger.warn('resendVerificationEmail failed', e, st);
      return false;
    }
  }

  Future<void> tryActivateInvitedEmployee(User user) async {
    await user.reload();
    // reload() refreshes the auth instance's user; the passed-in snapshot can
    // be stale, so re-read the verified flag from the instance.
    final refreshed = _auth.currentUser ?? user;
    if (!refreshed.emailVerified) return;
    final invite = await _employees.findInvitedEmployeeForCurrentUser();
    if (invite == null) return;
    await _employees.activateEmployee(docId: invite.docId, uid: user.uid);
  }

  Future<void> signOut() async {
    try {
      await _auth.signOut();
    } finally {
      await _authCache.clear();
    }
  }
}

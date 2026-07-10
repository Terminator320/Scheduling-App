import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/core/storage/secure_storage_service.dart';
import 'package:scheduling/features/auth/data/auth_cache.dart';
import 'package:scheduling/features/auth/data/auth_error_mapper.dart';
import 'package:scheduling/features/auth/domain/auth_failure.dart';
import 'package:scheduling/features/auth/services/auth_service.dart';
import 'package:scheduling/features/employees/application/employees_providers.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';

/// Outcome of a sign-in attempt (or of resuming a session right after
/// signup). The login screen only maps these to banner messages and
/// navigation; the orchestration lives in [SignInController].
sealed class SignInOutcome {
  const SignInOutcome();
}

/// Signed in with an active, provisioned account — route into the app.
class SignInSuccess extends SignInOutcome {
  const SignInSuccess(this.employee);
  final EmployeeRecord employee;
}

/// Auth accepted the request but returned no user.
class SignInInvalidCredentials extends SignInOutcome {
  const SignInInvalidCredentials();
}

/// Signed in, but no provisioned `users` doc exists for this uid. The session
/// was signed out again before this outcome was returned.
class SignInNoProfile extends SignInOutcome {
  const SignInNoProfile();
}

/// The account's `users` doc is not active (disabled staff). The session was
/// signed out again before this outcome was returned.
class SignInAccountDisabled extends SignInOutcome {
  const SignInAccountDisabled();
}

/// Post-signup resume only: there is no authenticated session to resume.
class SignInNoSession extends SignInOutcome {
  const SignInNoSession();
}

/// Post-signup resume only: signed in, but the freshly activated `users` doc
/// has not become readable yet — ask the user to sign in normally.
class SignInProfilePending extends SignInOutcome {
  const SignInProfilePending();
}

/// The attempt failed; [failure] is already mapped for localized display.
class SignInError extends SignInOutcome {
  const SignInError(this.failure);
  final AuthFailure failure;
}

/// Busy flag for the sign-in flow — drives the button spinner and disables
/// the form fields while the attempt is in flight.
@immutable
class SignInState {
  const SignInState({this.inProgress = false});

  final bool inProgress;

  @override
  bool operator ==(Object other) =>
      other is SignInState && other.inProgress == inProgress;

  @override
  int get hashCode => inProgress.hashCode;
}

/// Orchestrates the sign-in flow shared by the login form and the
/// return-from-signup path: auth call, uid-keyed profile lookup (with the
/// auth-propagation retry), active check, and the best-effort cache writes.
/// Returns a [SignInOutcome]; the screen owns form state and navigation.
class SignInController extends Notifier<SignInState> {
  @override
  SignInState build() => const SignInState();

  /// Full credential sign-in. On success [state] stays in-progress so the
  /// button keeps its spinner while the screen navigates away; every other
  /// outcome resets it so the form is usable again.
  Future<SignInOutcome> signIn({
    required String email,
    required String password,
  }) async {
    // Resolve dependencies before the first await: the screen can be disposed
    // mid-flight, and using the Ref of a disposed notifier throws in
    // Riverpod 3.
    final auth = ref.read(authServiceProvider);
    final employees = ref.read(employeesRepositoryProvider);
    final authCache = ref.read(authCacheProvider);
    final storage = ref.read(secureStorageServiceProvider);
    final logger = ref.read(loggerProvider);

    state = const SignInState(inProgress: true);
    try {
      final credential = await auth.signIn(email: email, password: password);
      final user = credential.user;
      if (user == null) {
        _settle();
        return const SignInInvalidCredentials();
      }

      // A provisioned user has a uid-keyed users doc. Invited employees are
      // activated server-side at signup (redeemSignupCode), so there is no
      // client-side activation fallback here.
      final userDoc = await _retryOnAuthPropagation(
        () => employees.findUserByUid(user.uid),
      );

      if (userDoc == null) {
        // Signed in, but no profile doc — not a provisioned account.
        await auth.signOut();
        _settle();
        return const SignInNoProfile();
      }

      final employee = EmployeeRecord.fromMap(userDoc.id, userDoc.data);

      if (!employee.isActive) {
        await auth.signOut();
        _settle();
        return const SignInAccountDisabled();
      }

      // Best-effort identity cache + remembered email: neither may delay or
      // fail the sign-in, so they run unawaited and only log on failure.
      unawaited(
        authCache.save(employee).catchError((Object e, StackTrace st) {
          logger.warn('login.auth_cache_save', e, st);
        }),
      );
      unawaited(
        storage
            .write(
              SecureStorageKeys.rememberedEmail,
              email.trim().toLowerCase(),
            )
            .catchError((Object e, StackTrace st) {
              logger.warn('login.remember_email', e, st);
            }),
      );

      return SignInSuccess(employee);
    } catch (error, stackTrace) {
      logger.warn('login.sign_in', error, stackTrace);
      _settle();
      return SignInError(AuthErrorMapper.map(error));
    }
  }

  /// The create-account flow signs the user in and activates their account
  /// via the signup code. They're already authenticated and active, so
  /// resolve their profile and let the screen route straight into the app
  /// instead of asking them to sign in again.
  Future<SignInOutcome> resumeAfterSignUp() async {
    final auth = ref.read(authServiceProvider);
    final employees = ref.read(employeesRepositoryProvider);
    final logger = ref.read(loggerProvider);
    final user = auth.currentUser;
    if (user == null) return const SignInNoSession();
    try {
      final userDoc = await _retryOnAuthPropagation(
        () => employees.findUserByUid(user.uid),
      );
      if (userDoc == null) return const SignInProfilePending();
      return SignInSuccess(EmployeeRecord.fromMap(userDoc.id, userDoc.data));
    } catch (error, stackTrace) {
      // The account IS created and active server-side — a failed profile read
      // here must not escape to the zone handler and strand the user with no
      // message. "Pending" tells them to sign in normally, which recovers.
      logger.warn('login.resume_after_sign_up', error, stackTrace);
      return const SignInProfilePending();
    }
  }

  void _settle() {
    if (ref.mounted) state = const SignInState();
  }
}

/// signInWithEmailAndPassword resolves before the freshly minted ID token has
/// propagated to Firestore's request channel, so the first authorized read
/// fired right after sign-in can come back permission-denied even though the
/// user is signed in — the "have to tap Sign in twice" race. Retry such a
/// read once after a short delay, by which point the token has propagated.
Future<T> _retryOnAuthPropagation<T>(Future<T> Function() read) async {
  try {
    return await read();
  } on FirebaseException catch (e) {
    if (e.code != 'permission-denied') rethrow;
    await Future<void>.delayed(const Duration(milliseconds: 400));
    return read();
  }
}

final signInControllerProvider =
    NotifierProvider.autoDispose<SignInController, SignInState>(
      SignInController.new,
    );

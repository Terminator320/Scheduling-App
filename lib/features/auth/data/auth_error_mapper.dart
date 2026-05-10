import 'package:firebase_auth/firebase_auth.dart';

import 'package:scheduling/features/auth/domain/auth_failure.dart';

/// Translates a `FirebaseAuthException` (or any `Object` from a `try/catch`)
/// into an `AuthFailure`. Centralizes every Firebase code → typed-failure
/// mapping the auth feature cares about. Anything unrecognised becomes
/// `AuthFailureUnknown`.
class AuthErrorMapper {
  const AuthErrorMapper._();

  static AuthFailure map(Object error) {
    if (error is! FirebaseAuthException) {
      return const AuthFailureUnknown();
    }
    return _fromCode(error.code);
  }

  static AuthFailure _fromCode(String code) {
    switch (code) {
      case 'invalid-email':
        return const AuthFailureInvalidEmail();
      case 'user-disabled':
        return const AuthFailureUserDisabled();
      case 'user-not-found':
        return const AuthFailureUserNotFound();
      // Firebase may return any of these three for a wrong password.
      case 'wrong-password':
      case 'invalid-credential':
      case 'INVALID_LOGIN_CREDENTIALS':
        return const AuthFailureWrongCredentials();
      case 'too-many-requests':
        return const AuthFailureTooManyRequests();
      case 'network-request-failed':
        return const AuthFailureNetwork();
      case 'email-already-in-use':
        return const AuthFailureEmailAlreadyInUse();
      case 'weak-password':
        return const AuthFailureWeakPassword();
      case 'operation-not-allowed':
        return const AuthFailureOperationNotAllowed();
      case 'requires-recent-login':
        return const AuthFailureRequiresRecentLogin();
      case 'not-authorized':
        return const AuthFailureNotAuthorized();
      default:
        return const AuthFailureUnknown();
    }
  }
}

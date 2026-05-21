import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:scheduling/features/auth/domain/auth_failure.dart';

class AuthErrorMapper {
  const AuthErrorMapper._();

  static AuthFailure map(Object error) {
    if (error is AuthFailure) return error;
    if (error is FirebaseAuthException) return _fromCode(error.code);
    if (error is FirebaseException && error.code == 'permission-denied') {
      return const AuthFailurePermissionDenied();
    }
    return const AuthFailureUnknown();
  }

  static AuthFailure _fromCode(String code) {
    switch (code) {
      case 'invalid-email':
        return const AuthFailureInvalidEmail();
      case 'user-disabled':
        return const AuthFailureUserDisabled();
      case 'user-not-found':
        return const AuthFailureUserNotFound();
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

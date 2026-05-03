import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';

import 'package:scheduling/core/utils/app_text.dart';

enum AuthErrorContext {
  login,
  register,
  forgotPassword,
  passwordReset,
  reauthentication,
  general,
}

class AuthErrorHandler {
  const AuthErrorHandler._();

  static String getMessage(
    BuildContext context,
    Object error, {
    AuthErrorContext authContext = AuthErrorContext.general,
  }) {
    if (error is FirebaseAuthException) {
      return _messageForCode(context, error.code, authContext);
    }
    return tr(context, 'Something went wrong, please try again');
  }

  // Returns null for account-existence errors (user-not-found, user-disabled,
  // invalid-email) so the UI shows the same neutral "check your inbox" message
  // regardless of whether the email is registered — prevents account enumeration.
  static String? getPasswordResetRequestMessage(
    BuildContext context,
    Object error,
  ) {
    if (error is! FirebaseAuthException) {
      return tr(context, 'Something went wrong, please try again');
    }

    switch (error.code) {
      case 'too-many-requests':
      case 'network-request-failed':
        return getMessage(
          context,
          error,
          authContext: AuthErrorContext.forgotPassword,
        );
      default:
        return null;
    }
  }

static String _messageForCode(
    BuildContext context,
    String code,
    AuthErrorContext authContext,
  ) {
    switch (code) {
      case 'invalid-email':
        return tr(context, 'Please enter a valid email address');
      case 'user-disabled':
        return tr(context, 'This account has been disabled');
      case 'user-not-found':
        return authContext == AuthErrorContext.reauthentication
            ? tr(context, 'Please log in again and retry')
            : tr(context, 'No account found with this email');
      // Firebase may return any of these three codes for a wrong password.
      case 'wrong-password':
      case 'invalid-credential':
      case 'INVALID_LOGIN_CREDENTIALS':
        return authContext == AuthErrorContext.reauthentication
            ? tr(context, 'Please log in again and retry')
            : tr(context, 'Invalid email or password');
      case 'too-many-requests':
        return tr(context, 'Too many attempts, please try again later');
      case 'network-request-failed':
        return tr(
          context,
          'Network error. Check your connection and try again',
        );
      case 'email-already-in-use':
        return tr(context, 'An account with this email already exists');
      case 'weak-password':
        return tr(context, 'Password is too weak. Use at least 6 characters');
      case 'operation-not-allowed':
        return tr(context, 'Sign-in is temporarily unavailable');
      case 'requires-recent-login':
        return tr(context, 'Please log in again and retry');
      case 'not-authorized':
        return tr(context, 'This email is not authorized to sign up');
      default:
        return tr(context, 'Something went wrong, please try again');
    }
  }
}

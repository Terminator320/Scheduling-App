import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';

import 'package:scheduling/core/utils/l10n_extensions.dart';

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
    return context.l10n.somethingWentWrongPleaseTryAgain;
  }

  // Returns null for account-existence errors (user-not-found, user-disabled,
  // invalid-email) so the UI shows the same neutral "check your inbox" message
  // regardless of whether the email is registered — prevents account enumeration.
  static String? getPasswordResetRequestMessage(
    BuildContext context,
    Object error,
  ) {
    if (error is! FirebaseAuthException) {
      return context.l10n.somethingWentWrongPleaseTryAgain;
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
        return context.l10n.pleaseEnterAValidEmailAddress;
      case 'user-disabled':
        return context.l10n.thisAccountHasBeenDisabled;
      case 'user-not-found':
        return authContext == AuthErrorContext.reauthentication
            ? context.l10n.pleaseLogInAgainAndRetry
            : context.l10n.noAccountFoundWithThisEmail;
      // Firebase may return any of these three codes for a wrong password.
      case 'wrong-password':
      case 'invalid-credential':
      case 'INVALID_LOGIN_CREDENTIALS':
        return authContext == AuthErrorContext.reauthentication
            ? context.l10n.pleaseLogInAgainAndRetry
            : context.l10n.invalidEmailOrPassword;
      case 'too-many-requests':
        return context.l10n.tooManyAttemptsPleaseTryAgainLater2;
      case 'network-request-failed':
        return context.l10n.networkErrorCheckYourConnectionAndTryAgain;
      case 'email-already-in-use':
        return context.l10n.anAccountWithThisEmailAlreadyExists;
      case 'weak-password':
        return context.l10n.passwordIsTooWeakUseAtLeast6Characters;
      case 'operation-not-allowed':
        return context.l10n.signInIsTemporarilyUnavailable;
      case 'requires-recent-login':
        return context.l10n.pleaseLogInAgainAndRetry;
      case 'not-authorized':
        return context.l10n.thisEmailIsNotAuthorizedToSignUp;
      default:
        return context.l10n.somethingWentWrongPleaseTryAgain;
    }
  }
}

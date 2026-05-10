import 'package:flutter/widgets.dart';

import 'package:scheduling/core/errors/failure.dart';
import 'package:scheduling/core/utils/l10n_extensions.dart';

/// Where in the auth flow a failure surfaced. Affects messaging — for example
/// a `userNotFound` during reauthentication should ask the user to log in
/// again, while during login it should say "no account with this email."
enum AuthErrorContext {
  login,
  register,
  forgotPassword,
  passwordReset,
  reauthentication,
  general,
}

/// Sealed family of typed auth failures. Each variant maps 1:1 to a
/// `FirebaseAuthException.code` (see `AuthErrorMapper`).
///
/// Extends `Failure` so the same value can flow through `AppErrorListener`
/// and through screen-level banner state. Screens that need context-specific
/// strings call `toLocalizedMessageInContext`; the default
/// `toLocalizedMessage` (general context) is what `AppErrorListener` uses.
sealed class AuthFailure extends Failure {
  const AuthFailure();

  @override
  String toLocalizedMessage(BuildContext context) =>
      toLocalizedMessageInContext(context, AuthErrorContext.general);

  String toLocalizedMessageInContext(
    BuildContext context,
    AuthErrorContext errorContext,
  );
}

class AuthFailureInvalidEmail extends AuthFailure {
  const AuthFailureInvalidEmail();
  @override
  String toLocalizedMessageInContext(BuildContext c, AuthErrorContext _) =>
      c.l10n.pleaseEnterAValidEmailAddress;
}

class AuthFailureUserDisabled extends AuthFailure {
  const AuthFailureUserDisabled();
  @override
  String toLocalizedMessageInContext(BuildContext c, AuthErrorContext _) =>
      c.l10n.thisAccountHasBeenDisabled;
}

class AuthFailureUserNotFound extends AuthFailure {
  const AuthFailureUserNotFound();
  @override
  String toLocalizedMessageInContext(
    BuildContext c,
    AuthErrorContext errorContext,
  ) => errorContext == AuthErrorContext.reauthentication
      ? c.l10n.pleaseLogInAgainAndRetry
      : c.l10n.noAccountFoundWithThisEmail;
}

/// Covers Firebase's three "bad password" codes:
/// `wrong-password`, `invalid-credential`, `INVALID_LOGIN_CREDENTIALS`.
class AuthFailureWrongCredentials extends AuthFailure {
  const AuthFailureWrongCredentials();
  @override
  String toLocalizedMessageInContext(
    BuildContext c,
    AuthErrorContext errorContext,
  ) => errorContext == AuthErrorContext.reauthentication
      ? c.l10n.pleaseLogInAgainAndRetry
      : c.l10n.invalidEmailOrPassword;
}

class AuthFailureTooManyRequests extends AuthFailure {
  const AuthFailureTooManyRequests();
  @override
  String toLocalizedMessageInContext(BuildContext c, AuthErrorContext _) =>
      c.l10n.tooManyAttemptsPleaseTryAgainLater2;
}

class AuthFailureNetwork extends AuthFailure {
  const AuthFailureNetwork();
  @override
  String toLocalizedMessageInContext(BuildContext c, AuthErrorContext _) =>
      c.l10n.networkErrorCheckYourConnectionAndTryAgain;
}

class AuthFailureEmailAlreadyInUse extends AuthFailure {
  const AuthFailureEmailAlreadyInUse();
  @override
  String toLocalizedMessageInContext(BuildContext c, AuthErrorContext _) =>
      c.l10n.anAccountWithThisEmailAlreadyExists;
}

class AuthFailureWeakPassword extends AuthFailure {
  const AuthFailureWeakPassword();
  @override
  String toLocalizedMessageInContext(BuildContext c, AuthErrorContext _) =>
      c.l10n.passwordIsTooWeakUseAtLeast6Characters;
}

class AuthFailureOperationNotAllowed extends AuthFailure {
  const AuthFailureOperationNotAllowed();
  @override
  String toLocalizedMessageInContext(BuildContext c, AuthErrorContext _) =>
      c.l10n.signInIsTemporarilyUnavailable;
}

class AuthFailureRequiresRecentLogin extends AuthFailure {
  const AuthFailureRequiresRecentLogin();
  @override
  String toLocalizedMessageInContext(BuildContext c, AuthErrorContext _) =>
      c.l10n.pleaseLogInAgainAndRetry;
}

class AuthFailureNotAuthorized extends AuthFailure {
  const AuthFailureNotAuthorized();
  @override
  String toLocalizedMessageInContext(BuildContext c, AuthErrorContext _) =>
      c.l10n.thisEmailIsNotAuthorizedToSignUp;
}

class AuthFailureUnknown extends AuthFailure {
  const AuthFailureUnknown();
  @override
  String toLocalizedMessageInContext(BuildContext c, AuthErrorContext _) =>
      c.l10n.somethingWentWrongPleaseTryAgain;
}

/// Account-enumeration neutralization for the password-reset flow:
/// returns `null` for "this email isn't registered" style failures so the UI
/// shows the same neutral "check your inbox" message regardless of whether
/// the account exists. Mirrors the original
/// `AuthErrorHandler.getPasswordResetRequestMessage` behavior verbatim.
extension AuthFailureForgotPassword on AuthFailure {
  String? toForgotPasswordMessage(BuildContext context) {
    return switch (this) {
      AuthFailureTooManyRequests() => toLocalizedMessageInContext(
        context,
        AuthErrorContext.forgotPassword,
      ),
      AuthFailureNetwork() => toLocalizedMessageInContext(
        context,
        AuthErrorContext.forgotPassword,
      ),
      AuthFailureUnknown() => context.l10n.somethingWentWrongPleaseTryAgain,
      _ => null,
    };
  }
}

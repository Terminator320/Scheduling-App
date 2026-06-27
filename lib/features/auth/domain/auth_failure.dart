import 'package:flutter/widgets.dart';

import 'package:scheduling/core/errors/failure.dart';
import 'package:scheduling/l10n/l10n.dart';

enum AuthErrorContext {
  login,
  register,
  forgotPassword,
  reauthentication,
  general,
}

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
      c.l10n.validation_pleaseEnterAValidEmailAddress;
}

class AuthFailureUserDisabled extends AuthFailure {
  const AuthFailureUserDisabled();
  @override
  String toLocalizedMessageInContext(BuildContext c, AuthErrorContext _) =>
      c.l10n.error_thisAccountHasBeenDisabled;
}

class AuthFailureUserNotFound extends AuthFailure {
  const AuthFailureUserNotFound();
  @override
  String toLocalizedMessageInContext(
    BuildContext c,
    AuthErrorContext errorContext,
  ) => errorContext == AuthErrorContext.reauthentication
      ? c.l10n.auth_pleaseLogInAgainAndRetry
      : c.l10n.error_noAccountFoundWithThisEmail;
}

class AuthFailureWrongCredentials extends AuthFailure {
  const AuthFailureWrongCredentials();
  @override
  String toLocalizedMessageInContext(
    BuildContext c,
    AuthErrorContext errorContext,
  ) => errorContext == AuthErrorContext.reauthentication
      ? c.l10n.auth_pleaseLogInAgainAndRetry
      : c.l10n.error_invalidEmailOrPassword;
}

class AuthFailureTooManyRequests extends AuthFailure {
  const AuthFailureTooManyRequests();
  @override
  String toLocalizedMessageInContext(BuildContext c, AuthErrorContext _) =>
      c.l10n.error_tooManyAttemptsPleaseTryAgainLater;
}

class AuthFailureNetwork extends AuthFailure {
  const AuthFailureNetwork();
  @override
  String toLocalizedMessageInContext(BuildContext c, AuthErrorContext _) =>
      c.l10n.error_networkErrorCheckYourConnectionAndTryAgain;
}

class AuthFailureEmailAlreadyInUse extends AuthFailure {
  const AuthFailureEmailAlreadyInUse();
  @override
  String toLocalizedMessageInContext(
    BuildContext c,
    AuthErrorContext errorContext,
  ) => errorContext == AuthErrorContext.register
      ? c.l10n.error_anAccountWithThisEmailAlreadyExistsSignInOrContactAdmin
      : c.l10n.error_anAccountWithThisEmailAlreadyExists;
}

class AuthFailureWeakPassword extends AuthFailure {
  const AuthFailureWeakPassword();
  @override
  String toLocalizedMessageInContext(BuildContext c, AuthErrorContext _) =>
      c.l10n.validation_passwordIsTooWeakUseAtLeast6Characters;
}

class AuthFailureOperationNotAllowed extends AuthFailure {
  const AuthFailureOperationNotAllowed();
  @override
  String toLocalizedMessageInContext(BuildContext c, AuthErrorContext _) =>
      c.l10n.error_signInIsTemporarilyUnavailable;
}

class AuthFailureRequiresRecentLogin extends AuthFailure {
  const AuthFailureRequiresRecentLogin();
  @override
  String toLocalizedMessageInContext(BuildContext c, AuthErrorContext _) =>
      c.l10n.auth_pleaseLogInAgainAndRetry;
}

class AuthFailureNotAuthorized extends AuthFailure {
  const AuthFailureNotAuthorized();
  @override
  String toLocalizedMessageInContext(BuildContext c, AuthErrorContext _) =>
      c.l10n.error_thisEmailIsNotAuthorizedToSignUp;
}

class AuthFailureInvalidSignupCode extends AuthFailure {
  const AuthFailureInvalidSignupCode();
  @override
  String toLocalizedMessageInContext(BuildContext c, AuthErrorContext _) =>
      c.l10n.error_thatCodeIsntValidAskYourAdmin;
}

class AuthFailureSignupCodeExpired extends AuthFailure {
  const AuthFailureSignupCodeExpired();
  @override
  String toLocalizedMessageInContext(BuildContext c, AuthErrorContext _) =>
      c.l10n.error_thatCodeHasExpiredAskYourAdmin;
}

class AuthFailurePermissionDenied extends AuthFailure {
  const AuthFailurePermissionDenied();
  @override
  String toLocalizedMessageInContext(BuildContext c, AuthErrorContext _) =>
      c.l10n.error_signInIsTemporarilyUnavailable;
}

class AuthFailureUnknown extends AuthFailure {
  const AuthFailureUnknown();
  @override
  String toLocalizedMessageInContext(BuildContext c, AuthErrorContext _) =>
      c.l10n.error_somethingWentWrongPleaseTryAgain;
}

// Thrown when signUpWithCode created the Firebase Auth user but the rollback
// delete failed after code redemption errored. The Auth account is now
// orphaned: no matching Firestore users doc, blocks re-registration with the
// same email. Tell the admin to delete the Auth user in console and re-invite.
class AuthFailureAccountCreationIncomplete extends AuthFailure {
  const AuthFailureAccountCreationIncomplete();
  @override
  String toLocalizedMessageInContext(BuildContext c, AuthErrorContext _) =>
      c.l10n.error_accountCreationIncompleteContactAdmin;
}

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
      AuthFailureUnknown() =>
        context.l10n.error_somethingWentWrongPleaseTryAgain,
      _ => null,
    };
  }
}

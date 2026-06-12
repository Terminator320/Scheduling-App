import 'package:flutter/widgets.dart';

import 'package:scheduling/core/validators/password_requirements.dart';
import 'package:scheduling/l10n/l10n.dart';

class AuthValidators {
  const AuthValidators._();

  static final RegExp _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  static bool isValidEmailFormat(String email) => _emailPattern.hasMatch(email);

  static String? email(BuildContext context, String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return context.l10n.validation_pleaseEnterYourEmail;
    }
    if (!isValidEmailFormat(trimmed)) {
      return context.l10n.validation_pleaseEnterAValidEmailAddress;
    }
    return null;
  }

  static const int minPasswordLength = PasswordRequirement.minLengthChars;

  static String? password(BuildContext context, String value) {
    if (value.trim().isEmpty) {
      return context.l10n.validation_pleaseEnterYourPassword;
    }
    if (value.length < minPasswordLength) {
      return context.l10n.validation_passwordMustBeAtLeast8Characters;
    }
    return null;
  }

  /// Strict variant for the create-account flow — sign-in keeps [password]
  /// so existing credentials predating these rules aren't blocked.
  static String? newPassword(BuildContext context, String value) {
    if (value.trim().isEmpty) {
      return context.l10n.validation_pleaseEnterYourPassword;
    }
    if (!PasswordRequirement.allMetBy(value)) {
      return context.l10n.validation_passwordDoesNotMeetAllRequirements;
    }
    return null;
  }
}

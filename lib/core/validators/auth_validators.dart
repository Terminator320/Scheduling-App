import 'package:flutter/widgets.dart';

import 'package:scheduling/core/utils/l10n_extensions.dart';

class AuthValidators {
  const AuthValidators._();

  static final RegExp _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  static bool isValidEmailFormat(String email) => _emailPattern.hasMatch(email);

  static String? email(BuildContext context, String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return context.l10n.pleaseEnterYourEmail;
    }
    if (!isValidEmailFormat(trimmed)) {
      return context.l10n.pleaseEnterAValidEmailAddress;
    }
    return null;
  }

  static const int minPasswordLength = 8;

  static String? password(BuildContext context, String value) {
    if (value.trim().isEmpty) {
      return context.l10n.pleaseEnterYourPassword;
    }
    if (value.length < minPasswordLength) {
      return context.l10n.passwordMustBeAtLeast8Characters;
    }
    return null;
  }
}

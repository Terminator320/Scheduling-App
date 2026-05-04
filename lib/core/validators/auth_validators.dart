import 'package:flutter/widgets.dart';

import 'package:scheduling/core/utils/l10n_extensions.dart';

// Centralizes auth field validation so login and forgot-password screens
// stay in sync without duplicating regex or error strings.
class AuthValidators {
  const AuthValidators._();

  static final RegExp _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  static String? email(BuildContext context, String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return context.l10n.pleaseEnterYourEmail;
    }
    if (!_emailPattern.hasMatch(trimmed)) {
      return context.l10n.pleaseEnterAValidEmailAddress;
    }
    return null;
  }

  static String? password(BuildContext context, String value) {
    if (value.trim().isEmpty) {
      return context.l10n.pleaseEnterYourPassword;
    }
    return null;
  }
}

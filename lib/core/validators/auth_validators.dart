import 'package:flutter/widgets.dart';

import 'package:scheduling/core/utils/app_text.dart';

// Centralizes auth field validation so login and forgot-password screens
// stay in sync without duplicating regex or error strings.
class AuthValidators {
  const AuthValidators._();

  static final RegExp _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  static String? email(BuildContext context, String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return tr(context, 'Please enter your email');
    }
    if (!_emailPattern.hasMatch(trimmed)) {
      return tr(context, 'Please enter a valid email address');
    }
    return null;
  }

  static String? password(BuildContext context, String value) {
    if (value.trim().isEmpty) {
      return tr(context, 'Please enter your password');
    }
    return null;
  }
}

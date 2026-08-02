import 'package:flutter/foundation.dart';

/// What `createEmployeeAccount` hands back for the admin to read out: the
/// address the person signs in with, and the starting password the server
/// actually set.
///
/// The password comes FROM the server rather than from a client constant so
/// the dialog can't display something the account was never given — the two
/// would drift silently the first time the default changes on one side.
///
/// This is a credential in transit. It lives in widget state and dies with the
/// surface: never logged, never persisted, never in a notice. The clipboard
/// copy on the dialog is the one sanctioned egress, exactly as it was for the
/// signup code this replaced.
@immutable
class NewAccountCredentials {
  const NewAccountCredentials({required this.email, required this.password});

  /// Decodes the callable's payload. Callers must apply the loose cast
  /// (`(res.data as Map?)?.cast<String, dynamic>()`) first — a direct generic
  /// cast throws on Android.
  factory NewAccountCredentials.fromMap(Map<String, dynamic> data) =>
      NewAccountCredentials(
        email: (data['email'] ?? '').toString(),
        password: (data['password'] ?? '').toString(),
      );

  final String email;
  final String password;

  bool get isComplete => email.isNotEmpty && password.isNotEmpty;

  @override
  bool operator ==(Object other) =>
      other is NewAccountCredentials &&
      other.email == email &&
      other.password == password;

  @override
  int get hashCode => Object.hash(email, password);
}

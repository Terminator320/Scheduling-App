import 'package:flutter/foundation.dart';

/// What the `previewInvite` callable can truthfully say about a pending invite
/// before the holder has an account: who it was issued to, what they are being
/// invited as, and when the code dies.
///
/// The callable deliberately returns nothing else — no doc id, no phone, no
/// colour — so this class has nothing else to carry.
@immutable
class InvitePreview {
  const InvitePreview({
    required this.email,
    required this.firstName,
    required this.lastName,
    required this.role,
    required this.expiresAt,
  });

  /// Decodes the callable's payload. Callers must apply the loose cast
  /// (`(res.data as Map?)?.cast<String, dynamic>()`) first — a direct generic
  /// cast throws on Android.
  factory InvitePreview.fromMap(Map<String, dynamic> data) {
    final expiresAtMs = (data['expiresAtMs'] as num?)?.toInt();
    return InvitePreview(
      email: (data['email'] ?? '').toString(),
      firstName: (data['firstName'] ?? '').toString(),
      lastName: (data['lastName'] ?? '').toString(),
      role: (data['role'] ?? 'employee').toString(),
      expiresAt: expiresAtMs == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(expiresAtMs),
    );
  }

  final String email;
  final String firstName;
  final String lastName;

  /// The ACCESS role (`admin` / `employee`), never a job title.
  final String role;

  /// Null when the payload carried no expiry — the banner omits the line
  /// rather than rendering an epoch date.
  final DateTime? expiresAt;

  bool get isAdmin => role == 'admin';

  @override
  bool operator ==(Object other) =>
      other is InvitePreview &&
      other.email == email &&
      other.firstName == firstName &&
      other.lastName == lastName &&
      other.role == role &&
      other.expiresAt == expiresAt;

  @override
  int get hashCode => Object.hash(email, firstName, lastName, role, expiresAt);
}

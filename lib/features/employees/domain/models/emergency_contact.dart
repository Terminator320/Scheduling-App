import 'package:flutter/foundation.dart';

/// Who to call about a person if something goes wrong on site.
///
/// This lives in `users/{docId}/private/emergency`, NOT on the users doc, and
/// the separation is the whole point. Firestore rules are document-level —
/// there is no way to hide a field from someone allowed to read the document —
/// and the `/users` read rule deliberately lets every active employee read
/// every active peer (the crew pickers, names and colours depend on it). Left
/// on the parent doc, this pair shipped a third party's name and phone number
/// to every employee's device; that third party is not an app user and never
/// consented. A subcollection is the only place rules can gate it to the admin
/// and the person themselves.
@immutable
class EmergencyContact {
  const EmergencyContact({this.contact = '', this.phone = ''});

  factory EmergencyContact.fromMap(Map<String, dynamic>? data) {
    if (data == null) return empty;
    return EmergencyContact(
      contact: (data['contact'] ?? '').toString(),
      phone: (data['phone'] ?? '').toString(),
    );
  }

  final String contact;
  final String phone;

  static const empty = EmergencyContact();

  bool get isEmpty => contact.trim().isEmpty && phone.trim().isEmpty;
  bool get isNotEmpty => !isEmpty;

  /// Trimmed on the way out so a whitespace-only edit round-trips to [isEmpty]
  /// rather than persisting a blank the detail view would then render.
  Map<String, dynamic> toMap() => {
    'contact': contact.trim(),
    'phone': phone.trim(),
  };

  @override
  bool operator ==(Object other) =>
      other is EmergencyContact &&
      other.contact == contact &&
      other.phone == phone;

  @override
  int get hashCode => Object.hash(contact, phone);
}

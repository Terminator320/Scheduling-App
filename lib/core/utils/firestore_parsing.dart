import 'package:cloud_firestore/cloud_firestore.dart';

/// Parses a Firestore field value into a [DateTime]: accepts a Firestore
/// [Timestamp], a [DateTime], or an ISO-8601 [String]. Returns null for
/// anything else. This is the single Firestore-date boundary for the domain
/// models, so they call it instead of importing `cloud_firestore` themselves.
DateTime? firestoreDateTime(dynamic value) {
  if (value == null) return null;
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  return null;
}

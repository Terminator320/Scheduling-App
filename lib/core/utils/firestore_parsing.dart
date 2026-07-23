import 'package:cloud_firestore/cloud_firestore.dart';

/// Parses a Firestore field value into [DateTime]; the single Firestore-date boundary so domain models don't import cloud_firestore.
DateTime? firestoreDateTime(dynamic value) {
  if (value == null) return null;
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  return null;
}

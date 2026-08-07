import 'package:cloud_firestore/cloud_firestore.dart';

/// Parses a Firestore field value into [DateTime]. This is the single
/// Firestore-date boundary, so domain models don't need to import
/// cloud_firestore directly.
DateTime? firestoreDateTime(dynamic value) {
  if (value == null) return null;
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  return null;
}

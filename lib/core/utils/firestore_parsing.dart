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

/// Parses a Firestore field value into a whole number, leniently.
///
/// The lenient counterpart of `firestoreDateTime`, and it exists for the same
/// reason: these factories run inside `snapshots().map`, so a hard
/// `as num?` on ONE console-written or legacy document throws for the entire
/// snapshot rather than for the field — blanking a list, a map or a picker
/// app-wide. A double is truncated (Firestore has one number type on the
/// console side); anything unparseable is null, for the caller's default.
int? firestoreInt(dynamic value) {
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim());
  return null;
}

/// Parses a Firestore field value into a list of strings.
///
/// Two accepted shapes, a list of strings or a bare non-empty string, because
/// both occur in stored documents. ONE owner on purpose: the history filter
/// reads `employeeNames` off the raw map before a record exists, so a second
/// spelling that accepted less would silently reject documents the record
/// itself would have matched — a search that quietly stops finding a crew
/// member, with nothing logged.
List<String> firestoreStringList(dynamic value) {
  if (value is List) return value.whereType<String>().toList();
  if (value is String && value.isNotEmpty) return [value];
  return const [];
}

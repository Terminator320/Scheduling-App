import 'package:cloud_firestore/cloud_firestore.dart';

/// Parses a Firestore field value into [DateTime].
DateTime? firestoreDateTime(dynamic value) {
  if (value == null) return null;
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  if (value is Map) {
    final seconds = value['seconds'] ?? value['_seconds'];
    final nanos = value['nanoseconds'] ?? value['_nanoseconds'] ?? 0;
    if (seconds is num && nanos is num) {
      return DateTime.fromMillisecondsSinceEpoch(
        seconds.toInt() * 1000 + (nanos.toInt() ~/ 1000000),
      );
    }
    final millis = value['millisecondsSinceEpoch'];
    if (millis is num) {
      return DateTime.fromMillisecondsSinceEpoch(millis.toInt());
    }
  }
  return null;
}

/// Parses a Firestore field value into a whole number, leniently.
int? firestoreInt(dynamic value) {
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim());
  return null;
}

/// Parses a Firestore field value into a list, leniently.
List<Object?> firestoreList(dynamic value) => value is List ? value : const [];

/// Parses a Firestore field value into a list of strings.
List<String> firestoreStringList(dynamic value) {
  if (value is List) return value.whereType<String>().toList();
  if (value is String && value.isNotEmpty) return [value];
  return const [];
}

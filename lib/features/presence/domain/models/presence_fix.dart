import 'package:flutter/foundation.dart';

/// A single staff member's last-known location fix, read from
/// `users/{userDocId}/presence/location` via the `presence` collection group.
/// `updatedAt` is null while a latency-compensated own-write's
/// `serverTimestamp()` is still pending — callers treat a null as fresh.
@immutable
class PresenceFix {
  const PresenceFix({
    required this.userDocId,
    required this.lat,
    required this.lng,
    required this.updatedAt,
  });

  final String userDocId;
  final double lat;
  final double lng;
  final DateTime? updatedAt;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PresenceFix &&
          other.userDocId == userDocId &&
          other.lat == lat &&
          other.lng == lng &&
          other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(userDocId, lat, lng, updatedAt);
}

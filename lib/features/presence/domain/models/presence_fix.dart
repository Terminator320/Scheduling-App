import 'package:flutter/foundation.dart';

/// A single staff member's last-known location fix; updatedAt is null (treated as fresh) pending own-write's serverTimestamp().
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

import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:scheduling/core/logging/app_logger.dart';

/// Reads/writes the single `users/{docId}/presence/location` doc that feeds
/// the server's travel-time "leave now" reminders. Injected Firestore (never
/// `FirebaseFirestore.instance` from UI); logs and swallows failures so a
/// presence write never breaks a flow.
class PresenceRepository {
  PresenceRepository({required FirebaseFirestore firestore, AppLogger? logger})
    : _firestore = firestore,
      _logger = logger ?? AppLogger();

  final FirebaseFirestore _firestore;
  final AppLogger _logger;

  DocumentReference<Map<String, dynamic>> _locationDoc(String userDocId) =>
      _firestore
          .collection('users')
          .doc(userDocId)
          .collection('presence')
          .doc('location');

  /// Upserts the device's last fix. The written fields stay within the four
  /// the security rule allows (`hasOnly([lat, lng, uid, updatedAt])`), and
  /// `updatedAt` MUST be a server timestamp (the rule enforces
  /// `updatedAt == request.time` so freshness can't be spoofed).
  Future<void> upsertLocation({
    required String userDocId,
    required String uid,
    required double lat,
    required double lng,
  }) async {
    try {
      await _locationDoc(userDocId).set(<String, dynamic>{
        'lat': lat,
        'lng': lng,
        'uid': uid,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e, st) {
      _logger.warn('PRESENCE upsertLocation failed', e, st);
    }
  }

  /// Best-effort delete on sign-out — privacy: no stale coordinates left
  /// behind after leaving.
  Future<void> deleteLocation({required String userDocId}) async {
    try {
      await _locationDoc(userDocId).delete();
    } catch (e, st) {
      _logger.warn('PRESENCE deleteLocation failed', e, st);
    }
  }
}

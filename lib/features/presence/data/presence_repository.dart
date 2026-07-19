import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/core/utils/retry.dart';
import 'package:scheduling/features/presence/domain/models/presence_fix.dart';

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
  ///
  /// Returns `true` on a successful write, `false` when the write failed (still
  /// logged and swallowed so a presence write never breaks a flow) — the caller
  /// uses this to avoid advancing its throttle clock on a failed write.
  Future<bool> upsertLocation({
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
      return true;
    } catch (e, st) {
      _logger.warn('PRESENCE upsertLocation failed', e, st);
      return false;
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

  /// Live feed of every staff member's last-known fix, for the admin map.
  /// Unlike the write paths above, stream errors PROPAGATE to the listener
  /// (the screen surfaces them) rather than being swallowed.
  Stream<List<PresenceFix>> watchAllPresence() => retryStream(
    () => _firestore.collectionGroup('presence').snapshots().map(_toFixes),
    retryWhen: _isAuthPropagationDenied,
  );

  /// One malformed doc must not drop the whole map — skip it and keep going.
  List<PresenceFix> _toFixes(QuerySnapshot<Map<String, dynamic>> snapshot) {
    final fixes = <PresenceFix>[];
    for (final doc in snapshot.docs) {
      final userDocId = doc.reference.parent.parent?.id;
      if (userDocId == null) continue;
      final data = doc.data();
      final rawLat = data['lat'];
      final rawLng = data['lng'];
      if (rawLat is! num || rawLng is! num) continue;
      final lat = rawLat.toDouble();
      final lng = rawLng.toDouble();
      fixes.add(
        PresenceFix(
          userDocId: userDocId,
          lat: lat,
          lng: lng,
          updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
        ),
      );
    }
    return fixes;
  }
}

// Twin of `_isAuthPropagationDenied` in
// `lib/features/employees/data/firebase_employees_repository.dart` — keep in
// sync. A freshly signed-in user's ID token can lag auth state, so the first
// collection-group listen can come back permission-denied even though the
// read is authorized. Re-subscribing after a short delay succeeds; a genuine
// denial survives every retry and surfaces as before.
bool _isAuthPropagationDenied(Object error) =>
    error is FirebaseException && error.code == 'permission-denied';

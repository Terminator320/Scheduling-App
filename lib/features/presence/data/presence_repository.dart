import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/core/utils/retry.dart';
import 'package:scheduling/features/presence/domain/models/presence_fix.dart';

/// Outcome of a presence write. Lets the controller distinguish a transient
/// failure from a rules denial.
enum PresenceWriteResult { ok, failed, denied }

/// Upper bound on the admin live-map presence feed, mirroring the users
/// streams' `_userStreamLimit` posture so a rules/data anomaly can't stream an
/// unbounded snapshot to the client.
const _presenceStreamLimit = 500;

/// Reads and writes the single `users/{docId}/presence/location` doc that
/// feeds the server's travel-time "leave now" reminders. Logs and swallows
/// failures so a presence write never breaks a flow.
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

  /// Upserts the device's last fix with a server-timestamp `updatedAt`. Never
  /// throws — the caller uses the returned result to avoid advancing the
  /// throttle clock on failure, and to stop tracking entirely on denial.
  Future<PresenceWriteResult> upsertLocation({
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
      return PresenceWriteResult.ok;
    } on FirebaseException catch (e, st) {
      _logger.warn('PRESENCE upsertLocation failed', e, st);
      return e.code == 'permission-denied'
          ? PresenceWriteResult.denied
          : PresenceWriteResult.failed;
    } catch (e, st) {
      _logger.warn('PRESENCE upsertLocation failed', e, st);
      return PresenceWriteResult.failed;
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

  /// Live feed of every staff member's last-known fix, for the admin map;
  /// unlike the write paths above, stream errors PROPAGATE to the listener.
  Stream<List<PresenceFix>> watchAllPresence() => retryStream(
    () => _firestore
        .collectionGroup('presence')
        .limit(_presenceStreamLimit)
        .snapshots()
        .map(_toFixes),
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

// Retries permission-denied from auth-token propagation lag (twin in firebase_employees_repository.dart; keep in sync).
bool _isAuthPropagationDenied(Object error) =>
    error is FirebaseException && error.code == 'permission-denied';

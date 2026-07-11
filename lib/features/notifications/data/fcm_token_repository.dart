import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:scheduling/core/logging/app_logger.dart';

/// Reads/writes the `users/{docId}/fcmTokens/{token}` device-token docs (doc
/// id = the token). Injected Firestore (never `FirebaseFirestore.instance`
/// from UI); logs and swallows failures so a token write never breaks a flow.
class FcmTokenRepository {
  FcmTokenRepository({required FirebaseFirestore firestore, AppLogger? logger})
    : _firestore = firestore,
      _logger = logger ?? AppLogger();

  final FirebaseFirestore _firestore;
  final AppLogger _logger;

  DocumentReference<Map<String, dynamic>> _tokenDoc(
    String userDocId,
    String token,
  ) => _firestore
      .collection('users')
      .doc(userDocId)
      .collection('fcmTokens')
      .doc(token);

  /// Upserts a device token. The written fields stay within the five the
  /// security rule allows (`hasOnly([platform, locale, uid, createdAt,
  /// updatedAt])`). `createdAt` is stamped only when the doc is first created
  /// so a token refresh (which re-upserts) preserves the original registration
  /// time instead of overwriting it; every write refreshes `updatedAt`.
  ///
  /// The existence check and the write run in a single transaction so two
  /// near-simultaneous upserts of the same token can't both observe "absent"
  /// and race on `createdAt`. (A read is inherent to a conditional
  /// `createdAt` — Firestore has no field-level create-only write — so the
  /// transaction makes that read-modify-write atomic rather than removing it.)
  Future<void> upsertToken({
    required String userDocId,
    required String token,
    required String platform,
    required String locale,
    required String uid,
  }) async {
    try {
      final ref = _tokenDoc(userDocId, token);
      await _firestore.runTransaction<void>((txn) async {
        final snap = await txn.get(ref);
        final data = <String, dynamic>{
          'platform': platform,
          'locale': locale,
          'uid': uid,
          'updatedAt': FieldValue.serverTimestamp(),
          if (!snap.exists) 'createdAt': FieldValue.serverTimestamp(),
        };
        txn.set(ref, data, SetOptions(merge: true));
      });
    } catch (e, st) {
      _logger.warn('FCM upsertToken failed', e, st);
    }
  }

  Future<void> deleteToken({
    required String userDocId,
    required String token,
  }) async {
    try {
      await _tokenDoc(userDocId, token).delete();
    } catch (e, st) {
      _logger.warn('FCM deleteToken failed', e, st);
    }
  }
}

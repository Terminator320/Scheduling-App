import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:scheduling/core/logging/app_logger.dart';

/// Reads/writes `users/{docId}/fcmTokens/{token}` device-token docs; logs and swallows failures so token writes never break a flow.
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

  /// Upserts a device token with createdAt only on first write (not overwritten on refresh).
  /// Plain get-then-set, NOT a transaction: concurrent transactions crash in cloud_firestore iOS plugin; cosmetic re-stamp of createdAt is acceptable.
  Future<void> upsertToken({
    required String userDocId,
    required String token,
    required String platform,
    required String locale,
    required String uid,
  }) async {
    try {
      final ref = _tokenDoc(userDocId, token);
      final snap = await ref.get();
      final data = <String, dynamic>{
        'platform': platform,
        'locale': locale,
        'uid': uid,
        'updatedAt': FieldValue.serverTimestamp(),
        if (!snap.exists) 'createdAt': FieldValue.serverTimestamp(),
      };
      await ref.set(data, SetOptions(merge: true));
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

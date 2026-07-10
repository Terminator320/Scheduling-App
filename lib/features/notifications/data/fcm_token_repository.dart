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

  /// Upserts a device token. The field set is exactly the five the security
  /// rule allows (`hasOnly([platform, locale, uid, createdAt, updatedAt])`).
  Future<void> upsertToken({
    required String userDocId,
    required String token,
    required String platform,
    required String locale,
    required String uid,
  }) async {
    try {
      await _tokenDoc(userDocId, token).set({
        'platform': platform,
        'locale': locale,
        'uid': uid,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
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

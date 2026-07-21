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
  /// Deliberately a plain get-then-set, NOT a transaction: the sign-in fan-out
  /// runs this concurrently with the Live Activity token upserts, and
  /// concurrent client transactions hit an unsynchronized-dictionary race in
  /// the cloud_firestore iOS plugin (EXC_BAD_ACCESS in
  /// FLTTransactionStreamHandler, seen fatal in Crashlytics; unfixed upstream
  /// as of 6.7.0). The worst the get/set race can do is re-stamp `createdAt`
  /// milliseconds later on a same-token double-upsert — cosmetic, and worth
  /// trading for a crash-free registration path. Same shape in
  /// `LiveActivityTokenRepository.upsertToken`; don't reintroduce
  /// `runTransaction` in either.
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

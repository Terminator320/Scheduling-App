import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/features/live_activity/domain/live_activity_token.dart';

/// Reads/writes the `users/{docId}/liveActivityTokens/{id}` APNs token docs
/// the server uses to start, update and end Live Activity cards. Injected
/// Firestore (never `FirebaseFirestore.instance` from UI); logs and swallows
/// failures so a token write never breaks a flow.
class LiveActivityTokenRepository {
  LiveActivityTokenRepository({
    required FirebaseFirestore firestore,
    AppLogger? logger,
  }) : _firestore = firestore,
       _logger = logger ?? AppLogger();

  final FirebaseFirestore _firestore;
  final AppLogger _logger;

  DocumentReference<Map<String, dynamic>> _tokenDoc(
    String userDocId,
    String docId,
  ) => _firestore
      .collection('users')
      .doc(userDocId)
      .collection('liveActivityTokens')
      .doc(docId);

  /// Upserts a Live Activity token. `createdAt` is stamped only on first
  /// create so an iOS token rotation (which re-upserts) preserves the original
  /// registration time; every write refreshes `updatedAt`.
  ///
  /// Deliberately a plain get-then-set, NOT a transaction — the sign-in
  /// fan-out runs the push-to-start and update-token upserts concurrently
  /// with `FcmTokenRepository.upsertToken`, and concurrent client
  /// transactions crash the cloud_firestore iOS plugin (see the note there;
  /// don't reintroduce `runTransaction` in either repo). A double-upsert can
  /// only re-stamp `createdAt` — cosmetic.
  ///
  /// `platform` is always `ios` — Live Activities do not exist elsewhere, and
  /// the security rule pins the field to that value.
  Future<void> upsertToken({
    required String userDocId,
    required String docId,
    required String token,
    required LiveActivityTokenKind kind,
    required String locale,
    required String uid,
    required DateTime expiresAt,
  }) async {
    try {
      final ref = _tokenDoc(userDocId, docId);
      final snap = await ref.get();
      final data = <String, dynamic>{
        'token': token,
        'kind': kind.raw,
        'employeeDocId': userDocId,
        'platform': 'ios',
        'locale': locale,
        'uid': uid,
        'expiresAt': Timestamp.fromDate(expiresAt),
        'updatedAt': FieldValue.serverTimestamp(),
        if (!snap.exists) 'createdAt': FieldValue.serverTimestamp(),
      };
      await ref.set(data, SetOptions(merge: true));
    } catch (e, st) {
      _logger.warn('LIVE-ACT upsertToken failed', e, st);
    }
  }

  /// Deletes every row of [kind] for this user, without needing the token
  /// value. A push-to-start row's doc id IS its token, so an opt-out that
  /// happens before the token stream has emitted (or on a cold start that
  /// never registered) has no id to delete by — but it must still clear the
  /// row, or the server keeps push-starting cards on an opted-out device.
  Future<void> deleteTokensOfKind({
    required String userDocId,
    required LiveActivityTokenKind kind,
  }) async {
    try {
      final snap = await _firestore
          .collection('users')
          .doc(userDocId)
          .collection('liveActivityTokens')
          .where('kind', isEqualTo: kind.raw)
          .get();
      await Future.wait(snap.docs.map((doc) => doc.reference.delete()));
    } catch (e, st) {
      _logger.warn('LIVE-ACT deleteTokensOfKind failed', e, st);
    }
  }

  Future<void> deleteToken({
    required String userDocId,
    required String docId,
  }) async {
    try {
      await _tokenDoc(userDocId, docId).delete();
    } catch (e, st) {
      _logger.warn('LIVE-ACT deleteToken failed', e, st);
    }
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/features/live_activity/domain/live_activity_token.dart';

/// Reads/writes `users/{docId}/liveActivityTokens/{id}` APNs token docs for starting, updating, and ending cards; logs and swallows failures.
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

  /// Upserts a Live Activity token with createdAt only on first write; plain get-then-set, not a transaction, since concurrent transactions crash the cloud_firestore iOS plugin.
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

  /// Deletes every row of [kind] without needing the token value (push-to-start doc id IS the token, which opt-out may never have seen).
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

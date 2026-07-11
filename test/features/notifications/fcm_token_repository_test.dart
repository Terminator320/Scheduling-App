// Mocktail-style stubs of sealed Firestore types (the canonical workaround
// for testing repos without fake_cloud_firestore).
// ignore_for_file: subtype_of_sealed_class

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:scheduling/features/notifications/data/fcm_token_repository.dart';

class _MockFirestore extends Mock implements FirebaseFirestore {}

class _MockCollection extends Mock
    implements CollectionReference<Map<String, dynamic>> {}

class _MockDoc extends Mock
    implements DocumentReference<Map<String, dynamic>> {}

class _MockSnap extends Mock
    implements DocumentSnapshot<Map<String, dynamic>> {}

class _MockTransaction extends Mock implements Transaction {}

// Typed tear-off so registerFallbackValue records the exact
// `Future<void> Function(Transaction)` type runTransaction's handler expects.
Future<void> _noopTxnHandler(Transaction _) async {}

void main() {
  late _MockFirestore firestore;
  late _MockCollection usersCol;
  late _MockDoc userDoc;
  late _MockCollection tokensCol;
  late _MockDoc tokenDoc;
  late _MockSnap tokenSnap;
  late _MockTransaction txn;
  late List<Map<String, dynamic>> setData;

  setUpAll(() {
    registerFallbackValue(SetOptions(merge: true));
    registerFallbackValue(<String, dynamic>{});
    registerFallbackValue(_noopTxnHandler);
    registerFallbackValue(Duration.zero);
  });

  setUp(() {
    firestore = _MockFirestore();
    usersCol = _MockCollection();
    userDoc = _MockDoc();
    tokensCol = _MockCollection();
    tokenDoc = _MockDoc();
    tokenSnap = _MockSnap();
    txn = _MockTransaction();
    setData = [];
    when(() => firestore.collection('users')).thenReturn(usersCol);
    when(() => usersCol.doc('u1')).thenReturn(userDoc);
    when(() => userDoc.collection('fcmTokens')).thenReturn(tokensCol);
    when(() => tokensCol.doc('tok')).thenReturn(tokenDoc);
    when(() => tokenDoc.delete()).thenAnswer((_) async {});
    // upsertToken runs its get + set inside a transaction; drive the handler
    // with the mock transaction.
    when(
      () => firestore.runTransaction<void>(
        any(),
        timeout: any(named: 'timeout'),
        maxAttempts: any(named: 'maxAttempts'),
      ),
    ).thenAnswer((inv) async {
      final handler =
          inv.positionalArguments.first as Future<void> Function(Transaction);
      await handler(txn);
    });
    when(() => txn.get(tokenDoc)).thenAnswer((_) async => tokenSnap);
    // Record the written payload here (rather than verify(captureAny())) so the
    // assertion doesn't hinge on mocktail's concrete-vs-matcher arg mixing.
    when(() => txn.set<Map<String, dynamic>>(tokenDoc, any(), any()))
        .thenAnswer((inv) {
      setData.add(
        (inv.positionalArguments[1] as Map).cast<String, dynamic>(),
      );
      return txn;
    });
  });

  test('upsertToken on a new doc stamps createdAt (rule-allowed field set)',
      () async {
    when(() => tokenSnap.exists).thenReturn(false);
    final repo = FcmTokenRepository(firestore: firestore);
    await repo.upsertToken(
      userDocId: 'u1',
      token: 'tok',
      platform: 'android',
      locale: 'fr',
      uid: 'uid1',
    );

    final captured = setData.single;
    expect(
      captured.keys.toSet(),
      {'platform', 'locale', 'uid', 'createdAt', 'updatedAt'},
    );
    expect(captured['platform'], 'android');
    expect(captured['locale'], 'fr');
    expect(captured['uid'], 'uid1');
  });

  test('upsertToken on an existing doc preserves createdAt (omits it)',
      () async {
    when(() => tokenSnap.exists).thenReturn(true);
    final repo = FcmTokenRepository(firestore: firestore);
    await repo.upsertToken(
      userDocId: 'u1',
      token: 'tok',
      platform: 'ios',
      locale: 'en',
      uid: 'uid1',
    );

    final captured = setData.single;
    // A refresh must not re-stamp createdAt, but still refreshes updatedAt and
    // stays within the rule allowlist (subset is permitted by hasOnly).
    expect(captured.containsKey('createdAt'), isFalse);
    expect(
      captured.keys.toSet(),
      {'platform', 'locale', 'uid', 'updatedAt'},
    );
  });

  test('deleteToken deletes the token doc', () async {
    final repo = FcmTokenRepository(firestore: firestore);
    await repo.deleteToken(userDocId: 'u1', token: 'tok');
    verify(() => tokenDoc.delete()).called(1);
  });
}

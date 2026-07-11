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

void main() {
  late _MockFirestore firestore;
  late _MockCollection usersCol;
  late _MockDoc userDoc;
  late _MockCollection tokensCol;
  late _MockDoc tokenDoc;
  late _MockSnap tokenSnap;

  setUpAll(() {
    registerFallbackValue(SetOptions(merge: true));
  });

  setUp(() {
    firestore = _MockFirestore();
    usersCol = _MockCollection();
    userDoc = _MockDoc();
    tokensCol = _MockCollection();
    tokenDoc = _MockDoc();
    tokenSnap = _MockSnap();
    when(() => firestore.collection('users')).thenReturn(usersCol);
    when(() => usersCol.doc('u1')).thenReturn(userDoc);
    when(() => userDoc.collection('fcmTokens')).thenReturn(tokensCol);
    when(() => tokensCol.doc('tok')).thenReturn(tokenDoc);
    when(() => tokenDoc.get()).thenAnswer((_) async => tokenSnap);
    when(() => tokenDoc.set(any(), any())).thenAnswer((_) async {});
    when(() => tokenDoc.delete()).thenAnswer((_) async {});
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

    final captured =
        (verify(() => tokenDoc.set(captureAny(), any())).captured.single as Map)
            .cast<String, dynamic>();
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

    final captured =
        (verify(() => tokenDoc.set(captureAny(), any())).captured.single as Map)
            .cast<String, dynamic>();
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

// Mocktail-style stubs of sealed Firestore types (the canonical workaround
// for testing repos without fake_cloud_firestore). Mirrors
// test/features/presence/presence_repository_test.dart.
// ignore_for_file: subtype_of_sealed_class

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:scheduling/features/live_activity/data/live_activity_token_repository.dart';
import 'package:scheduling/features/live_activity/domain/live_activity_token.dart';

class _MockFirestore extends Mock implements FirebaseFirestore {}

class _MockCollection extends Mock
    implements CollectionReference<Map<String, dynamic>> {}

class _MockDoc extends Mock implements DocumentReference<Map<String, dynamic>> {}

class _MockSnapshot extends Mock
    implements DocumentSnapshot<Map<String, dynamic>> {}

class _MockQuery extends Mock implements Query<Map<String, dynamic>> {}

class _MockQuerySnapshot extends Mock
    implements QuerySnapshot<Map<String, dynamic>> {}

class _MockQueryDoc extends Mock
    implements QueryDocumentSnapshot<Map<String, dynamic>> {}

void main() {
  late _MockFirestore firestore;
  late _MockCollection usersCol;
  late _MockDoc userDoc;
  late _MockCollection tokensCol;
  late _MockDoc tokenDoc;
  late _MockSnapshot snapshot;
  late List<Map<String, dynamic>> setData;
  late List<SetOptions?> setOptions;

  final expiry = DateTime.utc(2026, 8, 1, 12);

  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
    registerFallbackValue(SetOptions(merge: true));
  });

  setUp(() {
    firestore = _MockFirestore();
    usersCol = _MockCollection();
    userDoc = _MockDoc();
    tokensCol = _MockCollection();
    tokenDoc = _MockDoc();
    snapshot = _MockSnapshot();
    setData = [];
    setOptions = [];

    when(() => firestore.collection('users')).thenReturn(usersCol);
    when(() => usersCol.doc('u1')).thenReturn(userDoc);
    when(
      () => userDoc.collection('liveActivityTokens'),
    ).thenReturn(tokensCol);
    when(() => tokensCol.doc(any())).thenReturn(tokenDoc);
    when(() => tokenDoc.get()).thenAnswer((_) async => snapshot);
    when(() => snapshot.exists).thenReturn(false);
    when(() => tokenDoc.set(any(), any())).thenAnswer((inv) async {
      setData.add(
        (inv.positionalArguments.first as Map).cast<String, dynamic>(),
      );
      setOptions.add(inv.positionalArguments[1] as SetOptions?);
    });
  });

  Future<void> upsert(LiveActivityTokenRepository repo) => repo.upsertToken(
    userDocId: 'u1',
    docId: 'tok-abc',
    token: 'tok-abc',
    kind: LiveActivityTokenKind.pushToStart,
    locale: 'en',
    uid: 'uid-1',
    expiresAt: expiry,
  );

  group('upsertToken', () {
    test('stamps createdAt only when the doc does not exist', () async {
      when(() => snapshot.exists).thenReturn(false);
      final repo = LiveActivityTokenRepository(firestore: firestore);
      await upsert(repo);

      final data = setData.single;
      expect(data.containsKey('createdAt'), isTrue);
      expect(data['createdAt'], isA<FieldValue>());
    });

    test('omits createdAt when the doc already exists', () async {
      when(() => snapshot.exists).thenReturn(true);
      final repo = LiveActivityTokenRepository(firestore: firestore);
      await upsert(repo);

      expect(setData.single.containsKey('createdAt'), isFalse);
    });

    test('always refreshes updatedAt with a server timestamp', () async {
      when(() => snapshot.exists).thenReturn(true);
      final repo = LiveActivityTokenRepository(firestore: firestore);
      await upsert(repo);

      expect(setData.single['updatedAt'], isA<FieldValue>());
    });

    test('writes exactly the rule-allowed field set with platform ios',
        () async {
      when(() => snapshot.exists).thenReturn(false);
      final repo = LiveActivityTokenRepository(firestore: firestore);
      await repo.upsertToken(
        userDocId: 'u1',
        docId: 'act-1',
        token: 'update-tok',
        kind: LiveActivityTokenKind.update,
        locale: 'fr',
        uid: 'uid-1',
        expiresAt: expiry,
      );

      final data = setData.single;
      expect(data.keys.toSet(), {
        'token',
        'kind',
        'employeeDocId',
        'platform',
        'locale',
        'uid',
        'expiresAt',
        'updatedAt',
        'createdAt',
      });
      expect(data['token'], 'update-tok');
      expect(data['kind'], 'update');
      expect(data['employeeDocId'], 'u1');
      expect(data['platform'], 'ios');
      expect(data['locale'], 'fr');
      expect(data['uid'], 'uid-1');
      expect(data['expiresAt'], Timestamp.fromDate(expiry));
    });

    test('uses a merge set so a re-upsert preserves untouched fields',
        () async {
      final repo = LiveActivityTokenRepository(firestore: firestore);
      await upsert(repo);

      expect(setOptions.single?.merge, isTrue);
    });

    test('swallows a get/set failure and never throws', () async {
      when(() => tokenDoc.set(any(), any())).thenThrow(Exception('offline'));
      final repo = LiveActivityTokenRepository(firestore: firestore);
      await expectLater(upsert(repo), completes);
    });
  });

  group('deleteTokensOfKind', () {
    late _MockQuery query;
    late _MockQuerySnapshot querySnap;

    setUp(() {
      query = _MockQuery();
      querySnap = _MockQuerySnapshot();
      when(
        () => tokensCol.where('kind', isEqualTo: 'pushToStart'),
      ).thenReturn(query);
      when(() => query.get()).thenAnswer((_) async => querySnap);
    });

    _MockQueryDoc matchedDoc(_MockDoc ref) {
      final doc = _MockQueryDoc();
      when(() => doc.reference).thenReturn(ref);
      return doc;
    }

    test('queries where kind == kind.raw and deletes every matched doc',
        () async {
      final refA = _MockDoc();
      final refB = _MockDoc();
      when(refA.delete).thenAnswer((_) async {});
      when(refB.delete).thenAnswer((_) async {});
      final docA = matchedDoc(refA);
      final docB = matchedDoc(refB);
      when(() => querySnap.docs).thenReturn([docA, docB]);

      final repo = LiveActivityTokenRepository(firestore: firestore);
      await repo.deleteTokensOfKind(
        userDocId: 'u1',
        kind: LiveActivityTokenKind.pushToStart,
      );

      verify(() => tokensCol.where('kind', isEqualTo: 'pushToStart')).called(1);
      verify(refA.delete).called(1);
      verify(refB.delete).called(1);
    });

    test('no matched docs deletes nothing and does not throw', () async {
      when(() => querySnap.docs).thenReturn([]);
      final repo = LiveActivityTokenRepository(firestore: firestore);
      await expectLater(
        repo.deleteTokensOfKind(
          userDocId: 'u1',
          kind: LiveActivityTokenKind.pushToStart,
        ),
        completes,
      );
    });

    test('swallows a query failure and never throws', () async {
      when(() => query.get()).thenThrow(Exception('rules'));
      final repo = LiveActivityTokenRepository(firestore: firestore);
      await expectLater(
        repo.deleteTokensOfKind(
          userDocId: 'u1',
          kind: LiveActivityTokenKind.pushToStart,
        ),
        completes,
      );
    });

    test('swallows a per-doc delete failure and never throws', () async {
      final ref = _MockDoc();
      when(ref.delete).thenThrow(Exception('denied'));
      final doc = matchedDoc(ref);
      when(() => querySnap.docs).thenReturn([doc]);
      final repo = LiveActivityTokenRepository(firestore: firestore);
      await expectLater(
        repo.deleteTokensOfKind(
          userDocId: 'u1',
          kind: LiveActivityTokenKind.pushToStart,
        ),
        completes,
      );
    });
  });

  group('deleteToken', () {
    test('deletes the addressed token doc', () async {
      when(() => tokenDoc.delete()).thenAnswer((_) async {});
      final repo = LiveActivityTokenRepository(firestore: firestore);
      await repo.deleteToken(userDocId: 'u1', docId: 'act-1');

      verify(() => tokenDoc.delete()).called(1);
    });

    test('swallows a delete failure and never throws', () async {
      when(() => tokenDoc.delete()).thenThrow(Exception('offline'));
      final repo = LiveActivityTokenRepository(firestore: firestore);
      await expectLater(
        repo.deleteToken(userDocId: 'u1', docId: 'act-1'),
        completes,
      );
    });
  });
}

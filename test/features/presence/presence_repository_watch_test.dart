// Mocktail-style stubs of sealed Firestore types (the canonical workaround
// for testing repos without fake_cloud_firestore).
// ignore_for_file: subtype_of_sealed_class

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:scheduling/features/presence/data/presence_repository.dart';

class _MockFirestore extends Mock implements FirebaseFirestore {}

class _MockQuery extends Mock implements Query<Map<String, dynamic>> {}

class _MockQuerySnapshot extends Mock
    implements QuerySnapshot<Map<String, dynamic>> {}

class _MockQueryDocSnapshot extends Mock
    implements QueryDocumentSnapshot<Map<String, dynamic>> {}

class _MockDocRef extends Mock
    implements DocumentReference<Map<String, dynamic>> {}

class _MockCollectionRef extends Mock
    implements CollectionReference<Map<String, dynamic>> {}

/// Builds a mocked presence doc at `users/{userDocId}/presence/location`.
_MockQueryDocSnapshot _presenceDoc(
  String userDocId,
  Map<String, dynamic> data,
) {
  final userDoc = _MockDocRef();
  when(() => userDoc.id).thenReturn(userDocId);
  final presenceCollection = _MockCollectionRef();
  when(() => presenceCollection.parent).thenReturn(userDoc);
  final locationDoc = _MockDocRef();
  when(() => locationDoc.parent).thenReturn(presenceCollection);
  final doc = _MockQueryDocSnapshot();
  when(() => doc.reference).thenReturn(locationDoc);
  when(doc.data).thenReturn(data);
  return doc;
}

void main() {
  late _MockFirestore firestore;
  late _MockQuery query;

  setUp(() {
    firestore = _MockFirestore();
    query = _MockQuery();
    when(() => firestore.collectionGroup('presence')).thenReturn(query);
    // The feed is bounded by `.limit(...)` (mirrors the users-stream cap); the
    // mock chains it back to the same query so `.snapshots()` still resolves.
    when(() => query.limit(any())).thenReturn(query);
  });

  void stubSnapshots(Stream<QuerySnapshot<Map<String, dynamic>>> stream) {
    when(() => query.snapshots()).thenAnswer((_) => stream);
  }

  // `docs` must be fully built before stubbing `snapshot.docs` — mocktail can't handle a nested `when()` while the outer stub call is open.
  _MockQuerySnapshot snapshotOf(List<_MockQueryDocSnapshot> docs) {
    final snapshot = _MockQuerySnapshot();
    when(() => snapshot.docs).thenReturn(docs);
    return snapshot;
  }

  test(
    'maps a collection-group snapshot to fixes with the parent users-doc id',
    () async {
      final updatedAt = Timestamp.fromDate(DateTime(2026, 7, 17, 12));
      final doc = _presenceDoc('u1', {
        'lat': 45.5,
        'lng': -73.6,
        'updatedAt': updatedAt,
      });
      stubSnapshots(Stream.value(snapshotOf([doc])));

      final repo = PresenceRepository(firestore: firestore);
      final fixes = await repo.watchAllPresence().first;

      expect(fixes, hasLength(1));
      expect(fixes.single.userDocId, 'u1');
      expect(fixes.single.lat, 45.5);
      expect(fixes.single.lng, -73.6);
      expect(fixes.single.updatedAt, updatedAt.toDate());
    },
  );

  test('skips a malformed doc while siblings survive', () async {
    final badDoc = _presenceDoc('bad', {'lat': 'not-a-number', 'lng': -73.6});
    final goodDoc = _presenceDoc('good', {'lat': 1.0, 'lng': 2.0});
    stubSnapshots(Stream.value(snapshotOf([badDoc, goodDoc])));

    final repo = PresenceRepository(firestore: firestore);
    final fixes = await repo.watchAllPresence().first;

    expect(fixes, hasLength(1));
    expect(fixes.single.userDocId, 'good');
  });

  test('missing updatedAt maps to null', () async {
    final doc = _presenceDoc('u1', {'lat': 1.0, 'lng': 2.0});
    stubSnapshots(Stream.value(snapshotOf([doc])));

    final repo = PresenceRepository(firestore: firestore);
    final fixes = await repo.watchAllPresence().first;

    expect(fixes.single.updatedAt, isNull);
  });

  test('a stream error propagates to the listener', () async {
    stubSnapshots(Stream.error(Exception('boom')));

    final repo = PresenceRepository(firestore: firestore);

    await expectLater(repo.watchAllPresence(), emitsError(isException));
  });
}

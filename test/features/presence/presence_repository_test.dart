// Mocktail-style stubs of sealed Firestore types (the canonical workaround
// for testing repos without fake_cloud_firestore).
// ignore_for_file: subtype_of_sealed_class

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:scheduling/features/presence/data/presence_repository.dart';

class _MockFirestore extends Mock implements FirebaseFirestore {}

class _MockCollection extends Mock
    implements CollectionReference<Map<String, dynamic>> {}

class _MockDoc extends Mock
    implements DocumentReference<Map<String, dynamic>> {}

void main() {
  late _MockFirestore firestore;
  late _MockCollection usersCol;
  late _MockDoc userDoc;
  late _MockCollection presenceCol;
  late _MockDoc locationDoc;
  late List<Map<String, dynamic>> setData;

  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
  });

  setUp(() {
    firestore = _MockFirestore();
    usersCol = _MockCollection();
    userDoc = _MockDoc();
    presenceCol = _MockCollection();
    locationDoc = _MockDoc();
    setData = [];
    when(() => firestore.collection('users')).thenReturn(usersCol);
    when(() => usersCol.doc('u1')).thenReturn(userDoc);
    when(() => userDoc.collection('presence')).thenReturn(presenceCol);
    when(() => presenceCol.doc('location')).thenReturn(locationDoc);
    when(() => locationDoc.set(any())).thenAnswer((inv) async {
      setData.add(
        (inv.positionalArguments.first as Map).cast<String, dynamic>(),
      );
    });
    when(() => locationDoc.delete()).thenAnswer((_) async {});
  });

  test('upsertLocation writes exactly the rule-allowed field set', () async {
    final repo = PresenceRepository(firestore: firestore);
    await repo.upsertLocation(
      userDocId: 'u1',
      uid: 'uid1',
      lat: 45.5,
      lng: -73.6,
    );

    final captured = setData.single;
    expect(captured.keys.toSet(), {'lat', 'lng', 'uid', 'updatedAt'});
    expect(captured['lat'], 45.5);
    expect(captured['lng'], -73.6);
    expect(captured['uid'], 'uid1');
    // The rule requires updatedAt == request.time, i.e. a server timestamp.
    expect(captured['updatedAt'], isA<FieldValue>());
  });

  test('upsertLocation swallows a write failure', () async {
    when(() => locationDoc.set(any())).thenThrow(Exception('offline'));
    final repo = PresenceRepository(firestore: firestore);
    await expectLater(
      repo.upsertLocation(userDocId: 'u1', uid: 'uid1', lat: 1, lng: 2),
      completes,
    );
  });

  test('deleteLocation deletes the location doc', () async {
    final repo = PresenceRepository(firestore: firestore);
    await repo.deleteLocation(userDocId: 'u1');
    verify(() => locationDoc.delete()).called(1);
  });

  test('deleteLocation swallows a delete failure', () async {
    when(() => locationDoc.delete()).thenThrow(Exception('rules'));
    final repo = PresenceRepository(firestore: firestore);
    await expectLater(repo.deleteLocation(userDocId: 'u1'), completes);
  });
}

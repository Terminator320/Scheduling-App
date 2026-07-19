// Mocktail fakes must subclass cloud_firestore's sealed query/snapshot types.
// ignore_for_file: subtype_of_sealed_class

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:scheduling/features/calendar/data/firebase_appointments_repository.dart';

class _MockFirestore extends Mock implements FirebaseFirestore {}

class _MockCollection extends Mock
    implements CollectionReference<Map<String, dynamic>> {}

class _MockQuery extends Mock implements Query<Map<String, dynamic>> {}

class _MockQuerySnapshot extends Mock
    implements QuerySnapshot<Map<String, dynamic>> {}

class _MockDocSnap extends Mock
    implements QueryDocumentSnapshot<Map<String, dynamic>> {}

void main() {
  late _MockFirestore firestore;
  late _MockCollection collection;
  late _MockQuery query;
  late _MockQuerySnapshot snapshot;

  _MockDocSnap doc(String id, Map<String, dynamic> data) {
    final d = _MockDocSnap();
    when(() => d.id).thenReturn(id);
    when(d.data).thenReturn(data);
    return d;
  }

  setUp(() {
    firestore = _MockFirestore();
    collection = _MockCollection();
    query = _MockQuery();
    snapshot = _MockQuerySnapshot();

    when(() => firestore.collection('appointments')).thenReturn(collection);
    when(
      () => collection.where('clientId', isEqualTo: any(named: 'isEqualTo')),
    ).thenReturn(query);
    when(() => query.limit(any())).thenReturn(query);
    when(() => query.get()).thenAnswer((_) async => snapshot);

    // Deliberately NOT in start-time order: the repository must sort in Dart.
    final docs = [
      doc('older', {
        'clientId': 'c1',
        'title': 'Leak repair',
        'startTime': Timestamp.fromDate(DateTime(2026, 1, 10, 9)),
        'endTime': Timestamp.fromDate(DateTime(2026, 1, 10, 10)),
        'status': 'done',
      }),
      doc('newer', {
        'clientId': 'c1',
        'title': 'Water heater',
        'startTime': Timestamp.fromDate(DateTime(2026, 6, 1, 14)),
        'endTime': Timestamp.fromDate(DateTime(2026, 6, 1, 15)),
        'status': 'done',
      }),
    ];
    when(() => snapshot.docs).thenReturn(docs);
  });

  FirebaseAppointmentsRepository repo() =>
      FirebaseAppointmentsRepository(firestore);

  test('filters by clientId and applies the limit (no orderBy)', () async {
    await repo().fetchClientHistory(clientId: 'c1', limit: 25);
    verify(() => collection.where('clientId', isEqualTo: 'c1')).called(1);
    verify(() => query.limit(25)).called(1);
    // No composite index: the query must never add a server-side orderBy.
    verifyNever(() => query.orderBy(any()));
  });

  test('sorts most-recent first in Dart regardless of doc order', () async {
    final result = await repo().fetchClientHistory(clientId: 'c1');
    expect(result.map((a) => a.id), ['newer', 'older']);
  });

  test('defaults to a bounded limit of 50', () async {
    await repo().fetchClientHistory(clientId: 'c1');
    verify(() => query.limit(50)).called(1);
  });

  test('returns empty without querying for a blank clientId', () async {
    expect(await repo().fetchClientHistory(clientId: ''), isEmpty);
    verifyNever(() => query.get());
  });
}

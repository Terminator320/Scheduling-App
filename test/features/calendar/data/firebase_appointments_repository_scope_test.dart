// Mocktail fakes must subclass cloud_firestore's sealed query/snapshot types.
// ignore_for_file: subtype_of_sealed_class

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:scheduling/features/calendar/data/firebase_appointments_repository.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';

class _MockFirestore extends Mock implements FirebaseFirestore {}

class _MockCollection extends Mock
    implements CollectionReference<Map<String, dynamic>> {}

class _MockDoc extends Mock
    implements DocumentReference<Map<String, dynamic>> {}

class _MockQuery extends Mock implements Query<Map<String, dynamic>> {}

class _MockQuerySnapshot extends Mock
    implements QuerySnapshot<Map<String, dynamic>> {}

class _MockDocSnap extends Mock
    implements QueryDocumentSnapshot<Map<String, dynamic>> {}

class _FakeDocSnap extends Fake
    implements QueryDocumentSnapshot<Map<String, dynamic>> {}

/// A technician's History is the business-wide terminal archive narrowed by
/// `employeeIds`.
void main() {
  setUpAll(() {
    registerFallbackValue(_FakeDocSnap());
    registerFallbackValue(<String, dynamic>{});
  });

  late _MockFirestore firestore;
  late _MockCollection collection;
  late _MockDoc doc;

  /// The unscoped chain, and the scoped chain that hangs off `arrayContains`.
  late _MockQuery adminQuery;
  late _MockQuery scopedQuery;
  late _MockQuerySnapshot adminSnapshot;
  late _MockQuerySnapshot scopedSnapshot;

  _MockDocSnap hit(String id, Map<String, dynamic> data) {
    final d = _MockDocSnap();
    when(() => d.id).thenReturn(id);
    when(d.data).thenReturn(data);
    return d;
  }

  void stubChain(_MockQuery query, _MockQuerySnapshot snapshot) {
    when(
      () => query.where('status', whereIn: any(named: 'whereIn')),
    ).thenReturn(query);
    when(
      () => query.orderBy(any(), descending: any(named: 'descending')),
    ).thenReturn(query);
    when(() => query.limit(any())).thenReturn(query);
    when(() => query.startAfterDocument(any())).thenReturn(query);
    when(() => query.get()).thenAnswer((_) async => snapshot);
  }

  setUp(() {
    firestore = _MockFirestore();
    collection = _MockCollection();
    doc = _MockDoc();
    adminQuery = _MockQuery();
    scopedQuery = _MockQuery();
    adminSnapshot = _MockQuerySnapshot();
    scopedSnapshot = _MockQuerySnapshot();

    when(() => firestore.collection('appointments')).thenReturn(collection);
    when(() => collection.doc(any())).thenReturn(doc);
    when(() => doc.update(any())).thenAnswer((_) async {});

    // Business-wide: status is the first constraint on the collection.
    when(
      () => collection.where('status', whereIn: any(named: 'whereIn')),
    ).thenReturn(adminQuery);
    stubChain(adminQuery, adminSnapshot);

    // Scoped: `arrayContains` first, then the same chain.
    when(
      () => collection.where(
        'employeeIds',
        arrayContains: any(named: 'arrayContains'),
      ),
    ).thenReturn(scopedQuery);
    stubChain(scopedQuery, scopedSnapshot);

    final marcsJob = hit('a1', {
      'clientName': 'Sophie Tremblay',
      'employeeIds': ['e1'],
      'employeeNames': ['Marc'],
      'status': 'done',
      'startTime': Timestamp.fromDate(DateTime(2026, 6, 24, 9)),
      'endTime': Timestamp.fromDate(DateTime(2026, 6, 24, 10)),
    });
    final zoesJob = hit('a2', {
      'clientName': 'Sophie Tremblay',
      'employeeIds': ['e2'],
      'employeeNames': ['Zoé'],
      'status': 'done',
      'startTime': Timestamp.fromDate(DateTime(2026, 6, 23, 9)),
      'endTime': Timestamp.fromDate(DateTime(2026, 6, 23, 10)),
    });
    when(() => adminSnapshot.docs).thenReturn([marcsJob, zoesJob]);
    when(() => scopedSnapshot.docs).thenReturn([marcsJob]);
  });

  FirebaseAppointmentsRepository repo() =>
      FirebaseAppointmentsRepository(firestore);

  group('the paged history query', () {
    test('narrows to the assignee when a scope is given', () async {
      await repo().fetchHistoryPage(limit: 25, employeeId: 'e1');

      verify(
        () => collection.where('employeeIds', arrayContains: 'e1'),
      ).called(1);
      verify(
        () => scopedQuery.where('status', whereIn: any(named: 'whereIn')),
      ).called(1);
    });

    test('stays business-wide without one', () async {
      await repo().fetchHistoryPage(limit: 25);

      verifyNever(
        () => collection.where(
          'employeeIds',
          arrayContains: any(named: 'arrayContains'),
        ),
      );
    });
  });

  group('the search scan window', () {
    test("a scoped search reads only that person's archive", () async {
      final results = await repo().searchHistory('sophie', employeeId: 'e1');

      expect(results.map((a) => a.id), ['a1']);
      verifyNever(() => adminQuery.get());
    });

    test('the two scopes are cached apart', () async {
      final r = repo();

      final everyone = await r.searchHistory('sophie');
      final marcs = await r.searchHistory('sophie', employeeId: 'e1');
      // Both again, from cache.
      await r.searchHistory('sophie');
      await r.searchHistory('sophie', employeeId: 'e1');

      expect(everyone.map((a) => a.id), ['a1', 'a2']);
      expect(marcs.map((a) => a.id), ['a1']);
      verify(() => adminQuery.get()).called(1);
      verify(() => scopedQuery.get()).called(1);
    });

    test('a local write that unassigns the person drops the job from '
        'THEIR window and keeps it in the archive', () async {
      final r = repo();
      await r.searchHistory('sophie');
      await r.searchHistory('sophie', employeeId: 'e1');

      // Marc is taken off a1; it is still done, so history keeps it.
      await r.updateAppointment(
        AppointmentRecord(
          id: 'a1',
          title: 'Leak',
          clientName: 'Sophie Tremblay',
          startTime: DateTime(2026, 6, 24, 9),
          endTime: DateTime(2026, 6, 24, 10),
          employeeIds: const ['e2'],
          employeeNames: const ['Zoé'],
          status: 'done',
        ),
      );

      final everyone = await r.searchHistory('sophie');
      final marcs = await r.searchHistory('sophie', employeeId: 'e1');

      expect(everyone.map((a) => a.id), ['a1', 'a2']);
      expect(marcs, isEmpty);
      // Patched, not re-paged: neither window was fetched again.
      verify(() => adminQuery.get()).called(1);
      verify(() => scopedQuery.get()).called(1);
    });

    test('clearCaches forgets every scope', () async {
      final r = repo();
      await r.searchHistory('sophie');
      await r.searchHistory('sophie', employeeId: 'e1');

      r.clearCaches();
      await r.searchHistory('sophie');
      await r.searchHistory('sophie', employeeId: 'e1');

      verify(() => adminQuery.get()).called(2);
      verify(() => scopedQuery.get()).called(2);
    });
  });
}

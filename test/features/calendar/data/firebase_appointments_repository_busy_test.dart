// Mocktail fakes must subclass cloud_firestore's sealed query/snapshot types.
// ignore_for_file: subtype_of_sealed_class

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:scheduling/features/calendar/data/firebase_appointments_repository.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';

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

  _MockDocSnap doc(Map<String, dynamic> data, {String id = 'appt'}) {
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
      () => collection.where(
        'employeeIds',
        arrayContainsAny: any(named: 'arrayContainsAny'),
      ),
    ).thenReturn(query);
    when(
      () => query.where('startTime', isLessThan: any(named: 'isLessThan')),
    ).thenReturn(query);
    when(
      () => query.where('endTime', isGreaterThan: any(named: 'isGreaterThan')),
    ).thenReturn(query);
    when(() => query.limit(any())).thenReturn(query);
    when(() => query.get()).thenAnswer((_) async => snapshot);
    when(() => snapshot.docs).thenReturn(const []);
  });

  FirebaseAppointmentsRepository repo() =>
      FirebaseAppointmentsRepository(firestore);

  List<EmployeeRecord> employees(int n) => [
    for (var i = 0; i < n; i++) EmployeeRecord(id: 'e$i'),
  ];

  final start = DateTime(2026, 6, 24, 9);
  final end = DateTime(2026, 6, 24, 10);

  test('returns empty without querying when there are no candidates', () async {
    final result = await repo().findBusyEmployees(
      candidates: const [],
      start: start,
      end: end,
    );
    expect(result, isEmpty);
    verifyNever(() => query.get());
  });

  test('chunks >30 candidate ids into batches of 30 (whereArrayContainsAny '
      'limit) and covers every id exactly once', () async {
    await repo().findBusyEmployees(
      candidates: employees(31),
      start: start,
      end: end,
    );

    final captured = verify(
      () => collection.where(
        'employeeIds',
        arrayContainsAny: captureAny(named: 'arrayContainsAny'),
      ),
    ).captured;

    expect(captured.length, 2, reason: '31 ids -> two batches');
    final batch1 = (captured[0] as List).cast<String>();
    final batch2 = (captured[1] as List).cast<String>();
    expect(batch1.length, 30);
    expect(batch2.length, 1);
    expect({...batch1, ...batch2}.length, 31, reason: 'no overlap, full cover');
  });

  test(
    'bounds every chunk, so a wide booking cannot read without a ceiling',
    () async {
      // Two inequalities bound this in practice, so it is tail risk rather than
      // steady state — but a 14-day booking across a large roster reads every
      // overlapping job for up to 30 assignees per chunk on every Save, and this
      // was the last query in the repository naming no ceiling at all.
      await repo().findBusyEmployees(
        candidates: employees(31),
        start: start,
        end: end,
      );

      final caps = verify(() => query.limit(captureAny())).captured;
      expect(caps.length, 2, reason: 'one cap per chunk, not one for the lot');
      expect(caps.toSet().single, isA<int>());
    },
  );

  test('issues a single query for <=30 candidates', () async {
    await repo().findBusyEmployees(
      candidates: employees(30),
      start: start,
      end: end,
    );
    verify(() => query.get()).called(1);
  });

  test(
    'merges + dedupes busy ids and returns only matching candidates',
    () async {
      // Build the doc mock before stubbing `docs` — mocktail forbids calling
      // `when` (inside doc()) while another stub is being defined.
      final busyDoc = doc({
        'employeeIds': ['e0', 'e5', 'e30'],
      });
      when(() => snapshot.docs).thenReturn([busyDoc]);

      final result = await repo().findBusyEmployees(
        candidates: employees(31),
        start: start,
        end: end,
      );

      expect(result.map((e) => e.id).toSet(), {'e0', 'e5', 'e30'});
    },
  );

  test(
    'excludes the appointment being edited from its own conflicts',
    () async {
      // The only overlapping doc IS the one under edit — editing a job's notes
      // must not report its own assignees as busy.
      final ownDoc = doc({
        'employeeIds': ['e0'],
      }, id: 'a1');
      when(() => snapshot.docs).thenReturn([ownDoc]);

      final result = await repo().findBusyEmployees(
        candidates: employees(1),
        start: start,
        end: end,
        excludeAppointmentId: 'a1',
      );

      expect(result, isEmpty);
    },
  );

  test('still reports a clash with a different appointment', () async {
    final otherDoc = doc({
      'employeeIds': ['e0'],
    }, id: 'a2');
    when(() => snapshot.docs).thenReturn([otherDoc]);

    final result = await repo().findBusyEmployees(
      candidates: employees(1),
      start: start,
      end: end,
      excludeAppointmentId: 'a1',
    );

    // The exclusion is by doc id, so a sibling occurrence of the same series
    // still surfaces.
    expect(result.map((e) => e.id), ['e0']);
  });
}

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

  final now = DateTime.now();

  _MockDocSnap job({
    required String id,
    required DateTime start,
    required DateTime end,
    String status = 'pending',
  }) {
    final d = _MockDocSnap();
    when(() => d.id).thenReturn(id);
    when(d.data).thenReturn({
      'startTime': Timestamp.fromDate(start),
      'endTime': Timestamp.fromDate(end),
      'status': status,
      'employeeIds': const ['e1'],
    });
    return d;
  }

  void withDocs(List<_MockDocSnap> docs) =>
      when(() => snapshot.docs).thenReturn(docs);

  setUp(() {
    firestore = _MockFirestore();
    collection = _MockCollection();
    query = _MockQuery();
    snapshot = _MockQuerySnapshot();

    when(() => firestore.collection('appointments')).thenReturn(collection);
    when(
      () => collection.where(
        'employeeIds',
        arrayContains: any(named: 'arrayContains'),
      ),
    ).thenReturn(query);
    when(
      () => query.where(
        'startTime',
        isGreaterThanOrEqualTo: any(named: 'isGreaterThanOrEqualTo'),
      ),
    ).thenReturn(query);
    when(() => query.get()).thenAnswer((_) async => snapshot);
    withDocs([]);
  });

  FirebaseAppointmentsRepository repo() =>
      FirebaseAppointmentsRepository(firestore);

  test('counts a run already under way, not just one starting later', () async {
    // Day 3 of a 10-day job: the old startTime >= now query reported 0 and the
    // admin disabled someone standing on a job site.
    withDocs([
      job(
        id: 'a',
        start: now.subtract(const Duration(days: 3)),
        end: now.add(const Duration(days: 7)),
      ),
    ]);

    expect(await repo().countFutureAssignments('e1'), 1);
  });

  test('excludes a job completed earlier today', () async {
    // Its window hasn't closed, so the widened floor admits it — only the
    // status test keeps it from reading as "still assigned, reassign it".
    withDocs([
      job(
        id: 'a',
        start: now.subtract(const Duration(hours: 4)),
        end: now.add(const Duration(hours: 4)),
        status: 'done',
      ),
    ]);

    expect(await repo().countFutureAssignments('e1'), 0);
  });

  test('excludes a cancelled job whose window is still open', () async {
    withDocs([
      job(
        id: 'a',
        start: now.subtract(const Duration(hours: 4)),
        end: now.add(const Duration(hours: 4)),
        status: 'cancelled',
      ),
    ]);

    expect(await repo().countFutureAssignments('e1'), 0);
  });

  test('excludes a run that finished inside the widened floor', () async {
    withDocs([
      job(
        id: 'a',
        start: now.subtract(const Duration(days: 10)),
        end: now.subtract(const Duration(days: 2)),
      ),
    ]);

    expect(await repo().countFutureAssignments('e1'), 0);
  });

  test('counts an unknown status as open work', () async {
    withDocs([
      job(
        id: 'a',
        start: now.add(const Duration(days: 1)),
        end: now.add(const Duration(days: 1, hours: 8)),
        status: 'legacy_confirmed',
      ),
    ]);

    expect(await repo().countFutureAssignments('e1'), 1);
  });
}

// Mocktail fakes must subclass cloud_firestore's sealed query/snapshot types.
// ignore_for_file: subtype_of_sealed_class

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/features/calendar/data/firebase_appointments_repository.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';

class _RecordingLogger extends AppLogger {
  final warnings = <String>[];

  @override
  void warn(String message, [Object? error, StackTrace? stack]) {
    warnings.add(message);
  }
}

class _FakeDoc extends Fake
    implements QueryDocumentSnapshot<Map<String, dynamic>> {
  _FakeDoc(this.id, this._data);

  @override
  final String id;

  final Map<String, dynamic> _data;

  @override
  Map<String, dynamic> data() => _data;
}

class _MockFirestore extends Mock implements FirebaseFirestore {}

class _MockCollection extends Mock
    implements CollectionReference<Map<String, dynamic>> {}

class _MockQuery extends Mock implements Query<Map<String, dynamic>> {}

class _MockQuerySnapshot extends Mock
    implements QuerySnapshot<Map<String, dynamic>> {}

void main() {
  late _MockFirestore firestore;
  late _MockCollection collection;
  late _MockQuery query;
  late _MockQuerySnapshot snapshot;
  late _RecordingLogger logger;

  final now = DateTime(2026, 8, 15, 9);

  setUpAll(() {
    registerFallbackValue(_FakeDoc('fallback', const {}));
  });

  setUp(() {
    firestore = _MockFirestore();
    collection = _MockCollection();
    query = _MockQuery();
    snapshot = _MockQuerySnapshot();
    logger = _RecordingLogger();

    when(() => firestore.collection('appointments')).thenReturn(collection);
    when(
      () => collection.where(
        'employeeIds',
        arrayContains: any(named: 'arrayContains'),
      ),
    ).thenReturn(query);
    when(
      () => collection.where(
        'startTime',
        isGreaterThanOrEqualTo: any(named: 'isGreaterThanOrEqualTo'),
      ),
    ).thenReturn(query);
    when(
      () => collection.where('status', whereIn: any(named: 'whereIn')),
    ).thenReturn(query);
    when(
      () => collection.where('clientId', isEqualTo: any(named: 'isEqualTo')),
    ).thenReturn(query);
    when(
      () => query.where(
        'endTime',
        isGreaterThanOrEqualTo: any(named: 'isGreaterThanOrEqualTo'),
      ),
    ).thenReturn(query);
    when(
      () => query.where('startTime', isLessThan: any(named: 'isLessThan')),
    ).thenReturn(query);
    when(
      () => query.orderBy(any(), descending: any(named: 'descending')),
    ).thenReturn(query);
    when(() => query.orderBy(any())).thenReturn(query);
    when(() => query.limit(any())).thenReturn(query);
    when(() => query.startAfterDocument(any())).thenReturn(query);
    when(() => query.get()).thenAnswer((_) async => snapshot);
    when(() => snapshot.docs).thenReturn(const []);
  });

  FirebaseAppointmentsRepository repo() =>
      FirebaseAppointmentsRepository(firestore, logger: logger);

  void withJobs(int count) => when(() => snapshot.docs).thenReturn([
    for (var i = 0; i < count; i++)
      _FakeDoc('a$i', {
        'startTime': Timestamp.fromDate(now.subtract(const Duration(hours: 1))),
        'endTime': Timestamp.fromDate(now.add(const Duration(hours: 4))),
        'status': 'pending',
        'employeeIds': const ['e1'],
      }),
  ]);

  group('countFutureAssignments warns at its cap', () {
    test('a full page warns', () async {
      withJobs(200);

      expect(await repo().countFutureAssignments('e1'), 200);
      expect(logger.warnings, hasLength(1));
      expect(logger.warnings.single, startsWith('APPT-COUNT'));
      expect(logger.warnings.single, contains('200'));
    });

    test('a short page is silent', () async {
      withJobs(199);

      await repo().countFutureAssignments('e1');
      expect(logger.warnings, isEmpty);
    });
  });

  test('fetchInRange no longer truncates through a hard query limit', () async {
    await repo().fetchInRange(
      AppointmentDateRange(
        start: DateTime(2026, 8),
        end: DateTime(2026, 9),
      ),
    );

    verifyNever(() => query.limit(1000));
  });

  test('history search walks additional pages instead of warning at a cap', () async {
    final firstPage = [
      for (var i = 0; i < 500; i++)
        _FakeDoc('h$i', {
          'clientName': 'Sophie Tremblay',
          'employeeNames': const <String>[],
          'status': 'done',
        }),
    ];
    final secondPage = [
      _FakeDoc('h500', {
        'clientName': 'Sophie Tremblay',
        'employeeNames': const <String>[],
        'status': 'done',
      }),
    ];
    final secondSnapshot = _MockQuerySnapshot();
    when(() => snapshot.docs).thenReturn(firstPage);
    when(() => secondSnapshot.docs).thenReturn(secondPage);
    var call = 0;
    when(() => query.get()).thenAnswer((_) async {
      call++;
      return call == 1 ? snapshot : secondSnapshot;
    });

    final result = await repo().searchHistory('sophie');

    expect(result, hasLength(501));
    expect(result.last.id, 'h500');
    expect(logger.warnings, isEmpty);
    verify(() => query.startAfterDocument(firstPage.last)).called(1);
  });
}

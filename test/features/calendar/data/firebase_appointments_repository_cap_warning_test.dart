// Mocktail fakes must subclass cloud_firestore's sealed query/snapshot types.
// ignore_for_file: subtype_of_sealed_class

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/features/calendar/data/firebase_appointments_repository.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';

/// Every bounded read in this repository truncates in SILENCE otherwise — the
/// caller gets a short list that looks exactly like a complete one. The warn is
/// the entire mitigation, and none of the three were asserted anywhere.
class _RecordingLogger extends AppLogger {
  final warnings = <String>[];

  @override
  void warn(String message, [Object? error, StackTrace? stack]) {
    warnings.add(message);
  }
}

/// A plain fake rather than a `Mock`: these tests build a thousand of them, and
/// only `id` and `data()` are ever read.
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
    when(() => query.limit(any())).thenReturn(query);
    when(() => query.get()).thenAnswer((_) async => snapshot);
    when(() => snapshot.docs).thenReturn(const []);
  });

  FirebaseAppointmentsRepository repo() =>
      FirebaseAppointmentsRepository(firestore, logger: logger);

  /// [count] assignable jobs, all open and all still running.
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
    // Understating this caption tells an admin they have LESS work to reassign
    // before disabling someone than they actually do.

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

  group('a range read warns at its cap', () {
    // Past the cap the caller holds a PREFIX of the range, and the calendar's
    // grid dots and agenda would disagree with reality with nothing failing.

    final range = AppointmentDateRange(
      start: DateTime(2026, 8),
      end: DateTime(2026, 9),
    );

    test('a full page warns', () async {
      withJobs(1000);

      expect(await repo().fetchInRange(range), hasLength(1000));
      expect(logger.warnings, hasLength(1));
      expect(logger.warnings.single, startsWith('APPT-RANGE-ONCE'));
      expect(logger.warnings.single, contains('1000'));
    });

    test('a short page is silent', () async {
      withJobs(999);

      await repo().fetchInRange(range);
      expect(logger.warnings, isEmpty);
    });
  });

  group('the history search scan window warns at its cap', () {
    // At the cap the window is the NEWEST 1000 terminal visits, so an older
    // match simply never appears and search reports "no results" for a job
    // that exists.

    void withHistory(int count) => when(() => snapshot.docs).thenReturn([
      for (var i = 0; i < count; i++)
        _FakeDoc('h$i', {
          'clientName': 'Sophie Tremblay',
          'employeeNames': const <String>[],
          'status': 'done',
        }),
    ]);

    test('a full window warns', () async {
      withHistory(1000);

      await repo().searchHistory('sophie');
      expect(logger.warnings, hasLength(1));
      expect(logger.warnings.single, startsWith('HIST-SEARCH'));
      expect(logger.warnings.single, contains('1000'));
    });

    test('a short window is silent', () async {
      withHistory(999);

      await repo().searchHistory('sophie');
      expect(logger.warnings, isEmpty);
    });
  });
}

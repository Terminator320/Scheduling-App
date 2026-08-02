// Mocktail fakes must subclass cloud_firestore's sealed query/snapshot types.
// ignore_for_file: subtype_of_sealed_class

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:scheduling/features/employees/data/firebase_employees_repository.dart';
import 'package:scheduling/features/employees/domain/employees_failure.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';
import 'package:scheduling/features/employees/domain/models/job_title.dart';

class _MockFirestore extends Mock implements FirebaseFirestore {}

class _MockFirebaseFunctions extends Mock implements FirebaseFunctions {}

class _MockHttpsCallable extends Mock implements HttpsCallable {}

class _MockHttpsCallableResult extends Mock
    implements HttpsCallableResult<dynamic> {}

class _MockCollection extends Mock
    implements CollectionReference<Map<String, dynamic>> {}

class _MockQuery extends Mock implements Query<Map<String, dynamic>> {}

class _MockQuerySnapshot extends Mock
    implements QuerySnapshot<Map<String, dynamic>> {}

class _MockQueryDocSnapshot extends Mock
    implements QueryDocumentSnapshot<Map<String, dynamic>> {}

class _MockDocRef extends Mock
    implements DocumentReference<Map<String, dynamic>> {}

class _MockDocSnapshot extends Mock
    implements DocumentSnapshot<Map<String, dynamic>> {}

class _MockTransaction extends Mock implements Transaction {}

class _FakeFieldValue extends Fake implements FieldValue {}

class _FakeHttpsCallableOptions extends Fake implements HttpsCallableOptions {}

void main() {
  late _MockFirestore firestore;
  late _MockFirebaseFunctions functions;
  late _MockCollection collection;
  late _MockQuery query;
  late _MockQuerySnapshot snapshot;
  late _MockDocRef docRef;
  late _MockDocSnapshot docSnapshot;
  late _MockTransaction transaction;

  setUpAll(() {
    registerFallbackValue(_FakeFieldValue());
    registerFallbackValue(<String, dynamic>{});
    registerFallbackValue(_MockDocRef());
    registerFallbackValue((Transaction txn) async {});
    registerFallbackValue(Duration.zero);
    registerFallbackValue(_FakeHttpsCallableOptions());
  });

  setUp(() {
    firestore = _MockFirestore();
    functions = _MockFirebaseFunctions();
    collection = _MockCollection();
    query = _MockQuery();
    snapshot = _MockQuerySnapshot();
    docRef = _MockDocRef();
    docSnapshot = _MockDocSnapshot();
    transaction = _MockTransaction();

    when(() => firestore.collection('users')).thenReturn(collection);

    // Default: where chain returns the same query mock
    when(
      () => collection.where(any(), isEqualTo: any(named: 'isEqualTo')),
    ).thenReturn(query);
    when(
      () => collection.where(any(), whereIn: any(named: 'whereIn')),
    ).thenReturn(query);
    when(
      () => query.where(any(), whereIn: any(named: 'whereIn')),
    ).thenReturn(query);
    when(
      () => query.where(any(), isEqualTo: any(named: 'isEqualTo')),
    ).thenReturn(query);
    when(() => query.limit(any())).thenReturn(query);
    when(() => query.get()).thenAnswer((_) async => snapshot);
    when(() => snapshot.docs).thenReturn(const []);

    when(() => collection.doc(any())).thenReturn(docRef);
    when(() => docRef.update(any())).thenAnswer((_) async {});
    when(() => docRef.get()).thenAnswer((_) async => docSnapshot);
    when(() => docRef.firestore).thenReturn(firestore);
    when(() => collection.add(any())).thenAnswer((_) async => docRef);

    // updateEmployee commits inside a transaction: run the handler with the
    // transaction mock, which re-reads the target doc.
    when(
      () => firestore.runTransaction<void>(
        any(),
        timeout: any(named: 'timeout'),
        maxAttempts: any(named: 'maxAttempts'),
      ),
    ).thenAnswer((invocation) {
      final handler =
          invocation.positionalArguments.first
              as Future<void> Function(Transaction);
      return handler(transaction);
    });
    when(() => transaction.get(docRef)).thenAnswer((_) async => docSnapshot);
    when(() => transaction.update(docRef, any())).thenReturn(transaction);
    when(docSnapshot.data).thenReturn(const {'email': 'old@example.com'});
  });

  FirebaseEmployeesRepository repo() =>
      FirebaseEmployeesRepository(firestore, functions: functions);

  /// The single captured update payload, cast the way mocktail requires —
  /// captureAny() returns Map<Object, Object?>, so a direct
  /// `as Map<String, dynamic>` throws at runtime.
  Map<String, dynamic> capturedUpdate() {
    final captured = verify(
      () => transaction.update(docRef, captureAny()),
    ).captured.single;
    return (captured as Map).cast<String, dynamic>();
  }

  group('createEmployeeInvite', () {
    test('returns the code and lowercases the email', () async {
      final callable = _MockHttpsCallable();
      final result = _MockHttpsCallableResult();
      when(
        () => functions.httpsCallable(
          any(that: equals('createEmployeeInvite')),
          options: any(named: 'options'),
        ),
      ).thenReturn(callable);
      when(() => result.data).thenReturn({'code': 'K7Q2-9MZ4-XR8T'});
      when(
        () => callable.call<dynamic>(any<Object?>()),
      ).thenAnswer((_) async => result);

      final repo = FirebaseEmployeesRepository(firestore, functions: functions);
      final code = await repo.createEmployeeInvite(
        name: 'A',
        firstName: 'A',
        lastName: '',
        email: 'A@B.com',
        phone: '',
        colorValue: '1',
        jobTitle: 'technician',
        isAdmin: false,
      );

      expect(code, 'K7Q2-9MZ4-XR8T');
      final captured =
          (verify(
                    () => callable.call<dynamic>(captureAny<Object?>()),
                  ).captured.single
                  as Map)
              .cast<String, dynamic>();
      expect(captured['email'], 'a@b.com');
      expect(captured['jobTitle'], 'technician');
      expect(captured['firstName'], 'A');
      expect(captured['isAdmin'], isFalse);
    });

    test(
      'maps email-exists to EmployeesFailureEmailAlreadyExists',
      () async {
        final callable = _MockHttpsCallable();
        when(
          () => functions.httpsCallable(
            any(that: equals('createEmployeeInvite')),
            options: any(named: 'options'),
          ),
        ).thenReturn(callable);
        when(() => callable.call<dynamic>(any<Object?>())).thenThrow(
          FirebaseFunctionsException(
            message: 'email-exists',
            code: 'already-exists',
          ),
        );
        final repo = FirebaseEmployeesRepository(
          firestore,
          functions: functions,
        );
        expect(
          () => repo.createEmployeeInvite(
            name: 'A',
            firstName: '',
            lastName: '',
            email: 'a@b.com',
            phone: '',
            colorValue: '1',
            jobTitle: '',
            isAdmin: false,
          ),
          throwsA(isA<EmployeesFailureEmailAlreadyExists>()),
        );
      },
    );
  });

  /// Stubs [name] to a callable returning [data] and hands back the mock so
  /// the payload can be captured.
  _MockHttpsCallable stubCallable(String name, {Object? data}) {
    final callable = _MockHttpsCallable();
    final result = _MockHttpsCallableResult();
    when(
      () => functions.httpsCallable(
        any(that: equals(name)),
        options: any(named: 'options'),
      ),
    ).thenReturn(callable);
    when(() => result.data).thenReturn(data);
    when(
      () => callable.call<dynamic>(any<Object?>()),
    ).thenAnswer((_) async => result);
    return callable;
  }

  _MockHttpsCallable stubFailingCallable(
    String name,
    FirebaseFunctionsException error,
  ) {
    final callable = _MockHttpsCallable();
    when(
      () => functions.httpsCallable(
        any(that: equals(name)),
        options: any(named: 'options'),
      ),
    ).thenReturn(callable);
    when(() => callable.call<dynamic>(any<Object?>())).thenThrow(error);
    return callable;
  }

  /// captureAny() returns Map<Object, Object?>, so the direct generic cast
  /// throws at runtime — go through Map first.
  Map<String, dynamic> capturedPayload(_MockHttpsCallable callable) {
    final captured = verify(
      () => callable.call<dynamic>(captureAny<Object?>()),
    ).captured.single;
    return (captured as Map).cast<String, dynamic>();
  }

  group('redeemSignupCode', () {
    test('sends all six keys, defaulting the profile to empty', () async {
      final callable = stubCallable(
        'redeemSignupCode',
        data: {'role': 'employee', 'name': 'A'},
      );

      await repo().redeemSignupCode('K7Q2-9MZ4-XR8T');

      final payload = capturedPayload(callable);
      expect(payload['code'], 'K7Q2-9MZ4-XR8T');
      expect(payload['firstName'], '');
      expect(payload['lastName'], '');
      expect(payload['phone'], '');
      expect(payload['termsAccepted'], isFalse);
      expect(payload['locationConsent'], isFalse);
    });

    test('carries the acceptance profile and consent flags', () async {
      final callable = stubCallable(
        'redeemSignupCode',
        data: {'role': 'admin', 'name': 'Theo Roy'},
      );

      await repo().redeemSignupCode(
        'K7Q29MZ4XR8T',
        firstName: 'Theo',
        lastName: 'Roy',
        phone: '(514) 555-1234',
        termsAccepted: true,
        locationConsent: true,
      );

      final payload = capturedPayload(callable);
      expect(payload['firstName'], 'Theo');
      expect(payload['lastName'], 'Roy');
      expect(payload['phone'], '(514) 555-1234');
      expect(payload['termsAccepted'], isTrue);
      expect(payload['locationConsent'], isTrue);
    });
  });

  group('revokeInvite', () {
    test('sends the invite doc id', () async {
      final callable = stubCallable('revokeInvite', data: {'ok': true});

      await repo().revokeInvite('invite-doc-1');

      expect(capturedPayload(callable)['inviteDocId'], 'invite-doc-1');
    });

    test('maps invite-not-pending to the typed failure', () async {
      stubFailingCallable(
        'revokeInvite',
        FirebaseFunctionsException(
          message: 'invite-not-pending',
          code: 'failed-precondition',
        ),
      );

      await expectLater(
        repo().revokeInvite('invite-doc-1'),
        throwsA(isA<EmployeesFailureInviteNoLongerPending>()),
      );
    });

    test('maps invite-not-found to the same typed failure', () async {
      stubFailingCallable(
        'revokeInvite',
        FirebaseFunctionsException(
          message: 'invite-not-found',
          code: 'not-found',
        ),
      );

      await expectLater(
        repo().revokeInvite('invite-doc-1'),
        throwsA(isA<EmployeesFailureInviteNoLongerPending>()),
      );
    });

    test('rethrows anything else untouched', () async {
      stubFailingCallable(
        'revokeInvite',
        FirebaseFunctionsException(
          message: 'boom',
          code: 'permission-denied',
        ),
      );

      await expectLater(
        repo().revokeInvite('invite-doc-1'),
        throwsA(isA<FirebaseFunctionsException>()),
      );
    });
  });

  group('previewInvite', () {
    test('decodes a Map<dynamic, dynamic> callable response', () async {
      // The shape the plugin actually returns on Android.
      final callable = stubCallable(
        'previewInvite',
        data: <dynamic, dynamic>{
          'email': 'theo@example.com',
          'firstName': 'Theo',
          'lastName': 'Roy',
          'role': 'employee',
          'expiresAtMs': 1786000000000,
        },
      );

      final preview = await repo().previewInvite('K7Q2-9MZ4-XR8T');

      expect(preview.email, 'theo@example.com');
      expect(preview.firstName, 'Theo');
      expect(preview.role, 'employee');
      expect(
        preview.expiresAt,
        DateTime.fromMillisecondsSinceEpoch(1786000000000),
      );
      expect(capturedPayload(callable)['code'], 'K7Q2-9MZ4-XR8T');
    });

    test('rethrows a FirebaseFunctionsException untouched', () async {
      // No error mapping here — that's AuthService.previewInvite's job, the
      // same split as redeemSignupCode/signUpWithCode above.
      stubFailingCallable(
        'previewInvite',
        FirebaseFunctionsException(
          message: 'code-expired',
          code: 'failed-precondition',
        ),
      );

      await expectLater(
        repo().previewInvite('K7Q29MZ4XR8T'),
        throwsA(isA<FirebaseFunctionsException>()),
      );
    });

    test('a null payload surfaces EmployeesFailureUnknown', () async {
      stubCallable('previewInvite');

      await expectLater(
        repo().previewInvite('K7Q29MZ4XR8T'),
        throwsA(isA<EmployeesFailureUnknown>()),
      );
    });
  });

  group('updateEmployee', () {
    test(
      'throws EmployeesFailureEmailAlreadyExists when another employee has same email',
      () async {
        final otherDoc = _MockQueryDocSnapshot();
        when(() => otherDoc.id).thenReturn('other-id');
        when(() => snapshot.docs).thenReturn([otherDoc]);

        expect(
          () => repo().updateEmployee(
            docId: 'my-id',
            employee: const EmployeeRecord(
              id: 'my-id',
              name: 'Alice',
              email: 'alice@example.com',
              phone: '555-1234',
            ),
          ),
          throwsA(isA<EmployeesFailureEmailAlreadyExists>()),
        );
      },
    );

    test('writes updatedAt on successful update', () async {
      when(() => snapshot.docs).thenReturn(const []);

      await repo().updateEmployee(
        docId: 'my-id',
        employee: const EmployeeRecord(
          id: 'my-id',
          name: 'Alice',
          email: 'alice@example.com',
          phone: '555-1234',
        ),
      );

      final captured = capturedUpdate();
      expect(captured.containsKey('updatedAt'), isTrue);
      expect(captured['email'], 'alice@example.com');
    });

    test('writes the P4 fields and never uid or status', () async {
      when(() => snapshot.docs).thenReturn(const []);

      await repo().updateEmployee(
        docId: 'my-id',
        employee: const EmployeeRecord(
          id: 'my-id',
          name: 'Theo Roy',
          firstName: 'Theo',
          lastName: 'Roy',
          email: 'theo@x.com',
          phone: '555-0100',
          role: 'admin',
          status: 'active',
          uid: 'auth-uid-must-not-be-written',
          jobTitle: JobTitle.leadTech,
          maxJobsPerDay: 4,
          onCall: true,
          emergencyContact: 'Marie',
        ),
      );

      final data = capturedUpdate();
      expect(data['jobTitle'], 'lead_tech');
      expect(data['firstName'], 'Theo');
      expect(data['maxJobsPerDay'], 4);
      expect(data['onCall'], isTrue);
      expect(data['emergencyContact'], 'Marie');
      expect(data['role'], 'admin');
      expect(data.containsKey('uid'), isFalse);
      expect(data.containsKey('status'), isFalse);
    });

    test('recomposes name from first and last', () async {
      when(() => snapshot.docs).thenReturn(const []);

      await repo().updateEmployee(
        docId: 'my-id',
        employee: const EmployeeRecord(
          id: 'my-id',
          name: 'Stale Name',
          firstName: 'Theo',
          lastName: 'Roy',
          email: 'theo@x.com',
        ),
      );

      expect(capturedUpdate()['name'], 'Theo Roy');
    });

    test('keeps the stored name when both halves are blank', () async {
      when(() => snapshot.docs).thenReturn(const []);

      await repo().updateEmployee(
        docId: 'my-id',
        employee: const EmployeeRecord(
          id: 'my-id',
          name: 'Legacy Single Name',
          email: 'theo@x.com',
        ),
      );

      // Never empty: watchAllUsers orders by name and Firestore drops docs
      // missing the orderBy field.
      expect(capturedUpdate()['name'], 'Legacy Single Name');
    });

    test('aborts when the target email changed under the uniqueness check', () {
      when(() => snapshot.docs).thenReturn(const []);
      // Pre-check read sees the old email…
      when(docSnapshot.data).thenReturn(const {'email': 'old@example.com'});
      // …but the transactional re-read sees a concurrent edit.
      final freshSnapshot = _MockDocSnapshot();
      when(freshSnapshot.data).thenReturn(const {'email': 'new@example.com'});
      when(
        () => transaction.get(docRef),
      ).thenAnswer((_) async => freshSnapshot);

      expect(
        () => repo().updateEmployee(
          docId: 'my-id',
          employee: const EmployeeRecord(
            id: 'my-id',
            name: 'Alice',
            email: 'alice@example.com',
            phone: '555-1234',
          ),
        ),
        throwsA(isA<EmployeesFailureUnknown>()),
      );
      verifyNever(() => transaction.update(docRef, any()));
    });
  });

  group('auth-propagation retry (C2)', () {
    FirebaseException permissionDenied() => FirebaseException(
      plugin: 'cloud_firestore',
      code: 'permission-denied',
    );

    test('watchEmployees resubscribes past a permission-denied error', () {
      fakeAsync((async) {
        var subscriptions = 0;
        when(query.snapshots).thenAnswer((_) {
          subscriptions++;
          if (subscriptions == 1) {
            return Stream.error(permissionDenied());
          }
          return Stream.value(snapshot);
        });

        final emissions = <List<EmployeeRecord>>[];
        Object? error;
        repo().watchEmployees().listen(
          emissions.add,
          onError: (Object e) => error = e,
        );

        async.elapse(const Duration(seconds: 1));
        expect(subscriptions, 2);
        expect(error, isNull);
        expect(emissions, [isEmpty]);
      });
    });

    test('watchUserDoc resubscribes and then emits the user doc', () {
      fakeAsync((async) {
        final userDoc = _MockQueryDocSnapshot();
        when(userDoc.data).thenReturn(const {'role': 'admin'});
        when(() => snapshot.docs).thenReturn([userDoc]);

        var subscriptions = 0;
        when(query.snapshots).thenAnswer((_) {
          subscriptions++;
          if (subscriptions == 1) {
            return Stream.error(permissionDenied());
          }
          return Stream.value(snapshot);
        });

        final emissions = <Map<String, dynamic>>[];
        Object? error;
        repo()
            .watchUserDoc('uid-1')
            .listen(
              emissions.add,
              onError: (Object e) => error = e,
            );

        async.elapse(const Duration(seconds: 1));
        expect(subscriptions, 2);
        expect(error, isNull);
        expect(emissions, [
          {'role': 'admin'},
        ]);
      });
    });

    test('watchUserDoc does not retry a non-permission error', () {
      fakeAsync((async) {
        var subscriptions = 0;
        when(query.snapshots).thenAnswer((_) {
          subscriptions++;
          return Stream.error(
            FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'),
          );
        });

        Object? error;
        repo()
            .watchUserDoc('uid-1')
            .listen(
              (_) {},
              onError: (Object e) => error = e,
            );

        async.elapse(const Duration(seconds: 5));
        expect(subscriptions, 1);
        expect(error, isA<FirebaseException>());
      });
    });
  });

  group('status transitions', () {
    test('deactivateEmployee writes disabled status and updatedAt', () async {
      await repo().deactivateEmployee('e1');

      final captured =
          (verify(() => docRef.update(captureAny())).captured.single as Map)
              .cast<String, dynamic>();
      expect(captured['status'], 'disabled');
      expect(captured.containsKey('updatedAt'), isTrue);
    });

    test('reactivateEmployee writes active status and updatedAt', () async {
      await repo().reactivateEmployee('e1');

      final captured =
          (verify(() => docRef.update(captureAny())).captured.single as Map)
              .cast<String, dynamic>();
      expect(captured['status'], 'active');
      expect(captured.containsKey('updatedAt'), isTrue);
    });
  });
}

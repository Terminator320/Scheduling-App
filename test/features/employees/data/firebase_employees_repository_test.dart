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
    when(() => docRef.delete()).thenAnswer((_) async {});
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
        email: 'A@B.com',
        phone: '',
        colorValue: '1',
      );

      expect(code, 'K7Q2-9MZ4-XR8T');
      final captured = verify(
        () => callable.call<dynamic>(captureAny<Object?>()),
      ).captured.single;
      expect(
        (captured as Map).cast<String, dynamic>()['email'],
        'a@b.com',
      );
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
            email: 'a@b.com',
            phone: '',
            colorValue: '1',
          ),
          throwsA(isA<EmployeesFailureEmailAlreadyExists>()),
        );
      },
    );
  });

  group('redeemSignupCode', () {
    test('forwards the code to the callable', () async {
      final callable = _MockHttpsCallable();
      final result = _MockHttpsCallableResult();
      when(
        () => functions.httpsCallable(
          any(that: equals('redeemSignupCode')),
          options: any(named: 'options'),
        ),
      ).thenReturn(callable);
      when(() => result.data).thenReturn({'role': 'employee', 'name': 'A'});
      when(
        () => callable.call<dynamic>(any<Object?>()),
      ).thenAnswer((_) async => result);

      final repo = FirebaseEmployeesRepository(firestore, functions: functions);
      await repo.redeemSignupCode('K7Q2-9MZ4-XR8T');

      final captured = verify(
        () => callable.call<dynamic>(captureAny<Object?>()),
      ).captured.single;
      expect(
        (captured as Map).cast<String, dynamic>()['code'],
        'K7Q2-9MZ4-XR8T',
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
            name: 'Alice',
            email: 'alice@example.com',
            phone: '555-1234',
            colorValue: '0xFF0000FF',
          ),
          throwsA(isA<EmployeesFailureEmailAlreadyExists>()),
        );
      },
    );

    test('writes updatedAt on successful update', () async {
      when(() => snapshot.docs).thenReturn(const []);

      await repo().updateEmployee(
        docId: 'my-id',
        name: 'Alice',
        email: 'alice@example.com',
        phone: '555-1234',
        colorValue: '0xFF0000FF',
      );

      final captured =
          (verify(
                    () => transaction.update(docRef, captureAny()),
                  ).captured.single
                  as Map)
              .cast<String, dynamic>();
      expect(captured.containsKey('updatedAt'), isTrue);
      expect(captured['email'], 'alice@example.com');
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
          name: 'Alice',
          email: 'alice@example.com',
          phone: '555-1234',
          colorValue: '0xFF0000FF',
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

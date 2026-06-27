// Mocktail fakes must subclass cloud_firestore's sealed query/snapshot types.
// ignore_for_file: subtype_of_sealed_class

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:scheduling/features/employees/data/firebase_employees_repository.dart';
import 'package:scheduling/features/employees/domain/employees_failure.dart';

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

class _FakeFieldValue extends Fake implements FieldValue {}

void main() {
  late _MockFirestore firestore;
  late _MockFirebaseFunctions functions;
  late _MockCollection collection;
  late _MockQuery query;
  late _MockQuerySnapshot snapshot;
  late _MockDocRef docRef;

  setUpAll(() {
    registerFallbackValue(_FakeFieldValue());
    registerFallbackValue(<String, dynamic>{});
  });

  setUp(() {
    firestore = _MockFirestore();
    functions = _MockFirebaseFunctions();
    collection = _MockCollection();
    query = _MockQuery();
    snapshot = _MockQuerySnapshot();
    docRef = _MockDocRef();

    when(() => firestore.collection('users')).thenReturn(collection);

    // Default: where chain returns the same query mock
    when(
      () => collection.where(any(), isEqualTo: any(named: 'isEqualTo')),
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
    when(() => collection.add(any())).thenAnswer((_) async => docRef);
  });

  FirebaseEmployeesRepository repo() =>
      FirebaseEmployeesRepository(firestore, functions: functions);

  group('createEmployeeInvite', () {
    test('returns the code and lowercases the email', () async {
      final callable = _MockHttpsCallable();
      final result = _MockHttpsCallableResult();
      when(
        () => functions.httpsCallable('createEmployeeInvite'),
      ).thenReturn(callable);
      when(() => result.data).thenReturn({'code': 'K7Q2-9MZ4-XR8T'});
      when(
        () => callable.call<dynamic>(any()),
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
        () => callable.call<dynamic>(captureAny()),
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
          () => functions.httpsCallable('createEmployeeInvite'),
        ).thenReturn(callable);
        when(() => callable.call<dynamic>(any())).thenThrow(
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
        () => functions.httpsCallable('redeemSignupCode'),
      ).thenReturn(callable);
      when(() => result.data).thenReturn({'role': 'employee', 'name': 'A'});
      when(
        () => callable.call<dynamic>(any()),
      ).thenAnswer((_) async => result);

      final repo = FirebaseEmployeesRepository(firestore, functions: functions);
      await repo.redeemSignupCode('K7Q2-9MZ4-XR8T');

      final captured = verify(
        () => callable.call<dynamic>(captureAny()),
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
          (verify(() => docRef.update(captureAny())).captured.single as Map)
              .cast<String, dynamic>();
      expect(captured.containsKey('updatedAt'), isTrue);
    });
  });

  group('status transitions', () {
    test('activateEmployee writes uid, active status, and updatedAt', () async {
      await repo().activateEmployee(docId: 'e1', uid: 'uid-1');

      final captured =
          (verify(() => docRef.update(captureAny())).captured.single as Map)
              .cast<String, dynamic>();
      expect(captured['uid'], 'uid-1');
      expect(captured['status'], 'active');
      expect(captured.containsKey('updatedAt'), isTrue);
    });

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

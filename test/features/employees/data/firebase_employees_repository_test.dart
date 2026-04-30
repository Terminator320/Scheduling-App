// ignore_for_file: subtype_of_sealed_class

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:scheduling/features/employees/data/firebase_employees_repository.dart';
import 'package:scheduling/features/employees/domain/employees_failure.dart';

class _MockFirestore extends Mock implements FirebaseFirestore {}

class _MockFirebaseFunctions extends Mock implements FirebaseFunctions {}

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

  group('addEmployee', () {
    test(
      'throws EmployeesFailureEmailAlreadyExists when email already in use',
      () async {
        final existingDoc = _MockQueryDocSnapshot();
        when(() => snapshot.docs).thenReturn([existingDoc]);

        expect(
          () => repo().addEmployee(
            name: 'Alice',
            email: 'alice@example.com',
            phone: '555-1234',
            colorValue: '0xFF0000FF',
            isAdmin: false,
          ),
          throwsA(isA<EmployeesFailureEmailAlreadyExists>()),
        );
      },
    );

    test('writes normalized email and createdAt when no duplicate', () async {
      when(() => snapshot.docs).thenReturn(const []);

      await repo().addEmployee(
        name: 'Bob',
        email: '  BOB@EXAMPLE.COM  ',
        phone: '555-0000',
        colorValue: '0xFF0000FF',
        isAdmin: false,
      );

      final captured =
          (verify(() => collection.add(captureAny())).captured.single as Map)
              .cast<String, dynamic>();
      expect(captured['email'], 'bob@example.com');
      expect(captured['name'], 'Bob');
      expect(captured['status'], 'invited');
      expect(captured.containsKey('createdAt'), isTrue);
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

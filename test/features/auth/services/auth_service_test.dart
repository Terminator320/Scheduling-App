// ignore_for_file: subtype_of_sealed_class

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:scheduling/features/auth/domain/auth_failure.dart';
import 'package:scheduling/features/auth/services/auth_service.dart';
import 'package:scheduling/features/employees/domain/employees_repository.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';

class _MockFirebaseAuth extends Mock implements FirebaseAuth {}

class _MockUserCredential extends Mock implements UserCredential {}

class _MockUser extends Mock implements User {}

class _MockEmployeesRepository extends Mock implements EmployeesRepository {}

void main() {
  late _MockFirebaseAuth auth;
  late _MockEmployeesRepository employees;
  late _MockUserCredential credential;
  late _MockUser user;
  late AuthService service;

  setUp(() {
    auth = _MockFirebaseAuth();
    employees = _MockEmployeesRepository();
    credential = _MockUserCredential();
    user = _MockUser();
    service = AuthService(firebaseAuth: auth, employeesRepository: employees);
    when(() => credential.user).thenReturn(user);
    when(() => user.uid).thenReturn('uid-001');
    when(() => user.delete()).thenAnswer((_) async {});
  });

  void stubRegister({String? email}) {
    when(
      () => auth.createUserWithEmailAndPassword(
        email: email ?? any(named: 'email'),
        password: any(named: 'password'),
      ),
    ).thenAnswer((_) async => credential);
  }

  group('createEmployeeAccount', () {
    test('normalizes email before creating Auth account', () async {
      stubRegister(email: 'invite@example.com');
      when(() => employees.findInvitedEmployeeByEmail(any())).thenAnswer(
        (_) async => InvitedEmployeeMatch(
          docId: 'doc1',
          data: const {'uid': '', 'status': 'invited'},
        ),
      );
      when(
        () => employees.activateEmployee(
          docId: any(named: 'docId'),
          uid: any(named: 'uid'),
        ),
      ).thenAnswer((_) async {});

      await service.createEmployeeAccount(
        email: '  INVITE@EXAMPLE.COM  ',
        password: 'pass',
      );

      verify(
        () => auth.createUserWithEmailAndPassword(
          email: 'invite@example.com',
          password: 'pass',
        ),
      ).called(1);
    });

    test(
      'throws AuthFailureNotAuthorized and deletes Auth user when no invite',
      () async {
        stubRegister();
        when(
          () => employees.findInvitedEmployeeByEmail(any()),
        ).thenAnswer((_) async => null);

        await expectLater(
          service.createEmployeeAccount(
            email: 'nobody@example.com',
            password: 'pass',
          ),
          throwsA(isA<AuthFailureNotAuthorized>()),
        );
        verify(() => user.delete()).called(1);
      },
    );

    test('activates the invited employee on success', () async {
      stubRegister();
      when(() => employees.findInvitedEmployeeByEmail(any())).thenAnswer(
        (_) async => InvitedEmployeeMatch(
          docId: 'doc-xyz',
          data: const {'uid': '', 'status': 'invited'},
        ),
      );
      when(
        () => employees.activateEmployee(
          docId: any(named: 'docId'),
          uid: any(named: 'uid'),
        ),
      ).thenAnswer((_) async {});

      await service.createEmployeeAccount(
        email: 'invited@example.com',
        password: 'pass',
      );

      verify(
        () => employees.activateEmployee(docId: 'doc-xyz', uid: 'uid-001'),
      ).called(1);
    });

    test(
      'deletes Auth user and rethrows when findInvitedEmployeeByEmail throws',
      () async {
        stubRegister();
        when(
          () => employees.findInvitedEmployeeByEmail(any()),
        ).thenThrow(Exception('firestore unavailable'));

        await expectLater(
          service.createEmployeeAccount(
            email: 'test@example.com',
            password: 'pass',
          ),
          throwsException,
        );
        verify(() => user.delete()).called(1);
      },
    );
  });
}

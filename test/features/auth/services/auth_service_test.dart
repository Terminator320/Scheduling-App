import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:scheduling/features/auth/domain/auth_failure.dart';
import 'package:scheduling/features/auth/services/auth_service.dart';
import 'package:scheduling/features/employees/domain/employees_repository.dart';

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
    when(() => auth.signOut()).thenAnswer((_) async {});
  });

  group('signUpWithCode', () {
    test('redeems the code after registering (active, signed in)', () async {
      when(
        () => auth.createUserWithEmailAndPassword(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenAnswer((_) async => credential);
      when(() => employees.redeemSignupCode(any())).thenAnswer((_) async {});

      await service.signUpWithCode(
        email: 'a@b.com',
        password: 'pw123456',
        code: 'K7Q2-9MZ4-XR8T',
      );

      verify(() => employees.redeemSignupCode('K7Q2-9MZ4-XR8T')).called(1);
    });

    test(
      'maps invalid-code to AuthFailureInvalidSignupCode and rolls back',
      () async {
        when(
          () => auth.createUserWithEmailAndPassword(
            email: any(named: 'email'),
            password: any(named: 'password'),
          ),
        ).thenAnswer((_) async => credential);
        when(() => employees.redeemSignupCode(any())).thenThrow(
          FirebaseFunctionsException(
            message: 'invalid-code',
            code: 'invalid-argument',
          ),
        );
        when(() => user.delete()).thenAnswer((_) async {});

        await expectLater(
          service.signUpWithCode(
            email: 'a@b.com',
            password: 'pw123456',
            code: 'bad',
          ),
          throwsA(isA<AuthFailureInvalidSignupCode>()),
        );
        verify(() => user.delete()).called(1);
      },
    );

    test('maps code-expired to AuthFailureSignupCodeExpired', () async {
      when(
        () => auth.createUserWithEmailAndPassword(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenAnswer((_) async => credential);
      when(() => employees.redeemSignupCode(any())).thenThrow(
        FirebaseFunctionsException(
          message: 'code-expired',
          code: 'failed-precondition',
        ),
      );
      when(() => user.delete()).thenAnswer((_) async {});

      await expectLater(
        service.signUpWithCode(email: 'a@b.com', password: 'pw', code: 'x'),
        throwsA(isA<AuthFailureSignupCodeExpired>()),
      );
    });
  });

  group('resendVerificationEmail', () {
    test('returns true when the verification email is sent', () async {
      when(() => user.sendEmailVerification()).thenAnswer((_) async {});

      final sent = await service.resendVerificationEmail(user);

      expect(sent, isTrue);
      verify(() => user.sendEmailVerification()).called(1);
    });

    test('returns false when sending throws (e.g. rate-limited)', () async {
      when(
        () => user.sendEmailVerification(),
      ).thenThrow(FirebaseAuthException(code: 'too-many-requests'));

      final sent = await service.resendVerificationEmail(user);

      expect(sent, isFalse);
    });
  });
}

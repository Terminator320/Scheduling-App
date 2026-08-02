import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:scheduling/features/auth/domain/auth_failure.dart';
import 'package:scheduling/features/auth/services/auth_service.dart';
import 'package:scheduling/features/employees/domain/employees_repository.dart';
import 'package:scheduling/features/employees/domain/models/invite_preview.dart';

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
    when(() => auth.currentUser).thenReturn(user);
    when(() => auth.signOut()).thenAnswer((_) async {});
  });

  /// The redeem stub has to match on every named argument too — mocktail
  /// compares the whole invocation, so a positional-only stub misses the
  /// widened call.
  When<Future<void>> stubRedeem() => when(
    () => employees.redeemSignupCode(
      any(),
      firstName: any(named: 'firstName'),
      lastName: any(named: 'lastName'),
      phone: any(named: 'phone'),
      termsAccepted: any(named: 'termsAccepted'),
      locationConsent: any(named: 'locationConsent'),
    ),
  );

  group('signUpWithCode', () {
    test('redeems the code after registering (active, signed in)', () async {
      when(
        () => auth.createUserWithEmailAndPassword(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenAnswer((_) async => credential);
      stubRedeem().thenAnswer((_) async {});

      await service.signUpWithCode(
        email: 'a@b.com',
        password: 'pw123456',
        code: 'K7Q2-9MZ4-XR8T',
      );

      verify(
        () => employees.redeemSignupCode(
          'K7Q2-9MZ4-XR8T',
          firstName: '',
          lastName: '',
          phone: '',
          termsAccepted: false,
          locationConsent: false,
        ),
      ).called(1);
    });

    test('carries the acceptance profile and consent flags through', () async {
      when(
        () => auth.createUserWithEmailAndPassword(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenAnswer((_) async => credential);
      stubRedeem().thenAnswer((_) async {});

      await service.signUpWithCode(
        email: 'a@b.com',
        password: 'pw123456',
        code: ' K7Q2-9MZ4-XR8T ',
        firstName: ' Theo ',
        lastName: ' Roy ',
        phone: ' (514) 555-1234 ',
        termsAccepted: true,
        locationConsent: true,
      );

      verify(
        () => employees.redeemSignupCode(
          'K7Q2-9MZ4-XR8T',
          firstName: 'Theo',
          lastName: 'Roy',
          phone: '(514) 555-1234',
          termsAccepted: true,
          locationConsent: true,
        ),
      ).called(1);
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
        stubRedeem().thenThrow(
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

    test(
      'maps code-email-mismatch to AuthFailureSignupEmailMismatch',
      () async {
        when(
          () => auth.createUserWithEmailAndPassword(
            email: any(named: 'email'),
            password: any(named: 'password'),
          ),
        ).thenAnswer((_) async => credential);
        stubRedeem().thenThrow(
          FirebaseFunctionsException(
            message: 'code-email-mismatch',
            code: 'failed-precondition',
          ),
        );

        await expectLater(
          service.signUpWithCode(email: 'a@b.com', password: 'pw', code: 'x'),
          throwsA(isA<AuthFailureSignupEmailMismatch>()),
        );
      },
    );

    test(
      'rollback re-authenticates and deletes when the guard signed the '
      'fresh user out',
      () async {
        when(
          () => auth.createUserWithEmailAndPassword(
            email: any(named: 'email'),
            password: any(named: 'password'),
          ),
        ).thenAnswer((_) async => credential);
        stubRedeem().thenThrow(
          FirebaseFunctionsException(
            message: 'invalid-code',
            code: 'invalid-argument',
          ),
        );
        // The account guard already tore the session down before rollback.
        when(() => auth.currentUser).thenReturn(null);
        final reauthCredential = _MockUserCredential();
        final reauthUser = _MockUser();
        when(() => reauthCredential.user).thenReturn(reauthUser);
        when(reauthUser.delete).thenAnswer((_) async {});
        when(
          () => auth.signInWithEmailAndPassword(
            email: any(named: 'email'),
            password: any(named: 'password'),
          ),
        ).thenAnswer((_) async => reauthCredential);

        await expectLater(
          service.signUpWithCode(
            email: 'a@b.com',
            password: 'pw123456',
            code: 'bad',
          ),
          throwsA(isA<AuthFailureInvalidSignupCode>()),
        );
        verify(
          () => auth.signInWithEmailAndPassword(
            email: 'a@b.com',
            password: 'pw123456',
          ),
        ).called(1);
        verify(reauthUser.delete).called(1);
      },
    );

    test('maps code-expired to AuthFailureSignupCodeExpired', () async {
      when(
        () => auth.createUserWithEmailAndPassword(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenAnswer((_) async => credential);
      stubRedeem().thenThrow(
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

  group('previewInvite', () {
    test(
      'delegates to the employees repository and returns the preview',
      () async {
        const preview = InvitePreview(
          email: 'theo@example.com',
          firstName: 'Theo',
          lastName: 'Roy',
          role: 'employee',
          expiresAt: null,
        );
        when(
          () => employees.previewInvite(any()),
        ).thenAnswer((_) async => preview);

        final result = await service.previewInvite(' K7Q2-9MZ4-XR8T ');

        expect(result, preview);
        verify(() => employees.previewInvite('K7Q2-9MZ4-XR8T')).called(1);
      },
    );

    test('maps code-expired to AuthFailureSignupCodeExpired', () async {
      when(() => employees.previewInvite(any())).thenThrow(
        FirebaseFunctionsException(
          message: 'code-expired',
          code: 'failed-precondition',
        ),
      );

      await expectLater(
        service.previewInvite('K7Q29MZ4XR8T'),
        throwsA(isA<AuthFailureSignupCodeExpired>()),
      );
    });

    test('maps invalid-code to AuthFailureInvalidSignupCode', () async {
      when(() => employees.previewInvite(any())).thenThrow(
        FirebaseFunctionsException(
          message: 'invalid-code',
          code: 'invalid-argument',
        ),
      );

      await expectLater(
        service.previewInvite('K7Q29MZ4XR8T'),
        throwsA(isA<AuthFailureInvalidSignupCode>()),
      );
    });

    test('maps resource-exhausted to AuthFailureTooManyRequests', () async {
      when(() => employees.previewInvite(any())).thenThrow(
        FirebaseFunctionsException(
          message: 'rate-limited',
          code: 'resource-exhausted',
        ),
      );

      await expectLater(
        service.previewInvite('K7Q29MZ4XR8T'),
        throwsA(isA<AuthFailureTooManyRequests>()),
      );
    });

    test('maps unavailable to AuthFailureNetwork', () async {
      when(() => employees.previewInvite(any())).thenThrow(
        FirebaseFunctionsException(message: 'offline', code: 'unavailable'),
      );

      await expectLater(
        service.previewInvite('K7Q29MZ4XR8T'),
        throwsA(isA<AuthFailureNetwork>()),
      );
    });
  });
}

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:scheduling/features/auth/domain/auth_failure.dart';
import 'package:scheduling/features/auth/services/auth_service.dart';
import 'package:scheduling/features/employees/domain/employees_repository.dart';

class _MockFirebaseAuth extends Mock implements FirebaseAuth {}

class _MockUser extends Mock implements User {}

class _MockEmployeesRepository extends Mock implements EmployeesRepository {}

void main() {
  late _MockFirebaseAuth auth;
  late _MockEmployeesRepository employees;
  late _MockUser user;
  late AuthService service;

  setUp(() {
    auth = _MockFirebaseAuth();
    employees = _MockEmployeesRepository();
    user = _MockUser();
    service = AuthService(firebaseAuth: auth, employeesRepository: employees);
    when(() => user.uid).thenReturn('uid-001');
    when(() => auth.currentUser).thenReturn(user);
    when(() => auth.signOut()).thenAnswer((_) async {});
    when(() => user.updatePassword(any())).thenAnswer((_) async {});
  });

  /// Mocktail compares the whole invocation, so the stub has to name every
  /// argument the call site passes.
  When<Future<void>> stubSetup() => when(
    () => employees.completeEmployeeSetup(
      firstName: any(named: 'firstName'),
      lastName: any(named: 'lastName'),
      phone: any(named: 'phone'),
      termsAccepted: any(named: 'termsAccepted'),
      locationConsent: any(named: 'locationConsent'),
    ),
  );

  group('completeAccountSetup', () {
    test('replaces the password, then activates the account', () async {
      stubSetup().thenAnswer((_) async {});

      await service.completeAccountSetup(
        newPassword: 'N3wPassw0rd!',
        firstName: 'Zoé',
        lastName: 'Roy',
        phone: '(514) 555-1234',
        termsAccepted: true,
        locationConsent: true,
      );

      verifyInOrder([
        () => user.updatePassword('N3wPassw0rd!'),
        () => employees.completeEmployeeSetup(
          firstName: 'Zoé',
          lastName: 'Roy',
          phone: '(514) 555-1234',
          termsAccepted: true,
          locationConsent: true,
        ),
      ]);
    });

    test('trims the profile it sends', () async {
      stubSetup().thenAnswer((_) async {});

      await service.completeAccountSetup(
        newPassword: '  N3wPassw0rd!  ',
        firstName: '  Zoé  ',
        lastName: '  Roy  ',
        phone: '  (514) 555-1234  ',
      );

      verify(() => user.updatePassword('N3wPassw0rd!')).called(1);
      verify(
        () => employees.completeEmployeeSetup(
          firstName: 'Zoé',
          lastName: 'Roy',
          phone: '(514) 555-1234',
          termsAccepted: false,
          locationConsent: false,
        ),
      ).called(1);
    });

    test('never activates when the password change fails', () async {
      // ORDER IS THE GUARANTEE: the server cannot see a password, so
      // "you must replace the shared default" is true only because activation
      // is unreachable until updatePassword succeeds.
      when(() => user.updatePassword(any())).thenThrow(
        FirebaseAuthException(code: 'weak-password'),
      );
      stubSetup().thenAnswer((_) async {});

      await expectLater(
        service.completeAccountSetup(newPassword: 'abc'),
        throwsA(isA<AuthFailureWeakPassword>()),
      );
      verifyNever(
        () => employees.completeEmployeeSetup(
          firstName: any(named: 'firstName'),
          lastName: any(named: 'lastName'),
          phone: any(named: 'phone'),
          termsAccepted: any(named: 'termsAccepted'),
          locationConsent: any(named: 'locationConsent'),
        ),
      );
    });

    test('maps a stale credential to a session-expired failure', () async {
      when(() => user.updatePassword(any())).thenThrow(
        FirebaseAuthException(code: 'requires-recent-login'),
      );

      await expectLater(
        service.completeAccountSetup(newPassword: 'N3wPassw0rd!'),
        throwsA(isA<AuthFailureSessionExpired>()),
      );
    });

    test('fails when there is no signed-in user to act on', () async {
      when(() => auth.currentUser).thenReturn(null);

      await expectLater(
        service.completeAccountSetup(newPassword: 'N3wPassw0rd!'),
        throwsA(isA<AuthFailureSessionExpired>()),
      );
      verifyNever(() => user.updatePassword(any()));
    });

    test('maps an already-active account to its own failure', () async {
      stubSetup().thenThrow(
        FirebaseFunctionsException(
          code: 'failed-precondition',
          message: 'setup-not-pending',
        ),
      );

      await expectLater(
        service.completeAccountSetup(newPassword: 'N3wPassw0rd!'),
        throwsA(isA<AuthFailureSetupAlreadyComplete>()),
      );
    });

    test('maps a missing users doc to its own failure', () async {
      stubSetup().thenThrow(
        FirebaseFunctionsException(
          code: 'not-found',
          message: 'account-not-found',
        ),
      );

      await expectLater(
        service.completeAccountSetup(newPassword: 'N3wPassw0rd!'),
        throwsA(isA<AuthFailureNoAccountRecord>()),
      );
    });

    test('maps a rate-limit refusal', () async {
      stubSetup().thenThrow(
        FirebaseFunctionsException(code: 'resource-exhausted', message: 'slow'),
      );

      await expectLater(
        service.completeAccountSetup(newPassword: 'N3wPassw0rd!'),
        throwsA(isA<AuthFailureTooManyRequests>()),
      );
    });

    test('maps an unavailable backend to a network failure', () async {
      stubSetup().thenThrow(
        FirebaseFunctionsException(code: 'unavailable', message: 'offline'),
      );

      await expectLater(
        service.completeAccountSetup(newPassword: 'N3wPassw0rd!'),
        throwsA(isA<AuthFailureNetwork>()),
      );
    });

    test('does NOT sign out or revert the password on failure', () async {
      // The new password is the one the person just chose and typed twice.
      // Reverting it to the shared default would be strictly worse than
      // leaving them `invited` with a password that works.
      stubSetup().thenThrow(
        FirebaseFunctionsException(code: 'internal', message: 'boom'),
      );

      await expectLater(
        service.completeAccountSetup(newPassword: 'N3wPassw0rd!'),
        throwsA(isA<AuthFailureUnknown>()),
      );
      verifyNever(() => auth.signOut());
    });
  });

  group('signOut', () {
    test('swallows a local sign-out failure once auth state is already cleared', () async {
      when(() => auth.signOut()).thenThrow(Exception('ios signOut failed'));
      when(() => auth.currentUser).thenReturn(null);

      await service.signOut();

      verify(() => auth.signOut()).called(1);
    });

    test('rethrows a local sign-out failure when the session is still live', () async {
      when(() => auth.signOut()).thenThrow(Exception('ios signOut failed'));
      when(() => auth.currentUser).thenReturn(user);

      await expectLater(service.signOut(), throwsException);
    });
  });
}

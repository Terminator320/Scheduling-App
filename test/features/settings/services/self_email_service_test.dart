// Pins SelfEmailService's re-auth-BEFORE-callable ordering.
//
// Its docstring names the threat this ordering exists to stop: an unattended
// unlocked phone moving the sign-in address. Reversing the two calls would
// discover it couldn't prove who it was only AFTER Auth had already changed,
// and nothing would fail — which is why this needs a test rather than a
// comment. Same shape as AuthService.completeAccountSetup's
// password-then-activate order, which is pinned the same way.

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/features/auth/domain/auth_failure.dart';
import 'package:scheduling/features/auth/services/account_deletion_service.dart';
import 'package:scheduling/features/employees/domain/employees_failure.dart';
import 'package:scheduling/features/settings/services/self_email_service.dart';

class _MockDeletionService extends Mock implements AccountDeletionService {}

class _MockFunctions extends Mock implements FirebaseFunctions {}

class _MockCallable extends Mock implements HttpsCallable {}

class _FakeResult extends Mock implements HttpsCallableResult<dynamic> {}

void main() {
  late _MockDeletionService deletion;
  late _MockFunctions functions;
  late _MockCallable callable;
  late SelfEmailService service;

  setUp(() {
    deletion = _MockDeletionService();
    functions = _MockFunctions();
    callable = _MockCallable();
    service = SelfEmailService(
      deletionService: deletion,
      logger: AppLogger(),
      functions: functions,
    );
    when(
      () => functions.httpsCallable(
        any(),
        options: any(named: 'options'),
      ),
    ).thenReturn(callable);
    when(() => callable.call<dynamic>(any<dynamic>())).thenAnswer(
      (_) async => _FakeResult(),
    );
  });

  Future<void> change({String email = 'new@example.com'}) =>
      service.changeOwnEmail(
        docId: 'd1',
        email: email,
        password: 'S3cret!pass',
      );

  test('re-authenticates BEFORE calling changeEmployeeEmail', () async {
    when(() => deletion.reauthenticateWithPassword(any())).thenAnswer(
      (_) async {},
    );

    await change();

    verifyInOrder([
      () => deletion.reauthenticateWithPassword('S3cret!pass'),
      () => callable.call<dynamic>({
        'docId': 'd1',
        'email': 'new@example.com',
      }),
    ]);
  });

  test('normalizes the address before calling changeEmployeeEmail', () async {
    when(() => deletion.reauthenticateWithPassword(any())).thenAnswer(
      (_) async {},
    );

    await change(email: ' New@Example.com ');

    verify(
      () => callable.call<dynamic>({
        'docId': 'd1',
        'email': 'new@example.com',
      }),
    ).called(1);
  });

  test('a failed re-auth never reaches the callable', () async {
    // The half that matters: proving who you are has to GATE the write, not
    // merely precede it.
    when(() => deletion.reauthenticateWithPassword(any())).thenThrow(
      const AuthFailureWrongCredentials(),
    );

    await expectLater(change(), throwsA(isA<AuthFailureWrongCredentials>()));

    verifyNever(() => callable.call<dynamic>(any<dynamic>()));
  });

  test('a taken address surfaces as a typed failure', () async {
    when(() => deletion.reauthenticateWithPassword(any())).thenAnswer(
      (_) async {},
    );
    when(() => callable.call<dynamic>(any<dynamic>())).thenThrow(
      FirebaseFunctionsException(
        code: 'already-exists',
        message: 'email-exists',
      ),
    );

    await expectLater(
      change(),
      throwsA(isA<EmployeesFailureEmailAlreadyExists>()),
    );
  });

  test('an unauthenticated callable asks the user to sign in again', () async {
    when(() => deletion.reauthenticateWithPassword(any())).thenAnswer(
      (_) async {},
    );
    when(() => callable.call<dynamic>(any<dynamic>())).thenThrow(
      FirebaseFunctionsException(
        code: 'unauthenticated',
        message: 'stale-token',
      ),
    );

    await expectLater(
      change(),
      throwsA(isA<AuthFailureRequiresRecentLogin>()),
    );
  });

  test('resource exhaustion surfaces as too many requests', () async {
    when(() => deletion.reauthenticateWithPassword(any())).thenAnswer(
      (_) async {},
    );
    when(() => callable.call<dynamic>(any<dynamic>())).thenThrow(
      FirebaseFunctionsException(
        code: 'resource-exhausted',
        message: 'quota',
      ),
    );

    await expectLater(
      change(),
      throwsA(isA<AuthFailureTooManyRequests>()),
    );
  });

  test('transport failures surface as network errors', () async {
    when(() => deletion.reauthenticateWithPassword(any())).thenAnswer(
      (_) async {},
    );
    when(() => callable.call<dynamic>(any<dynamic>())).thenThrow(
      FirebaseFunctionsException(
        code: 'unavailable',
        message: 'offline',
      ),
    );

    await expectLater(change(), throwsA(isA<AuthFailureNetwork>()));
  });
}

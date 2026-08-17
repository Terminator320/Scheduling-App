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

  Future<void> change() => service.changeOwnEmail(
    docId: 'd1',
    email: 'new@example.com',
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
}

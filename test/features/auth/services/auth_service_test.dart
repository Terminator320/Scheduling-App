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

  void stubSignIn({String? email}) {
    when(
      () => auth.signInWithEmailAndPassword(
        email: email ?? any(named: 'email'),
        password: any(named: 'password'),
      ),
    ).thenAnswer((_) async => credential);
  }

  void stubRegisterThrowsEmailInUse() {
    when(
      () => auth.createUserWithEmailAndPassword(
        email: any(named: 'email'),
        password: any(named: 'password'),
      ),
    ).thenThrow(FirebaseAuthException(code: 'email-already-in-use'));
    when(() => user.sendEmailVerification()).thenAnswer((_) async {});
  }

  void stubRegister({String? email}) {
    when(
      () => auth.createUserWithEmailAndPassword(
        email: email ?? any(named: 'email'),
        password: any(named: 'password'),
      ),
    ).thenAnswer((_) async => credential);
    when(() => user.sendEmailVerification()).thenAnswer((_) async {});
  }

  group('createEmployeeAccount', () {
    test('normalizes email before creating Auth account', () async {
      stubRegister(email: 'invite@example.com');
      when(() => employees.findInvitedEmployeeForCurrentUser()).thenAnswer(
        (_) async => const InvitedEmployeeMatch(
          docId: 'doc1',
          data: {'uid': '', 'status': 'invited'},
        ),
      );

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
          () => employees.findInvitedEmployeeForCurrentUser(),
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

    test('sends email verification after finding invite', () async {
      stubRegister();
      when(() => employees.findInvitedEmployeeForCurrentUser()).thenAnswer(
        (_) async => const InvitedEmployeeMatch(
          docId: 'doc-xyz',
          data: {'uid': '', 'status': 'invited'},
        ),
      );

      await service.createEmployeeAccount(
        email: 'invited@example.com',
        password: 'pass',
      );

      verify(() => user.sendEmailVerification()).called(1);
      verifyNever(
        () => employees.activateEmployee(
          docId: any(named: 'docId'),
          uid: any(named: 'uid'),
        ),
      );
    });

    test(
      'deletes Auth user and rethrows when findInvitedEmployeeForCurrentUser throws',
      () async {
        stubRegister();
        when(
          () => employees.findInvitedEmployeeForCurrentUser(),
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

    test(
      'throws AuthFailureAccountCreationIncomplete when rollback delete fails',
      () async {
        stubRegister();
        when(
          () => employees.findInvitedEmployeeForCurrentUser(),
        ).thenAnswer((_) async => null);
        when(
          () => user.delete(),
        ).thenThrow(FirebaseAuthException(code: 'requires-recent-login'));

        await expectLater(
          service.createEmployeeAccount(
            email: 'nobody@example.com',
            password: 'pass',
          ),
          throwsA(isA<AuthFailureAccountCreationIncomplete>()),
        );
        verify(() => auth.signOut()).called(1);
      },
    );

    test(
      'recovers an orphan: signs in on email-already-in-use and sends '
      'verification when an invite exists',
      () async {
        stubRegisterThrowsEmailInUse();
        stubSignIn(email: 'orphan@example.com');
        when(() => employees.findInvitedEmployeeForCurrentUser()).thenAnswer(
          (_) async => const InvitedEmployeeMatch(
            docId: 'doc1',
            data: {'uid': '', 'status': 'invited'},
          ),
        );

        await service.createEmployeeAccount(
          email: 'orphan@example.com',
          password: 'pass',
        );

        verify(
          () => auth.signInWithEmailAndPassword(
            email: 'orphan@example.com',
            password: 'pass',
          ),
        ).called(1);
        verify(() => user.sendEmailVerification()).called(1);
        verifyNever(() => user.delete());
      },
    );

    test(
      'throws AuthFailureEmailAlreadyInUse without deleting when the email '
      'belongs to an already-provisioned account',
      () async {
        stubRegisterThrowsEmailInUse();
        stubSignIn();
        when(
          () => employees.findInvitedEmployeeForCurrentUser(),
        ).thenAnswer((_) async => null);
        when(() => employees.findUserByUid('uid-001')).thenAnswer(
          (_) async =>
              const UserUidMatch(id: 'doc9', data: {'status': 'active'}),
        );

        await expectLater(
          service.createEmployeeAccount(
            email: 'real@example.com',
            password: 'pass',
          ),
          throwsA(isA<AuthFailureEmailAlreadyInUse>()),
        );
        verifyNever(() => user.delete());
        verify(() => auth.signOut()).called(1);
      },
    );

    test(
      'deletes the adopted orphan when no invite and no provisioned doc exist',
      () async {
        stubRegisterThrowsEmailInUse();
        stubSignIn();
        when(
          () => employees.findInvitedEmployeeForCurrentUser(),
        ).thenAnswer((_) async => null);
        when(
          () => employees.findUserByUid('uid-001'),
        ).thenAnswer((_) async => null);

        await expectLater(
          service.createEmployeeAccount(
            email: 'orphan@example.com',
            password: 'pass',
          ),
          throwsA(isA<AuthFailureNotAuthorized>()),
        );
        verify(() => user.delete()).called(1);
      },
    );

    test(
      'does not delete an adopted account when the invite lookup throws',
      () async {
        stubRegisterThrowsEmailInUse();
        stubSignIn();
        when(
          () => employees.findInvitedEmployeeForCurrentUser(),
        ).thenThrow(Exception('firestore unavailable'));

        await expectLater(
          service.createEmployeeAccount(
            email: 'orphan@example.com',
            password: 'pass',
          ),
          throwsException,
        );
        verifyNever(() => user.delete());
        verify(() => auth.signOut()).called(1);
      },
    );
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

  group('tryActivateInvitedEmployee', () {
    setUp(() {
      when(() => user.reload()).thenAnswer((_) async {});
      when(() => user.email).thenReturn('invited@example.com');
      when(() => user.getIdToken(any())).thenAnswer((_) async => 'token');
    });

    test('does nothing when email is not verified', () async {
      when(() => user.emailVerified).thenReturn(false);

      await service.tryActivateInvitedEmployee(user);

      verifyNever(() => employees.findInvitedEmployeeForCurrentUser());
      verifyNever(
        () => employees.activateEmployee(
          docId: any(named: 'docId'),
          uid: any(named: 'uid'),
        ),
      );
    });

    test('activates when email is verified and invite exists', () async {
      when(() => user.emailVerified).thenReturn(true);
      when(() => employees.findInvitedEmployeeForCurrentUser()).thenAnswer(
        (_) async => const InvitedEmployeeMatch(
          docId: 'doc-xyz',
          data: {'uid': '', 'status': 'invited'},
        ),
      );
      when(
        () => employees.activateEmployee(
          docId: any(named: 'docId'),
          uid: any(named: 'uid'),
        ),
      ).thenAnswer((_) async {});

      await service.tryActivateInvitedEmployee(user);

      verify(
        () => employees.activateEmployee(docId: 'doc-xyz', uid: 'uid-001'),
      ).called(1);
    });

    test('does nothing when no invite exists for the verified email', () async {
      when(() => user.emailVerified).thenReturn(true);
      when(
        () => employees.findInvitedEmployeeForCurrentUser(),
      ).thenAnswer((_) async => null);

      await service.tryActivateInvitedEmployee(user);

      verifyNever(
        () => employees.activateEmployee(
          docId: any(named: 'docId'),
          uid: any(named: 'uid'),
        ),
      );
    });

    test('forces a fresh ID token before resolving the invite', () async {
      // resolveMyInvite now requires a verified email_verified token claim;
      // reload() doesn't refresh that claim, so a forced token refresh must
      // precede the lookup.
      when(() => user.emailVerified).thenReturn(true);
      when(
        () => employees.findInvitedEmployeeForCurrentUser(),
      ).thenAnswer((_) async => null);

      await service.tryActivateInvitedEmployee(user);

      verify(() => user.getIdToken(true)).called(1);
    });
  });
}

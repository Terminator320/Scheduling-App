import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scheduling/features/auth/domain/auth_failure.dart';
import 'package:scheduling/features/auth/services/account_deletion_service.dart';

class _MockFirebaseAuth extends Mock implements FirebaseAuth {}

class _MockUser extends Mock implements User {}

class _MockFirebaseFunctions extends Mock implements FirebaseFunctions {}

class _MockHttpsCallable extends Mock implements HttpsCallable {}

class _MockHttpsCallableResult extends Mock
    implements HttpsCallableResult<dynamic> {}

class _MockUserCredential extends Mock implements UserCredential {}

class _FakeAuthCredential extends Fake implements AuthCredential {}

class _FakeHttpsCallableOptions extends Fake implements HttpsCallableOptions {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(_FakeAuthCredential());
    registerFallbackValue(_FakeHttpsCallableOptions());
  });

  late _MockFirebaseAuth auth;
  late _MockUser user;
  late _MockFirebaseFunctions functions;
  late _MockHttpsCallable callable;
  late AccountDeletionService service;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    auth = _MockFirebaseAuth();
    user = _MockUser();
    functions = _MockFirebaseFunctions();
    callable = _MockHttpsCallable();
    service = AccountDeletionService(firebaseAuth: auth, functions: functions);
    when(() => auth.currentUser).thenReturn(user);
    when(() => user.email).thenReturn('owner@example.com');
    when(
      () => functions.httpsCallable(
        any(that: equals('deleteAccount')),
        options: any(named: 'options'),
      ),
    ).thenReturn(callable);
  });

  group('reauthenticateWithPassword', () {
    test('normalizes email before reauth', () async {
      when(() => user.email).thenReturn('  OWNER@EXAMPLE.COM  ');
      when(
        () => user.reauthenticateWithCredential(any()),
      ).thenAnswer((_) async => _MockUserCredential());

      await service.reauthenticateWithPassword(' pw ');

      final captured =
          verify(
                () => user.reauthenticateWithCredential(captureAny()),
              ).captured.single
              as EmailAuthCredential;
      expect(captured.email, 'owner@example.com');
      expect(captured.password, 'pw');
    });

    test(
      'throws AuthFailureRequiresRecentLogin when no current user',
      () async {
        when(() => auth.currentUser).thenReturn(null);

        await expectLater(
          service.reauthenticateWithPassword('pw'),
          throwsA(isA<AuthFailureRequiresRecentLogin>()),
        );
      },
    );

    test('maps FirebaseAuthException via AuthErrorMapper', () async {
      when(
        () => user.reauthenticateWithCredential(any()),
      ).thenThrow(FirebaseAuthException(code: 'wrong-password'));

      await expectLater(
        service.reauthenticateWithPassword('pw'),
        throwsA(isA<AuthFailureWrongCredentials>()),
      );
    });
  });

  group('deleteAccount', () {
    test('signs out after the callable succeeds', () async {
      when(
        () => callable.call<dynamic>(),
      ).thenAnswer((_) async => _MockHttpsCallableResult());
      when(() => auth.signOut()).thenAnswer((_) async {});

      await service.deleteAccount();

      verify(() => callable.call<dynamic>()).called(1);
      verify(() => auth.signOut()).called(1);
    });

    test(
      'maps unauthenticated callable error to requires-recent-login',
      () async {
        when(() => callable.call<dynamic>()).thenThrow(
          FirebaseFunctionsException(
            message: 'no-auth',
            code: 'unauthenticated',
          ),
        );

        await expectLater(
          service.deleteAccount(),
          throwsA(isA<AuthFailureRequiresRecentLogin>()),
        );
        verifyNever(() => auth.signOut());
      },
    );

    test('maps other callable errors to AuthFailureUnknown', () async {
      when(() => callable.call<dynamic>()).thenThrow(
        FirebaseFunctionsException(message: 'boom', code: 'internal'),
      );

      await expectLater(
        service.deleteAccount(),
        throwsA(isA<AuthFailureUnknown>()),
      );
      verifyNever(() => auth.signOut());
    });
  });
}

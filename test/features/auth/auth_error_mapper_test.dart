import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/features/auth/data/auth_error_mapper.dart';
import 'package:scheduling/features/auth/domain/auth_failure.dart';

FirebaseAuthException _exc(String code) =>
    FirebaseAuthException(code: code, message: 'test');

void main() {
  group('AuthErrorMapper.map', () {
    test('maps invalid-email', () {
      expect(AuthErrorMapper.map(_exc('invalid-email')),
          isA<AuthFailureInvalidEmail>());
    });

    test('maps user-disabled', () {
      expect(AuthErrorMapper.map(_exc('user-disabled')),
          isA<AuthFailureUserDisabled>());
    });

    test('maps user-not-found', () {
      expect(AuthErrorMapper.map(_exc('user-not-found')),
          isA<AuthFailureUserNotFound>());
    });

    test('maps all three wrong-credentials variants', () {
      for (final code in [
        'wrong-password',
        'invalid-credential',
        'INVALID_LOGIN_CREDENTIALS',
      ]) {
        expect(
          AuthErrorMapper.map(_exc(code)),
          isA<AuthFailureWrongCredentials>(),
          reason: 'expected AuthFailureWrongCredentials for code $code',
        );
      }
    });

    test('maps too-many-requests', () {
      expect(AuthErrorMapper.map(_exc('too-many-requests')),
          isA<AuthFailureTooManyRequests>());
    });

    test('maps network-request-failed', () {
      expect(AuthErrorMapper.map(_exc('network-request-failed')),
          isA<AuthFailureNetwork>());
    });

    test('maps email-already-in-use', () {
      expect(AuthErrorMapper.map(_exc('email-already-in-use')),
          isA<AuthFailureEmailAlreadyInUse>());
    });

    test('maps weak-password', () {
      expect(AuthErrorMapper.map(_exc('weak-password')),
          isA<AuthFailureWeakPassword>());
    });

    test('maps operation-not-allowed', () {
      expect(AuthErrorMapper.map(_exc('operation-not-allowed')),
          isA<AuthFailureOperationNotAllowed>());
    });

    test('maps requires-recent-login', () {
      expect(AuthErrorMapper.map(_exc('requires-recent-login')),
          isA<AuthFailureRequiresRecentLogin>());
    });

    test('maps not-authorized', () {
      expect(AuthErrorMapper.map(_exc('not-authorized')),
          isA<AuthFailureNotAuthorized>());
    });

    test('falls back to unknown for unrecognised Firebase codes', () {
      expect(AuthErrorMapper.map(_exc('something-new-and-weird')),
          isA<AuthFailureUnknown>());
    });

    test('falls back to unknown for non-Firebase exceptions', () {
      expect(AuthErrorMapper.map(Exception('plain')),
          isA<AuthFailureUnknown>());
      expect(AuthErrorMapper.map('a string'), isA<AuthFailureUnknown>());
    });
  });
}

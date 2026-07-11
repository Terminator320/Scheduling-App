import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/features/notifications/application/push_registration_controller.dart';

void main() {
  group('shouldRegisterPush', () {
    test('active employee signed in registers', () {
      expect(
        shouldRegisterPush(role: 'employee', status: 'active', signedIn: true),
        isTrue,
      );
    });

    test('active admin signed in registers (for time-based nudges)', () {
      expect(
        shouldRegisterPush(role: 'admin', status: 'active', signedIn: true),
        isTrue,
      );
    });

    test('a non-active admin does not register', () {
      expect(
        shouldRegisterPush(role: 'admin', status: 'invited', signedIn: true),
        isFalse,
      );
    });

    test('an unknown role does not register', () {
      expect(
        shouldRegisterPush(role: '', status: 'active', signedIn: true),
        isFalse,
      );
    });

    test('a non-active employee does not register', () {
      expect(
        shouldRegisterPush(
          role: 'employee',
          status: 'invited',
          signedIn: true,
        ),
        isFalse,
      );
      expect(
        shouldRegisterPush(
          role: 'employee',
          status: 'disabled',
          signedIn: true,
        ),
        isFalse,
      );
    });

    test('signed-out never registers', () {
      expect(
        shouldRegisterPush(role: 'employee', status: 'active', signedIn: false),
        isFalse,
      );
    });
  });
}

import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/features/live_activity/application/live_activity_registration_controller.dart';
import 'package:scheduling/features/notifications/application/push_registration_controller.dart';

void main() {
  group('shouldRegisterLiveActivity', () {
    test('active employee signed in registers', () {
      expect(
        shouldRegisterLiveActivity(
          role: 'employee',
          status: 'active',
          signedIn: true,
        ),
        isTrue,
      );
    });

    test('active admin signed in registers', () {
      expect(
        shouldRegisterLiveActivity(
          role: 'admin',
          status: 'active',
          signedIn: true,
        ),
        isTrue,
      );
    });

    test('non-active statuses are excluded', () {
      expect(
        shouldRegisterLiveActivity(
          role: 'employee',
          status: 'invited',
          signedIn: true,
        ),
        isFalse,
      );
      expect(
        shouldRegisterLiveActivity(
          role: 'employee',
          status: 'disabled',
          signedIn: true,
        ),
        isFalse,
      );
    });

    test('unknown roles are excluded', () {
      expect(
        shouldRegisterLiveActivity(
          role: '',
          status: 'active',
          signedIn: true,
        ),
        isFalse,
      );
    });

    test('signed-out never registers', () {
      expect(
        shouldRegisterLiveActivity(
          role: 'employee',
          status: 'active',
          signedIn: false,
        ),
        isFalse,
      );
    });

    test(
      'tracks shouldRegisterPush across every role/status/signed-in combo',
      () {
        for (final role in ['employee', 'admin', 'manager', '']) {
          for (final status in ['active', 'invited', 'disabled', '']) {
            for (final signedIn in [true, false]) {
              expect(
                shouldRegisterLiveActivity(
                  role: role,
                  status: status,
                  signedIn: signedIn,
                ),
                shouldRegisterPush(
                  role: role,
                  status: status,
                  signedIn: signedIn,
                ),
                reason: 'drifted for role=$role status=$status in=$signedIn',
              );
            }
          }
        }
      },
    );
  });
}

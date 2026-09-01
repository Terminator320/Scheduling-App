// Pins the two things the forced-exit flow calls load-bearing: the
// teardown ORDER (de-register everything BEFORE signOut, because each
// de-registration needs the credential sign-out revokes) and the one-exit-at-a-
// time guard (three listeners can fire for a single underlying event).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:scheduling/core/app/account_exit_controller.dart';
import 'package:scheduling/core/app/device_deregistration.dart';
import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/features/auth/services/auth_service.dart';
import 'package:scheduling/features/live_activity/application/live_activity_registration_controller.dart';
import 'package:scheduling/features/notifications/application/push_registration_controller.dart';
import 'package:scheduling/features/presence/application/presence_sync_controller.dart';
import 'package:scheduling/l10n/l10n.dart';

import '../../support/account_exit_stubs.dart';

class _MockPush extends Mock implements PushRegistrationController {}

class _MockPresence extends Mock implements PresenceSyncController {}

class _MockLiveActivity extends Mock
    implements LiveActivityRegistrationController {}

class _MockAuthService extends Mock implements AuthService {}

void main() {
  late _MockPush push;
  late _MockPresence presence;
  late _MockLiveActivity liveActivity;
  late _MockAuthService auth;
  late List<String> calls;
  late GlobalKey<NavigatorState> navigatorKey;
  late GlobalKey<ScaffoldMessengerState> messengerKey;

  setUp(() {
    push = _MockPush();
    presence = _MockPresence();
    liveActivity = _MockLiveActivity();
    auth = _MockAuthService();
    calls = [];
    navigatorKey = GlobalKey<NavigatorState>();
    messengerKey = GlobalKey<ScaffoldMessengerState>();

    when(() => push.unregisterCurrentDevice()).thenAnswer((_) async {
      calls.add('push');
    });
    when(() => presence.unregister()).thenAnswer((_) async {
      calls.add('presence');
    });
    when(() => liveActivity.unregister()).thenAnswer((_) async {
      calls.add('liveActivity');
    });
    when(() => auth.signOut()).thenAnswer((_) async {
      calls.add('signOut');
    });
  });

  /// Pumps a real MaterialApp so navigatorKey.currentContext resolves — the
  /// handler bails early without one.
  Future<AccountExitController> pumpController(
    WidgetTester tester, {
    bool signedIn = true,
  }) async {
    late AccountExitController controller;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          pushRegistrationControllerProvider.overrideWithValue(push),
          presenceSyncControllerProvider.overrideWithValue(presence),
          liveActivityRegistrationControllerProvider.overrideWithValue(
            liveActivity,
          ),
          authServiceProvider.overrideWithValue(auth),
          ...accountExitStubOverrides(),
        ],
        child: MaterialApp(
          navigatorKey: navigatorKey,
          scaffoldMessengerKey: messengerKey,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Consumer(
            builder: (context, ref, _) {
              controller = AccountExitController(
                logger: AppLogger(),
                authService: auth,
                deregisterDevice: () => deregisterThisDevice(
                  DeviceDeregistrationDeps.from(ref.read),
                ),
                isSignedIn: () => signedIn,
              );
              return const Scaffold(body: SizedBox.shrink());
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return controller;
  }

  testWidgets('tears every registration down BEFORE signing out', (
    tester,
  ) async {
    final controller = await pumpController(tester);

    await controller.exitAccount(
      selectMessage: (l10n) => 'disabled',
      navigatorKey: navigatorKey,
      scaffoldMessengerKey: messengerKey,
      isMounted: () => true,
    );
    await tester.pumpAndSettle();

    // Reordering signOut above any de-registration makes those writes fail
    // permission-denied — swallowed by the best-effort catches, so a
    // terminated user quietly keeps receiving pushes.
    expect(calls, ['push', 'presence', 'liveActivity', 'signOut']);
  });

  testWidgets('a second signal while one exit is in flight is ignored', (
    tester,
  ) async {
    final controller = await pumpController(tester);

    // Three listeners can fire for one underlying event (a delete flips
    // status AND empties the doc). Without the guard each starts its own
    // teardown and navigation.
    final first = controller.exitAccount(
      selectMessage: (l10n) => 'disabled',
      navigatorKey: navigatorKey,
      scaffoldMessengerKey: messengerKey,
      isMounted: () => true,
    );
    final second = controller.exitAccount(
      selectMessage: (l10n) => 'disabled',
      navigatorKey: navigatorKey,
      scaffoldMessengerKey: messengerKey,
      isMounted: () => true,
    );
    await Future.wait([first, second]);
    await tester.pumpAndSettle();

    verify(() => auth.signOut()).called(1);
    expect(calls.where((c) => c == 'signOut').length, 1);
  });

  testWidgets('does nothing when nobody is signed in', (tester) async {
    final controller = await pumpController(tester, signedIn: false);

    await controller.exitAccount(
      selectMessage: (l10n) => 'disabled',
      navigatorKey: navigatorKey,
      scaffoldMessengerKey: messengerKey,
      isMounted: () => true,
    );
    await tester.pumpAndSettle();

    expect(calls, isEmpty);
    verifyNever(() => auth.signOut());
  });

  testWidgets(
    'a failed sign-out releases the guard so the next signal retries',
    (tester) async {
      final controller = await pumpController(tester);
      when(() => auth.signOut()).thenThrow(Exception('network'));

      await controller.exitAccount(
        selectMessage: (l10n) => 'disabled',
        navigatorKey: navigatorKey,
        scaffoldMessengerKey: messengerKey,
        isMounted: () => true,
      );
      await tester.pumpAndSettle();

      // The guard must NOT stay latched on failure — the account is still live
      // on this device until a retry succeeds.
      when(() => auth.signOut()).thenAnswer((_) async {
        calls.add('signOut');
      });
      await controller.exitAccount(
        selectMessage: (l10n) => 'disabled',
        navigatorKey: navigatorKey,
        scaffoldMessengerKey: messengerKey,
        isMounted: () => true,
      );
      await tester.pumpAndSettle();

      expect(calls.where((c) => c == 'signOut').length, 1);
    },
  );
}

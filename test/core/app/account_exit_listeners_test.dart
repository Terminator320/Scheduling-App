// Pins the two things AccountExitListeners' own doc calls load-bearing: the
// teardown ORDER (de-register everything BEFORE signOut, because each
// de-registration needs the credential sign-out revokes) and the one-exit-at-a-
// time guard (three listeners can fire for a single underlying event).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:scheduling/core/app/account_exit_listeners.dart';
import 'package:scheduling/features/auth/services/auth_service.dart';
import 'package:scheduling/features/live_activity/application/live_activity_registration_controller.dart';
import 'package:scheduling/features/notifications/application/push_registration_controller.dart';
import 'package:scheduling/features/presence/application/presence_sync_controller.dart';
import 'package:scheduling/l10n/l10n.dart';

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
  Future<AccountExitListeners> pumpListeners(
    WidgetTester tester, {
    bool signedIn = true,
  }) async {
    late AccountExitListeners listeners;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          pushRegistrationControllerProvider.overrideWithValue(push),
          presenceSyncControllerProvider.overrideWithValue(presence),
          liveActivityRegistrationControllerProvider.overrideWithValue(
            liveActivity,
          ),
          authServiceProvider.overrideWithValue(auth),
        ],
        child: MaterialApp(
          navigatorKey: navigatorKey,
          scaffoldMessengerKey: messengerKey,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Consumer(
            builder: (context, ref, _) {
              listeners = AccountExitListeners(
                ref: ref,
                navigatorKey: navigatorKey,
                scaffoldMessengerKey: messengerKey,
                isMounted: () => true,
                isSignedIn: () => signedIn,
              );
              return const Scaffold(body: SizedBox.shrink());
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return listeners;
  }

  testWidgets('tears every registration down BEFORE signing out', (
    tester,
  ) async {
    final listeners = await pumpListeners(tester);

    await listeners.handleAccountExit((l10n) => 'disabled');
    await tester.pumpAndSettle();

    // Reordering signOut above any de-registration makes those writes fail
    // permission-denied — swallowed by the best-effort catches, so a
    // terminated user quietly keeps receiving pushes.
    expect(calls, ['push', 'presence', 'liveActivity', 'signOut']);
  });

  testWidgets('a second signal while one exit is in flight is ignored', (
    tester,
  ) async {
    final listeners = await pumpListeners(tester);

    // Three listeners can fire for one underlying event (a delete flips
    // status AND empties the doc). Without the guard each starts its own
    // teardown and navigation.
    final first = listeners.handleAccountExit((l10n) => 'disabled');
    final second = listeners.handleAccountExit((l10n) => 'disabled');
    await Future.wait([first, second]);
    await tester.pumpAndSettle();

    verify(() => auth.signOut()).called(1);
    expect(calls.where((c) => c == 'signOut').length, 1);
  });

  testWidgets('does nothing when nobody is signed in', (tester) async {
    final listeners = await pumpListeners(tester, signedIn: false);

    await listeners.handleAccountExit((l10n) => 'disabled');
    await tester.pumpAndSettle();

    expect(calls, isEmpty);
    verifyNever(() => auth.signOut());
  });

  testWidgets(
    'a failed sign-out releases the guard so the next signal retries',
    (tester) async {
      final listeners = await pumpListeners(tester);
      when(() => auth.signOut()).thenThrow(Exception('network'));

      await listeners.handleAccountExit((l10n) => 'disabled');
      await tester.pumpAndSettle();

      // The guard must NOT stay latched on failure — the account is still live
      // on this device until a retry succeeds.
      when(() => auth.signOut()).thenAnswer((_) async {
        calls.add('signOut');
      });
      await listeners.handleAccountExit((l10n) => 'disabled');
      await tester.pumpAndSettle();

      expect(calls.where((c) => c == 'signOut').length, 1);
    },
  );
}

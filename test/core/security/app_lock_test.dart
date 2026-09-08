import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:scheduling/core/security/app_lock.dart';
import 'package:scheduling/core/security/biometric_auth_service.dart';
import 'package:scheduling/core/storage/secure_storage_service.dart';
import 'package:scheduling/l10n/l10n.dart';

class _MockSecureStorage extends Mock implements SecureStorageService {}

class _MockBiometrics extends Mock implements BiometricAuthService {}

/// Drives the lifecycle the way the OS does, so the widget's observer fires.
void _lifecycle(AppLifecycleState state) =>
    WidgetsBinding.instance.handleAppLifecycleStateChanged(state);

void main() {
  late _MockSecureStorage storage;
  late _MockBiometrics biometrics;

  setUp(() {
    storage = _MockSecureStorage();
    biometrics = _MockBiometrics();
    when(() => biometrics.isAvailable()).thenAnswer((_) async => true);
    when(() => biometrics.authenticate(any())).thenAnswer((_) async => false);
  });

  Future<void> pumpLock(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          secureStorageServiceProvider.overrideWithValue(storage),
          biometricAuthServiceProvider.overrideWithValue(biometrics),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: AppLock(child: Scaffold(body: Text('secret'))),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The lock overlay is private, so key off its Unlock button.
  bool isLocked(WidgetTester tester) =>
      find.byIcon(Icons.lock_open_rounded).evaluate().isNotEmpty;

  testWidgets('a resolved-off flag leaves the app unlocked in the background', (
    tester,
  ) async {
    when(() => storage.readFlag(any())).thenAnswer((_) async => false);
    await pumpLock(tester);

    _lifecycle(AppLifecycleState.inactive);
    await tester.pumpAndSettle();

    expect(isLocked(tester), isFalse);
  });

  testWidgets('an UNRESOLVED flag still locks on backgrounding', (
    tester,
  ) async {
    // The gate the OS grabs its app-switcher snapshot behind. Reading the
    // tri-state as a plain bool here left the signed-in session in the
    // switcher unprotected for the whole session after one failed read.
    when(() => storage.readFlag(any())).thenThrow(Exception('keystore'));
    await pumpLock(tester);

    _lifecycle(AppLifecycleState.inactive);
    await tester.pumpAndSettle();

    expect(isLocked(tester), isTrue);
  });

  testWidgets('resume releases a defensive lock once the retry reads off', (
    tester,
  ) async {
    // The retry is held open so the defensive lock is observable: the widget
    // fires one from initState, and letting it settle immediately resolves the
    // flag before backgrounding ever happens.
    final retry = Completer<bool>();
    var attempt = 0;
    when(() => storage.readFlag(any())).thenAnswer((_) {
      if (attempt++ == 0) return Future<bool>.error(Exception('keystore'));
      return retry.future;
    });
    await pumpLock(tester);

    _lifecycle(AppLifecycleState.inactive);
    await tester.pumpAndSettle();
    expect(isLocked(tester), isTrue, reason: 'locked while unresolved');

    _lifecycle(AppLifecycleState.resumed);
    await tester.pump();
    retry.complete(false);
    await tester.pumpAndSettle();

    // Never opted in, so they must not be held behind a biometric prompt.
    expect(isLocked(tester), isFalse);
    verifyNever(() => biometrics.authenticate(any()));
  });

  testWidgets('a PERSISTENTLY unreadable flag still degrades to unlocked', (
    tester,
  ) async {
    // The other half of the tri-state rule, and the one no test pinned: the
    // defensive lock buys the app-switcher window, not a hard guarantee.
    // Someone who never enabled biometrics must never be trapped behind a
    // prompt they cannot satisfy, so a read that NEVER succeeds opens up.
    when(() => storage.readFlag(any())).thenThrow(Exception('keystore'));
    await pumpLock(tester);

    _lifecycle(AppLifecycleState.inactive);
    await tester.pumpAndSettle();
    expect(isLocked(tester), isTrue, reason: 'locked while unresolved');

    _lifecycle(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(isLocked(tester), isFalse);
    verifyNever(() => biometrics.authenticate(any()));
  });

  testWidgets('resume keeps the lock and prompts when the retry reads on', (
    tester,
  ) async {
    var attempt = 0;
    when(() => storage.readFlag(any())).thenAnswer((_) async {
      if (attempt++ == 0) throw Exception('keystore');
      return true;
    });
    await pumpLock(tester);

    _lifecycle(AppLifecycleState.inactive);
    await tester.pumpAndSettle();

    _lifecycle(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(isLocked(tester), isTrue);
    verify(() => biometrics.authenticate(any())).called(greaterThan(0));
  });

  testWidgets('unavailable biometrics opens the session WITHOUT disabling the '
      'stored setting', (tester) async {
    // `isAvailable()` is `try { isDeviceSupported() } catch { false }`, so it
    // returns false for the pre-first-unlock `local_auth` channel window this
    // whole subsystem exists to handle. Persisting that answer turns the
    // user's app lock off forever after one hiccup.
    when(() => storage.readFlag(any())).thenAnswer((_) async => true);
    when(() => storage.writeFlag(any(), value: any(named: 'value')))
        .thenAnswer((_) async {});
    when(() => biometrics.isAvailable()).thenAnswer((_) async => false);

    await pumpLock(tester);

    expect(isLocked(tester), isFalse, reason: 'open for THIS session');
    verifyNever(() => storage.writeFlag(any(), value: any(named: 'value')));
  });

  testWidgets('a successful unlock clears the gate', (tester) async {
    // THE RELEASE SIDE, which no test reached: every other case here stubs
    // `authenticate` to false or to a throw, so the one transition the whole
    // feature exists to perform never executed under test. A regression that
    // locked the app and never opened it would have shipped green.
    when(() => storage.readFlag(any())).thenAnswer((_) async => true);
    when(() => biometrics.authenticate(any())).thenAnswer((_) async => true);

    await pumpLock(tester);

    expect(isLocked(tester), isFalse);
    verify(() => biometrics.authenticate(any())).called(1);
  });

  testWidgets('a refused unlock keeps the gate up and can be retried', (
    tester,
  ) async {
    // The pair to the case above: refusing must leave the overlay in place
    // AND leave the Unlock button working, or a mistyped passcode strands the
    // user on a screen with no way forward.
    when(() => storage.readFlag(any())).thenAnswer((_) async => true);
    await pumpLock(tester);
    expect(isLocked(tester), isTrue);

    when(() => biometrics.authenticate(any())).thenAnswer((_) async => true);
    await tester.tap(find.byIcon(Icons.lock_open_rounded));
    await tester.pumpAndSettle();

    expect(isLocked(tester), isFalse);
  });

  testWidgets('stays locked across hidden and paused, not only inactive', (
    tester,
  ) async {
    // All three states are named in the widget's guard and only `inactive` was
    // ever pumped. They cannot be driven independently — Flutter's binding
    // enforces resumed → inactive → hidden → paused and silently drops a jump —
    // so what is pinned here is that the lock SURVIVES the whole descent. A
    // guard that dropped `paused`/`hidden` would still lock on `inactive`, so
    // only walking the sequence catches it.
    when(() => storage.readFlag(any())).thenAnswer((_) async => true);
    when(() => biometrics.authenticate(any())).thenAnswer((_) async => true);
    await pumpLock(tester);
    expect(isLocked(tester), isFalse, reason: 'unlocked at start');

    when(() => biometrics.authenticate(any())).thenAnswer((_) async => false);
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      _lifecycle(state);
      await tester.pumpAndSettle();
      expect(isLocked(tester), isTrue, reason: 'locked at $state');
    }
  });

  testWidgets('resume re-prompts and unlocks a session locked by backgrounding',
      (tester) async {
    // The full round trip an ordinary app switch takes, which no test drove
    // end to end: unlocked → backgrounded → locked → resumed → unlocked.
    when(() => storage.readFlag(any())).thenAnswer((_) async => true);
    when(() => biometrics.authenticate(any())).thenAnswer((_) async => true);
    await pumpLock(tester);
    expect(isLocked(tester), isFalse);

    when(() => biometrics.authenticate(any())).thenAnswer((_) async => false);
    _lifecycle(AppLifecycleState.inactive);
    _lifecycle(AppLifecycleState.hidden);
    _lifecycle(AppLifecycleState.paused);
    await tester.pumpAndSettle();
    expect(isLocked(tester), isTrue);

    when(() => biometrics.authenticate(any())).thenAnswer((_) async => true);
    _lifecycle(AppLifecycleState.hidden);
    _lifecycle(AppLifecycleState.inactive);
    _lifecycle(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(isLocked(tester), isFalse);
  });

  testWidgets('a thrown biometric prompt does not escape the zone handler', (
    tester,
  ) async {
    when(() => storage.readFlag(any())).thenAnswer((_) async => true);
    when(() => biometrics.authenticate(any())).thenThrow(Exception('plugin'));
    await pumpLock(tester);

    expect(isLocked(tester), isTrue);
    expect(tester.takeException(), isNull);
  });
}

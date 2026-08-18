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
    var attempt = 0;
    when(() => storage.readFlag(any())).thenAnswer((_) async {
      if (attempt++ == 0) throw Exception('keystore');
      return false;
    });
    await pumpLock(tester);

    _lifecycle(AppLifecycleState.inactive);
    await tester.pumpAndSettle();
    expect(isLocked(tester), isTrue, reason: 'locked while unresolved');

    _lifecycle(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    // Never opted in, so they must not be held behind a biometric prompt.
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

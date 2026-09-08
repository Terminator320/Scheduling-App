import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:scheduling/core/storage/secure_storage_service.dart';
import 'package:scheduling/features/settings/application/app_lock_provider.dart';

class _MockSecureStorage extends Mock implements SecureStorageService {}

void main() {
  late _MockSecureStorage storage;
  late ProviderContainer container;

  setUp(() {
    storage = _MockSecureStorage();
    when(() => storage.readFlag(any())).thenAnswer((_) async => false);
    when(
      () => storage.writeFlag(any(), value: any(named: 'value')),
    ).thenAnswer((_) async {});

    container = ProviderContainer(
      overrides: [secureStorageServiceProvider.overrideWithValue(storage)],
    );
    addTearDown(container.dispose);
  });

  test('starts disabled before the stored flag loads', () {
    expect(container.read(appLockEnabledProvider), isFalse);
  });

  test('loads the enabled flag from secure storage', () async {
    when(
      () => storage.readFlag(SecureStorageKeys.biometricEnabled),
    ).thenAnswer((_) async => true);

    // Reading a non-autoDispose NotifierProvider triggers build + async _load
    // and keeps the element alive across the await.
    container.read(appLockEnabledProvider);
    await Future<void>.delayed(Duration.zero);

    expect(container.read(appLockEnabledProvider), isTrue);
  });

  test('stays disabled when the secure-storage read throws', () async {
    when(() => storage.readFlag(any())).thenThrow(Exception('keystore'));

    container.read(appLockEnabledProvider);
    await Future<void>.delayed(Duration.zero);

    expect(container.read(appLockEnabledProvider), isFalse);
  });

  test('a thrown read leaves the flag UNRESOLVED, not disabled', () async {
    when(() => storage.readFlag(any())).thenThrow(Exception('keystore'));

    final notifier = container.read(appLockEnabledProvider.notifier);
    await notifier.ensureLoaded();

    // Same `false` as a genuine opt-out, but distinguishable — which is what
    // stops one transient keychain error disabling the lock for the session.
    expect(container.read(appLockEnabledProvider), isFalse);
    expect(notifier.isResolved, isFalse);
  });

  test('a successful read resolves the flag', () async {
    final notifier = container.read(appLockEnabledProvider.notifier);
    await notifier.ensureLoaded();

    expect(notifier.isResolved, isTrue);
  });

  test('retryIfUnresolved engages the lock once the keychain opens', () async {
    when(() => storage.readFlag(any())).thenThrow(Exception('keystore'));
    final notifier = container.read(appLockEnabledProvider.notifier);
    await notifier.ensureLoaded();
    expect(container.read(appLockEnabledProvider), isFalse);

    // The device is unlocked now, so the same read succeeds.
    when(() => storage.readFlag(any())).thenAnswer((_) async => true);
    await notifier.retryIfUnresolved();

    expect(container.read(appLockEnabledProvider), isTrue);
    expect(notifier.isResolved, isTrue);
  });

  test('retryIfUnresolved is a no-op once resolved', () async {
    final notifier = container.read(appLockEnabledProvider.notifier);
    await notifier.ensureLoaded();
    clearInteractions(storage);

    await notifier.retryIfUnresolved();

    verifyNever(() => storage.readFlag(any()));
  });

  test('setEnabled resolves even after every read has failed', () async {
    when(() => storage.readFlag(any())).thenThrow(Exception('keystore'));
    final notifier = container.read(appLockEnabledProvider.notifier);
    await notifier.ensureLoaded();

    await notifier.setEnabled(value: true);

    // An explicit choice is authoritative; a later resume must not re-read
    // over the top of it.
    expect(notifier.isResolved, isTrue);
    expect(container.read(appLockEnabledProvider), isTrue);
  });

  test('setEnabled writes the flag and updates state', () async {
    await container
        .read(appLockEnabledProvider.notifier)
        .setEnabled(value: true);

    expect(container.read(appLockEnabledProvider), isTrue);
    verify(
      () => storage.writeFlag(SecureStorageKeys.biometricEnabled, value: true),
    ).called(1);
  });

  test('an in-flight initial load cannot overwrite a newer explicit choice', () async {
    final firstRead = Completer<bool>();
    when(
      () => storage.readFlag(SecureStorageKeys.biometricEnabled),
    ).thenAnswer((_) => firstRead.future);

    final notifier = container.read(appLockEnabledProvider.notifier);
    expect(container.read(appLockEnabledProvider), isFalse);

    await notifier.setEnabled(value: true);
    expect(container.read(appLockEnabledProvider), isTrue);

    firstRead.complete(false);
    await notifier.ensureLoaded();

    expect(container.read(appLockEnabledProvider), isTrue);
    expect(notifier.isResolved, isTrue);
  });
}

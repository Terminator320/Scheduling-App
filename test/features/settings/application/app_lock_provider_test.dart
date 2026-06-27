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

  test('setEnabled writes the flag and updates state', () async {
    await container
        .read(appLockEnabledProvider.notifier)
        .setEnabled(value: true);

    expect(container.read(appLockEnabledProvider), isTrue);
    verify(
      () => storage.writeFlag(SecureStorageKeys.biometricEnabled, value: true),
    ).called(1);
  });
}

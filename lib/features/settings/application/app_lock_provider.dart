import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/core/storage/secure_storage_service.dart';

/// Whether biometric app-lock is enabled, backed by encrypted storage.
class AppLockController extends Notifier<bool> {
  @override
  bool build() {
    _load();
    return false;
  }

  Future<void> _load() async {
    try {
      state = await ref
          .read(secureStorageServiceProvider)
          .readFlag(SecureStorageKeys.biometricEnabled);
    } catch (e, st) {
      // Encrypted-storage reads can throw on an Android keystore failure or
      // iOS pre-first-unlock — that's environmental, not a bug.
      if (isKeychainLockedError(e)) {
        ref.read(loggerProvider).warn('APPLOCK read skipped: keychain locked');
      } else {
        ref.read(loggerProvider).warn('APPLOCK read flag failed', e, st);
      }
    }
  }

  Future<void> setEnabled({required bool value}) async {
    await ref
        .read(secureStorageServiceProvider)
        .writeFlag(SecureStorageKeys.biometricEnabled, value: value);
    state = value;
  }
}

final appLockEnabledProvider = NotifierProvider<AppLockController, bool>(
  AppLockController.new,
);

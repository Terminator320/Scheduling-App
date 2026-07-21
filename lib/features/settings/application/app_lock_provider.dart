import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/core/storage/secure_storage_service.dart';

/// Whether the biometric app-lock is enabled. Backed by the encrypted
/// [SecureStorageService] flag; loaded once on first read and toggled from
/// Settings.
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
      // Encrypted-storage reads can throw on Android (keystore/cipher failure).
      // This Future is fired unawaited from build(), so an uncaught throw would
      // become an unhandled async error — log it and leave the lock disabled.
      // A locked iOS Keychain (background launch, pre-first-unlock) is
      // environmental, not a defect — log without a Crashlytics error record.
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

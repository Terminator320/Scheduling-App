import 'package:flutter_riverpod/flutter_riverpod.dart';
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
    state = await ref
        .read(secureStorageServiceProvider)
        .readFlag(SecureStorageKeys.biometricEnabled);
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

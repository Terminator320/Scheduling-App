import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Centralized keys for [SecureStorageService] so callers never pass raw
/// strings around. One namespace = one place to audit what we persist.
abstract final class SecureStorageKeys {
  /// Last e-mail used to sign in, prefilled on the login screen.
  static const rememberedEmail = 'remembered_email';

  /// Whether the user has opted into the biometric app-lock (sub-project D).
  static const biometricEnabled = 'biometric_enabled';

  /// Whether the first-launch onboarding flow has been completed.
  static const onboardingSeen = 'onboarding_seen';

  // Cached signed-in identity, migrated off SharedPreferences (see AuthCache).
  static const cacheUid = 'uc_uid';
  static const cacheDocId = 'uc_doc_id';
  static const cacheColorValue = 'uc_color_value';
  static const cacheName = 'uc_name';
}

/// Thin typed wrapper over [FlutterSecureStorage] — Keychain on iOS,
/// hardware-backed AES/GCM ciphers on Android (API 23+, the v10 default).
///
/// Injectable for tests; mirror the optional-dep pattern used by the other
/// services so a fake storage can be supplied without touching a singleton.
class SecureStorageService {
  SecureStorageService({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  Future<String?> read(String key) => _storage.read(key: key);

  /// Writes [value], or deletes the entry when [value] is null.
  Future<void> write(String key, String? value) => value == null
      ? _storage.delete(key: key)
      : _storage.write(key: key, value: value);

  Future<void> delete(String key) => _storage.delete(key: key);

  Future<bool> readFlag(String key) async =>
      await _storage.read(key: key) == 'true';

  Future<void> writeFlag(String key, {required bool value}) =>
      _storage.write(key: key, value: value ? 'true' : 'false');
}

final secureStorageServiceProvider = Provider<SecureStorageService>(
  (ref) => SecureStorageService(),
);

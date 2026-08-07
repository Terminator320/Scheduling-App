import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:scheduling/core/logging/app_logger.dart';

/// Centralized key namespace for [SecureStorageService], so there's one
/// place to audit persistence.
abstract final class SecureStorageKeys {
  /// Last e-mail used to sign in, prefilled on the login screen.
  static const rememberedEmail = 'remembered_email';

  /// Whether the user has opted into biometric app-lock.
  static const biometricEnabled = 'biometric_enabled';

  /// Whether the first-launch onboarding flow has been completed.
  static const onboardingSeen = 'onboarding_seen';

  // Cached signed-in identity, migrated off SharedPreferences (see AuthCache).
  static const cacheUid = 'uc_uid';
  static const cacheDocId = 'uc_doc_id';
  static const cacheColorValue = 'uc_color_value';
  static const cacheName = 'uc_name';

  /// All user-data keys — add new keys here so they get picked up by the iOS
  /// accessibility migration.
  static const all = [
    rememberedEmail,
    biometricEnabled,
    onboardingSeen,
    cacheUid,
    cacheDocId,
    cacheColorValue,
    cacheName,
  ];
}

/// True when [e] is the iOS Keychain refusing access because the device is
/// locked (-25308). Log this case without sending it to Crashlytics as an error.
bool isKeychainLockedError(Object e) =>
    e is PlatformException && (e.message?.contains('-25308') ?? false);

/// Thin wrapper that uses first_unlock_this_device accessibility to avoid
/// -25308 on locked phones. _ensureMigrated rewrites keys before any operation runs.
class SecureStorageService {
  SecureStorageService({FlutterSecureStorage? storage, AppLogger? logger})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock_this_device,
            ),
          ),
      _logger = logger ?? AppLogger(),
      // Injected storage (tests) skips the platform migration.
      _needsMigration =
          storage == null && defaultTargetPlatform == TargetPlatform.iOS;

  static const _migratedMarker = 'ios_keychain_accessibility_v2';

  /// Backup stash for crash recovery during delete-then-re-add migration.
  static const _backupPrefix = 'mig_bak_';

  // Legacy accessibility options for migration from unlocked/first_unlock classes.
  static const _legacy = FlutterSecureStorage();
  static const _legacyFirstUnlock = FlutterSecureStorage(
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  final FlutterSecureStorage _storage;
  final AppLogger _logger;
  final bool _needsMigration;
  Future<void>? _migration;

  Future<void> _ensureMigrated() {
    if (!_needsMigration) return Future.value();
    return _migration ??= _migrate();
  }

  // Runs once per launch, and keeps retrying on future launches until the
  // migration marker gets written.
  Future<void> _migrate() async {
    try {
      if (await _storage.read(key: _migratedMarker) == 'true') return;
      // Delete-then-add converges every item onto first_unlock_this_device.
      for (final key in SecureStorageKeys.all) {
        final backupKey = '$_backupPrefix$key';
        final value =
            await _legacy.read(key: key) ??
            await _legacyFirstUnlock.read(key: key) ??
            await _storage.read(key: key) ??
            // Recover a value stranded by a crash between delete and re-add.
            await _storage.read(key: backupKey);
        if (value == null) continue;
        await _storage.write(key: backupKey, value: value);
        await _storage.delete(key: key);
        await _storage.write(key: key, value: value);
        await _storage.delete(key: backupKey);
      }
      await _storage.write(key: _migratedMarker, value: 'true');
    } catch (e, st) {
      // Could be a locked keychain or just a transient failure — either way,
      // retry next launch and log the two cases separately.
      if (isKeychainLockedError(e)) {
        _logger.warn('APPLOCK keychain migration deferred (device locked)');
      } else {
        _logger.warn('APPLOCK keychain migration failed', e, st);
      }
      _migration = null;
    }
  }

  Future<String?> read(String key) async {
    await _ensureMigrated();
    return _storage.read(key: key);
  }

  /// Writes [value], or deletes the entry when [value] is null.
  Future<void> write(String key, String? value) async {
    await _ensureMigrated();
    return value == null
        ? _storage.delete(key: key)
        : _storage.write(key: key, value: value);
  }

  Future<void> delete(String key) async {
    await _ensureMigrated();
    return _storage.delete(key: key);
  }

  Future<bool> readFlag(String key) async => await read(key) == 'true';

  Future<void> writeFlag(String key, {required bool value}) =>
      write(key, value ? 'true' : 'false');
}

final secureStorageServiceProvider = Provider<SecureStorageService>(
  (ref) => SecureStorageService(),
);

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
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

  /// Every user-data key above — the iOS accessibility migration sweeps this
  /// list. Add new keys here too.
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
/// locked (`errSecInteractionNotAllowed`, -25308) — an environmental state
/// (background launch on a locked phone), not a defect. Catch sites should
/// log it without a Crashlytics error record.
bool isKeychainLockedError(Object e) =>
    e is PlatformException && (e.message?.contains('-25308') ?? false);

/// Thin typed wrapper over [FlutterSecureStorage] — Keychain on iOS,
/// hardware-backed AES/GCM ciphers on Android (API 23+, the v10 default).
///
/// iOS items are stored with `first_unlock` accessibility (readable while the
/// device is locked, after the first unlock since boot) — the default
/// `unlocked` class made every read fail with -25308 when a content-available
/// push cold-started the app on a locked phone, which both spammed
/// Crashlytics and left the biometric app-lock silently disengaged for that
/// session. Items written before this change carry the old `unlocked` class,
/// and the plugin's write path can't update in place across accessibility
/// classes, so [_ensureMigrated] rewrites every known key once (delete —
/// which ignores accessibility — then re-add) before any other operation.
///
/// Injectable for tests; mirror the optional-dep pattern used by the other
/// services so a fake storage can be supplied without touching a singleton.
class SecureStorageService {
  SecureStorageService({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock,
            ),
          ),
      // Injected storage (tests) skips the platform migration.
      _needsMigration =
          storage == null && defaultTargetPlatform == TargetPlatform.iOS;

  static const _migratedMarker = 'ios_first_unlock_migrated';

  /// Default-options instance (accessibility `unlocked`) used ONLY by the
  /// migration to find items written before the `first_unlock` switch —
  /// whichever way the platform treats the query's accessibility attribute
  /// (match filter or ignored), one of the two reads resolves the old item.
  static const _legacy = FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  final bool _needsMigration;
  Future<void>? _migration;

  Future<void> _ensureMigrated() {
    if (!_needsMigration) return Future.value();
    return _migration ??= _migrate();
  }

  /// One-shot per launch; re-runs on later launches until the marker lands
  /// (e.g. the first attempt happened pre-first-unlock and every read threw).
  Future<void> _migrate() async {
    try {
      if (await _storage.read(key: _migratedMarker) == 'true') return;
      // Delete strips the accessibility attribute entirely, so
      // delete-then-add converges every item onto first_unlock.
      for (final key in SecureStorageKeys.all) {
        final value =
            await _legacy.read(key: key) ?? await _storage.read(key: key);
        if (value == null) continue;
        await _storage.delete(key: key);
        await _storage.write(key: key, value: value);
      }
      await _storage.write(key: _migratedMarker, value: 'true');
    } catch (_) {
      // Locked keychain or transient failure — retry on the next launch.
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

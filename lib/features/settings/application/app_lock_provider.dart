import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/core/storage/secure_storage_service.dart';

/// Whether biometric app-lock is enabled, backed by encrypted storage.
///
/// The state is `false` until a read actually succeeds, so "off" and "we could
/// not find out" look identical to a reader — which is fine for the Settings
/// switch but NOT for the lock itself. [isResolved] tells those two apart, and
/// [retryIfUnresolved] is what keeps a single failed read from disabling the
/// lock for the rest of the session (see `AppLock`).
class AppLockController extends Notifier<bool> {
  Future<void>? _loading;
  bool _resolved = false;
  int _revision = 0;

  /// True once a read has actually settled. A `false` state with this still
  /// false means "unknown", not "disabled".
  bool get isResolved => _resolved;

  @override
  bool build() {
    _loading = _load();
    return false;
  }

  /// Completes when the first read has settled, successfully or not.
  Future<void> ensureLoaded() => _loading ?? Future<void>.value();

  /// Re-attempts a read that has never succeeded. A no-op once resolved, so
  /// callers can fire it on every resume without re-hitting the keychain.
  Future<void> retryIfUnresolved() {
    if (_resolved) return Future<void>.value();
    return _loading = _load();
  }

  Future<void> _load() async {
    final logger = ref.read(loggerProvider);
    final revision = _revision;
    try {
      final enabled = await ref
          .read(secureStorageServiceProvider)
          .readFlag(SecureStorageKeys.biometricEnabled);
      if (revision != _revision) return;
      state = enabled;
      _resolved = true;
    } catch (e, st) {
      // Encrypted-storage reads can throw on an Android keystore failure or
      // iOS pre-first-unlock — that's environmental, not a bug. Deliberately
      // leaves `_resolved` false so a later resume retries.
      if (isKeychainLockedError(e)) {
        logger.warn('APPLOCK read skipped: keychain locked');
      } else {
        logger.warn('APPLOCK read flag failed', e, st);
      }
    }
  }

  Future<void> setEnabled({required bool value}) async {
    final revision = ++_revision;
    await ref
        .read(secureStorageServiceProvider)
        .writeFlag(SecureStorageKeys.biometricEnabled, value: value);
    if (revision != _revision) return;
    state = value;
    // An explicit choice is authoritative even if every read so far has failed.
    _resolved = true;
  }
}

final appLockEnabledProvider = NotifierProvider<AppLockController, bool>(
  AppLockController.new,
);

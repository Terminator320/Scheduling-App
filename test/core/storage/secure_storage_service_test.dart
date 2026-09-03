import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/core/storage/secure_storage_service.dart';

// The private migration marker written once the keychain accessibility
// migration completes (see SecureStorageService._migratedMarker).
const _migratedMarker = 'ios_keychain_accessibility_v2';

// The private backup-slot prefix used during delete-then-rewrite migration.
const _backupPrefix = 'mig_bak_';

// Reads straight through the shared in-memory mock, bypassing the service.
Future<String?> _raw(String key) => const FlutterSecureStorage().read(key: key);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SecureStorageService migration (iOS)', () {
    setUp(() {
      // _needsMigration is true only when storage is not injected AND the
      // platform is iOS — force iOS so the migration path actually runs.
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    });

    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
    });

    test('fresh install runs migration and sets the marker', () async {
      FlutterSecureStorage.setMockInitialValues({});
      final service = SecureStorageService();

      // Any public method triggers _ensureMigrated first.
      await service.read(SecureStorageKeys.rememberedEmail);

      expect(await _raw(_migratedMarker), 'true');
    });

    test('values written pre-migration remain readable afterwards', () async {
      FlutterSecureStorage.setMockInitialValues({
        SecureStorageKeys.rememberedEmail: 'user@example.com',
        SecureStorageKeys.biometricEnabled: 'true',
        SecureStorageKeys.cacheUid: 'uid-42',
      });
      final service = SecureStorageService();

      expect(
        await service.read(SecureStorageKeys.rememberedEmail),
        'user@example.com',
      );
      expect(
        await service.readFlag(SecureStorageKeys.biometricEnabled),
        isTrue,
      );
      expect(await service.read(SecureStorageKeys.cacheUid), 'uid-42');
      // Migration completed as part of the read.
      expect(await _raw(_migratedMarker), 'true');
    });

    test('every key in SecureStorageKeys.all survives migration', () async {
      final seeded = {
        for (final key in SecureStorageKeys.all) key: 'v_$key',
      };
      FlutterSecureStorage.setMockInitialValues(seeded);
      final service = SecureStorageService();

      for (final key in SecureStorageKeys.all) {
        expect(await service.read(key), 'v_$key', reason: 'key $key lost');
      }
    });

    test(
      'an already-migrated store leaves existing values untouched',
      () async {
        FlutterSecureStorage.setMockInitialValues({
          _migratedMarker: 'true',
          SecureStorageKeys.cacheName: 'Jane',
        });
        final service = SecureStorageService();

        // Marker present => migration is a no-op; the value stays readable and
        // the marker is unchanged.
        expect(await service.read(SecureStorageKeys.cacheName), 'Jane');
        expect(await _raw(_migratedMarker), 'true');
        // The no-op path never mints a backup-slot entry.
        expect(
          await _raw('$_backupPrefix${SecureStorageKeys.cacheName}'),
          isNull,
        );
      },
    );

    test('recovers a value stranded in the backup slot by a crash', () async {
      // Simulates a crash between delete and re-add: only the backup remains.
      FlutterSecureStorage.setMockInitialValues({
        '$_backupPrefix${SecureStorageKeys.cacheName}': 'Recovered',
      });
      final service = SecureStorageService();

      expect(await service.read(SecureStorageKeys.cacheName), 'Recovered');
      // The backup slot is cleaned up once the primary is rewritten.
      expect(
        await _raw('$_backupPrefix${SecureStorageKeys.cacheName}'),
        isNull,
      );
      expect(await _raw(_migratedMarker), 'true');
    });

    // The catch path had nothing driving it, so `_migration = null` at the end
    // of it was unpinned.
    group('a THROWING migration', () {
      tearDown(() {
        FlutterSecureStorage.setMockInitialValues({});
      });

      test('is retried on the next operation, not cached as done', () async {
        final platform = _FlakyStorage({SecureStorageKeys.cacheDocId: 'doc-1'});
        FlutterSecureStoragePlatform.instance = platform;
        final logger = _RecordingLogger();
        final service = SecureStorageService(logger: logger);

        // First pass throws part-way through and swallows.
        platform.failing = true;
        await service.read(SecureStorageKeys.cacheDocId);
        expect(await _raw(_migratedMarker), isNull);

        // Second pass must actually re-run rather than await a settled future.
        platform.failing = false;
        await service.read(SecureStorageKeys.cacheDocId);
        expect(await _raw(_migratedMarker), 'true');
        expect(await service.read(SecureStorageKeys.cacheDocId), 'doc-1');
      });

      test(
        'a locked keychain (-25308) is logged as DEFERRED, not as a fault',
        () async {
          // isKeychainLockedError classifies the pre-first-unlock window so a
          // content-available push cold-starting a locked phone does not file a
          // Crashlytics fault every time.
          final platform = _FlakyStorage({})
            ..failing = true
            ..error = PlatformException(code: 'Unexpected', message: '-25308');
          FlutterSecureStoragePlatform.instance = platform;
          final logger = _RecordingLogger();

          await SecureStorageService(
            logger: logger,
          ).read(SecureStorageKeys.cacheDocId);

          expect(logger.warnings.single, contains('deferred'));
          expect(logger.errors, isEmpty);
        },
      );

      test('any other failure is logged WITH the error', () async {
        final platform = _FlakyStorage({})
          ..failing = true
          ..error = Exception('keychain on fire');
        FlutterSecureStoragePlatform.instance = platform;
        final logger = _RecordingLogger();

        await SecureStorageService(
          logger: logger,
        ).read(SecureStorageKeys.cacheDocId);

        expect(logger.warnings.single, contains('failed'));
        expect(logger.errors, hasLength(1));
      });
    });

    test('migration runs only once across multiple operations', () async {
      FlutterSecureStorage.setMockInitialValues({
        SecureStorageKeys.cacheDocId: 'doc-1',
      });
      final service = SecureStorageService();

      await service.read(SecureStorageKeys.cacheDocId);
      await service.write(SecureStorageKeys.cacheName, 'Later');

      // Original migrated value and the later write both persist.
      expect(await service.read(SecureStorageKeys.cacheDocId), 'doc-1');
      expect(await service.read(SecureStorageKeys.cacheName), 'Later');
      expect(await _raw(_migratedMarker), 'true');
    });
  });

  group('SecureStorageService public read/write/delete', () {
    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      FlutterSecureStorage.setMockInitialValues({});
    });

    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
    });

    test(
      'round-trips write/read/delete for a key in SecureStorageKeys.all',
      () async {
        final service = SecureStorageService();

        await service.write(SecureStorageKeys.cacheUid, 'uid-123');
        expect(await service.read(SecureStorageKeys.cacheUid), 'uid-123');

        await service.delete(SecureStorageKeys.cacheUid);
        expect(await service.read(SecureStorageKeys.cacheUid), isNull);
      },
    );

    test('write(null) deletes the entry', () async {
      final service = SecureStorageService();

      await service.write(SecureStorageKeys.rememberedEmail, 'a@b.com');
      expect(await service.read(SecureStorageKeys.rememberedEmail), 'a@b.com');

      await service.write(SecureStorageKeys.rememberedEmail, null);
      expect(await service.read(SecureStorageKeys.rememberedEmail), isNull);
    });

    test('readFlag/writeFlag round-trip', () async {
      final service = SecureStorageService();

      expect(await service.readFlag(SecureStorageKeys.onboardingSeen), isFalse);

      await service.writeFlag(SecureStorageKeys.onboardingSeen, value: true);
      expect(await service.readFlag(SecureStorageKeys.onboardingSeen), isTrue);

      await service.writeFlag(SecureStorageKeys.onboardingSeen, value: false);
      expect(await service.readFlag(SecureStorageKeys.onboardingSeen), isFalse);
    });
  });

  group('SecureStorageService with injected storage', () {
    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
    });

    test('injected storage skips the platform migration', () async {
      // Injecting storage sets _needsMigration = false even on iOS.
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      FlutterSecureStorage.setMockInitialValues({
        SecureStorageKeys.cacheName: 'X',
      });
      final service = SecureStorageService(
        storage: const FlutterSecureStorage(),
      );

      // Value is served directly, but no migration marker is written.
      expect(await service.read(SecureStorageKeys.cacheName), 'X');
      expect(await _raw(_migratedMarker), isNull);
    });

    test('non-iOS platform skips migration', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      FlutterSecureStorage.setMockInitialValues({
        SecureStorageKeys.cacheName: 'Y',
      });
      final service = SecureStorageService();

      expect(await service.read(SecureStorageKeys.cacheName), 'Y');
      expect(await _raw(_migratedMarker), isNull);
    });
  });
}

/// In-memory storage whose WRITES can be made to throw, so the migration
/// failure path is reachable.
class _FlakyStorage extends TestFlutterSecureStoragePlatform {
  _FlakyStorage(super.data);

  bool failing = false;
  Exception error = PlatformException(code: 'Unexpected', message: '-25308');

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async {
    if (failing) throw error;
    return super.write(key: key, value: value, options: options);
  }
}

class _RecordingLogger extends AppLogger {
  final warnings = <String>[];
  final errors = <Object>[];

  @override
  void warn(String message, [Object? error, StackTrace? stack]) {
    warnings.add(message);
    if (error != null) errors.add(error);
  }
}

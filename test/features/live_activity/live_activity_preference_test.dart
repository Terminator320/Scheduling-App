import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/features/live_activity/application/live_activity_preference.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

class _RecordingLogger extends AppLogger {
  final warnings = <String>[];

  @override
  void warn(String message, [Object? error, StackTrace? stack]) {
    warnings.add(message);
  }
}

class _ThrowingPreferencesStore extends SharedPreferencesStorePlatform {
  _ThrowingPreferencesStore(this._backing);

  final SharedPreferencesStorePlatform _backing;

  @override
  Future<bool> clear() => _backing.clear();

  @override
  Future<Map<String, Object>> getAll() => _backing.getAll();

  @override
  Future<bool> remove(String key) => _backing.remove(key);

  @override
  Future<bool> setValue(String valueType, String key, Object value) {
    throw Exception('prefs write failed');
  }
}

class _DelayedGetAllStore extends SharedPreferencesStorePlatform {
  _DelayedGetAllStore(this._backing, this._releaseRead);

  final SharedPreferencesStorePlatform _backing;
  final Future<void> _releaseRead;

  @override
  Future<bool> clear() => _backing.clear();

  @override
  Future<Map<String, Object>> getAll() async {
    await _releaseRead;
    return _backing.getAll();
  }

  @override
  Future<bool> remove(String key) => _backing.remove(key);

  @override
  Future<bool> setValue(String valueType, String key, Object value) =>
      _backing.setValue(valueType, key, value);
}

void main() {
  late ProviderContainer container;
  late _RecordingLogger logger;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    logger = _RecordingLogger();
    container = ProviderContainer(
      overrides: [loggerProvider.overrideWithValue(logger)],
    )
      // The preference loads asynchronously from build(); an explicit listener
      // keeps the state alive across reads.
      ..listen(liveActivityEnabledProvider, (_, _) {});
  });

  tearDown(() => container.dispose());

  group('liveActivityEnabledProvider', () {
    test('defaults to enabled for a device that never set it', () async {
      expect(container.read(liveActivityEnabledProvider), isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(liveActivityEnabledProvider), isTrue);
    });

    test('restores a stored opt-out', () async {
      SharedPreferences.setMockInitialValues({
        'live_activity_enabled': false,
      });
      final fresh = ProviderContainer()
        ..listen(liveActivityEnabledProvider, (_, _) {})
        ..read(liveActivityEnabledProvider);
      addTearDown(fresh.dispose);
      await Future<void>.delayed(Duration.zero);

      expect(fresh.read(liveActivityEnabledProvider), isFalse);
    });

    test('setEnabled updates state and persists', () async {
      await container
          .read(liveActivityEnabledProvider.notifier)
          .setEnabled(value: false);

      expect(container.read(liveActivityEnabledProvider), isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('live_activity_enabled'), isFalse);
    });

    test('setEnabled back on persists the opt-in', () async {
      final notifier = container.read(liveActivityEnabledProvider.notifier);
      await notifier.setEnabled(value: false);
      await notifier.setEnabled(value: true);

      expect(container.read(liveActivityEnabledProvider), isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('live_activity_enabled'), isTrue);
    });

    test('a write failure restores the previous state', () async {
      final originalStore = SharedPreferencesStorePlatform.instance;
      SharedPreferencesStorePlatform.instance = _ThrowingPreferencesStore(
        originalStore,
      );
      addTearDown(() => SharedPreferencesStorePlatform.instance = originalStore);

      final notifier = container.read(liveActivityEnabledProvider.notifier);
      expect(container.read(liveActivityEnabledProvider), isTrue);

      await notifier.setEnabled(value: false);

      expect(container.read(liveActivityEnabledProvider), isTrue);
      expect(logger.warnings.single, 'LIVE-ACT write preference failed');
    });

    test('an in-flight initial load cannot overwrite a newer explicit choice', () async {
      SharedPreferences.setMockInitialValues({
        'live_activity_enabled': false,
      });
      final releaseRead = Completer<void>();
      final originalStore = SharedPreferencesStorePlatform.instance;
      SharedPreferencesStorePlatform.instance = _DelayedGetAllStore(
        originalStore,
        releaseRead.future,
      );
      addTearDown(() => SharedPreferencesStorePlatform.instance = originalStore);

      final fresh = ProviderContainer(
        overrides: [loggerProvider.overrideWithValue(logger)],
      )
        ..listen(liveActivityEnabledProvider, (_, _) {})
        ..read(liveActivityEnabledProvider);
      addTearDown(fresh.dispose);

      final notifier = fresh.read(liveActivityEnabledProvider.notifier);
      await notifier.setEnabled(value: true);
      expect(fresh.read(liveActivityEnabledProvider), isTrue);

      releaseRead.complete();
      await notifier.ready;

      expect(fresh.read(liveActivityEnabledProvider), isTrue);
    });
  });
}

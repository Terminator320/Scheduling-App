import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/features/live_activity/application/live_activity_preference.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late ProviderContainer container;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    container = ProviderContainer()
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
  });
}

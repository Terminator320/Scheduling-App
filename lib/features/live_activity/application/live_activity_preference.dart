import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scheduling/core/logging/app_logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// SharedPreferences key for the user's Live Activity opt-out.
const _keyLiveActivityEnabled = 'live_activity_enabled';

/// Whether this device may host the "time to leave" Live Activity card (on
/// by default). Turning this off must call `unregister()`, since the server
/// push-starts cards from whatever tokens are registered.
class LiveActivityPreferenceController extends Notifier<bool> {
  int _revision = 0;

  /// Resolves once the disk read completes. Callers that act on the
  /// preference must await this first, or a cold start sees the default value
  /// and re-registers a device that had opted out.
  late final Future<void> ready = _load();

  @override
  bool build() {
    unawaited(ready);
    return true;
  }

  Future<void> _load() async {
    final logger = ref.read(loggerProvider);
    final revision = _revision;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (revision != _revision) return;
      state = prefs.getBool(_keyLiveActivityEnabled) ?? true;
    } catch (e, st) {
      // Default to enabled, same as a fresh install — an uncaught throw here
      // from the unawaited `ready` future would be fatal.
      logger.warn('LIVE-ACT read preference failed', e, st);
    }
  }

  Future<void> setEnabled({required bool value}) async {
    final logger = ref.read(loggerProvider);
    final previous = state;
    final revision = ++_revision;
    state = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyLiveActivityEnabled, value);
    } catch (e, st) {
      if (revision == _revision) state = previous;
      logger.warn('LIVE-ACT write preference failed', e, st);
    }
  }
}

final liveActivityEnabledProvider =
    NotifierProvider<LiveActivityPreferenceController, bool>(
      LiveActivityPreferenceController.new,
    );

/// Completes once the stored Live Activity preference has been read.
///
/// UI surfaces that must not render the optimistic default can watch this and
/// wait for it to settle before showing a switch.
final liveActivityPreferenceReadyProvider = FutureProvider<void>(
  (ref) => ref.watch(liveActivityEnabledProvider.notifier).ready,
);

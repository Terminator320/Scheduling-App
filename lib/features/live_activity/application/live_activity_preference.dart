import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scheduling/core/logging/app_logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// SharedPreferences key for the user's Live Activity opt-out.
const _keyLiveActivityEnabled = 'live_activity_enabled';

/// Whether this device may host the "time to leave" Live Activity card (default on, device-local preference).
/// Turning OFF requires `unregister()` to end the live card and delete token rows, since the server push-starts cards from registered tokens.
class LiveActivityPreferenceController extends Notifier<bool> {
  /// Resolves once disk read completes; callers that act on the preference must await this, or cold-start sees default and re-registers opted-out devices.
  late final Future<void> ready = _load();

  @override
  bool build() {
    unawaited(ready);
    return true;
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = prefs.getBool(_keyLiveActivityEnabled) ?? true;
    } catch (e, st) {
      // Default to enabled (same as fresh install) since an uncaught throw from unawaited ready would be fatal.
      ref.read(loggerProvider).warn('LIVE-ACT read preference failed', e, st);
    }
  }

  Future<void> setEnabled({required bool value}) async {
    state = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyLiveActivityEnabled, value);
    } catch (e, st) {
      ref.read(loggerProvider).warn('LIVE-ACT write preference failed', e, st);
    }
  }
}

final liveActivityEnabledProvider =
    NotifierProvider<LiveActivityPreferenceController, bool>(
      LiveActivityPreferenceController.new,
    );

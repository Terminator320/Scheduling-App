import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scheduling/core/logging/app_logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// SharedPreferences key for the user's Live Activity opt-out.
const _keyLiveActivityEnabled = 'live_activity_enabled';

/// Whether this device may host the "time to leave" Live Activity card.
///
/// **On by default** — the card only surfaces at the moment a tech should
/// leave, so it's opt-out rather than opt-in. Device-local (SharedPreferences),
/// not a Firestore field: it's a per-device display preference, and a tech with
/// two phones may reasonably want the card on one of them.
///
/// Turning it OFF cannot be a local flag alone. The card is *push-started* by
/// the server, so as long as this device has a registered push-to-start token a
/// card would still appear. The Settings toggle therefore drives
/// `LiveActivityRegistrationController.unregister()`, which ends any live card
/// and deletes this device's token rows — the flag only keeps a later `sync()`
/// from silently re-registering.
class LiveActivityPreferenceController extends Notifier<bool> {
  /// Resolves once the stored value has been read. [build] optimistically
  /// returns `true` before the disk read finishes, so a caller that acts on the
  /// preference — rather than merely displaying it — MUST await this first, or
  /// the very first read after a cold start always sees the default and an
  /// opted-out device silently re-registers. Settings can read the state
  /// directly; the registration controller cannot.
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
      // Fired unawaited from build(), so an uncaught throw would surface as an
      // unhandled async error. Default to enabled — the same state a fresh
      // install has.
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

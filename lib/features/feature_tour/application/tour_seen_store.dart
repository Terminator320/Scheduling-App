import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scheduling/core/layout/adaptive_shell.dart';
import 'package:scheduling/core/logging/app_logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// SharedPreferences key: names of hub tabs whose tour has been seen.
const _keyTourSeenTabs = 'tour_seen_tabs';

/// Tours seen on device; await ready before reading to avoid replaying on cold start.
class TourSeenController extends Notifier<Set<AdaptiveDestination>> {
  late final Future<void> ready = _load();

  @override
  Set<AdaptiveDestination> build() {
    unawaited(ready);
    return const {};
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final names = prefs.getStringList(_keyTourSeenTabs) ?? const [];
      state = {
        for (final tab in AdaptiveDestination.values)
          if (names.contains(tab.name)) tab,
      };
    } catch (e, st) {
      // Unawaited from build(); defaults to fresh install.
      ref.read(loggerProvider).warn('TOUR read seen flags failed', e, st);
    }
  }

  Future<void> markSeen(AdaptiveDestination tab) async {
    state = {...state, tab};
    await _save();
  }

  Future<void> resetAll() async {
    state = const {};
    await _save();
  }

  /// Unserialized save; safe only because writers can't overlap.
  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_keyTourSeenTabs, [
        for (final tab in state) tab.name,
      ]);
    } catch (e, st) {
      ref.read(loggerProvider).warn('TOUR write seen flags failed', e, st);
    }
  }
}

final tourSeenProvider =
    NotifierProvider<TourSeenController, Set<AdaptiveDestination>>(
      TourSeenController.new,
    );

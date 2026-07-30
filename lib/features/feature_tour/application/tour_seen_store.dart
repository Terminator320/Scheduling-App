import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scheduling/core/navigation/app_destination.dart';
import 'package:scheduling/core/logging/app_logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// SharedPreferences key: names of hub tabs whose tour has been seen.
const _keyTourSeenTabs = 'tour_seen_tabs';

/// Tracks which tours this device has already seen. Await `ready` before
/// reading it, or a cold start can replay a tour that was already seen.
class TourSeenController extends Notifier<Set<AppDestination>> {
  late final Future<void> ready = _load();

  @override
  Set<AppDestination> build() {
    unawaited(ready);
    return const {};
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final names = prefs.getStringList(_keyTourSeenTabs) ?? const [];
      // Lookup-based, so a name that no longer maps to a destination is
      // dropped rather than resurrecting a dead tour.
      state = {
        for (final name in names)
          if (destinationByName(name) case final destination?) destination,
      };
    } catch (e, st) {
      // This is unawaited from build(), so on failure we just fall back to
      // treating the device like a fresh install.
      ref.read(loggerProvider).warn('TOUR read seen flags failed', e, st);
    }
  }

  Future<void> markSeen(AppDestination tab) async {
    state = {...state, tab};
    await _save();
  }

  Future<void> resetAll() async {
    state = const {};
    await _save();
  }

  /// Saves aren't serialized, but that's fine since writers never overlap.
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
    NotifierProvider<TourSeenController, Set<AppDestination>>(
      TourSeenController.new,
    );

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/features/feature_tour/domain/tour_scope.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// SharedPreferences key: storage keys of the tours this device has seen.
/// The entry name predates form tours and is deliberately unchanged — the
/// destination keys inside it are still bare destination names.
const _keyTourSeenTabs = 'tour_seen_tabs';

/// Tracks which tours this device has already seen. Await `ready` before
/// reading it, or a cold start can replay a tour that was already seen.
class TourSeenController extends Notifier<Set<TourScope>> {
  late final Future<void> ready = _load();

  @override
  Set<TourScope> build() {
    unawaited(ready);
    return const {};
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getStringList(_keyTourSeenTabs) ?? const [];
      // Lookup-based, so a key that no longer maps to a scope is dropped
      // rather than resurrecting a dead tour.
      state = {for (final key in keys) ?tourScopeByKey(key)};
    } catch (e, st) {
      // This is unawaited from build(), so on failure we just fall back to
      // treating the device like a fresh install.
      ref.read(loggerProvider).warn('TOUR read seen flags failed', e, st);
    }
  }

  Future<void> markSeen(TourScope scope) async {
    state = {...state, scope};
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
        for (final scope in state) scope.storageKey,
      ]);
    } catch (e, st) {
      ref.read(loggerProvider).warn('TOUR write seen flags failed', e, st);
    }
  }
}

final tourSeenProvider = NotifierProvider<TourSeenController, Set<TourScope>>(
  TourSeenController.new,
);

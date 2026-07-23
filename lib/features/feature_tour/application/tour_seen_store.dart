import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scheduling/core/layout/adaptive_shell.dart';
import 'package:scheduling/core/logging/app_logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// SharedPreferences key: names of hub tabs whose tour has been seen.
const _keyTourSeenTabs = 'tour_seen_tabs';

/// Which tabs' feature tours have already run on this device. Device-local by
/// design (a returning user on a new phone gets the tour again); sign-out does
/// NOT reset it — the Settings "Replay app tour" row is the only reset.
///
/// Mirrors the Live Activity preference controller: `build` returns an
/// optimistic empty set before the disk read finishes, so anything that
/// *acts* on the value (auto-starting a tour) MUST await [ready] first — the
/// optimistic "nothing seen" default would otherwise replay seen tours on
/// cold start.
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
      // Fired unawaited from build(); default to "nothing seen" — the same
      // state a fresh install has.
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

  /// NOTE: mutations are state-then-save over one prefs key with no
  /// serialization — safe only while writers can't overlap (one visible
  /// tour at a time; replay can't be tapped through a running overlay).
  /// A new concurrent writer must add a serialized mutation chain first
  /// (see PendingUploadStore for the failure mode).
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

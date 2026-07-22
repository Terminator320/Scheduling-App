import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scheduling/core/layout/adaptive_shell.dart';
import 'package:scheduling/features/feature_tour/application/tour_seen_store.dart';
import 'package:scheduling/features/feature_tour/domain/tour_definitions.dart';
import 'package:scheduling/features/feature_tour/domain/tour_step_id.dart';
import 'package:showcaseview/showcaseview.dart';

/// Owns one hub tab's feature tour: registers the tab's showcaseview scope,
/// auto-starts the tour exactly once when (a) the tab is the hub's current
/// destination, (b) its seen-flag is loaded AND unset, and (c) [ready] is
/// true (never showcase over a skeleton), and marks the tour seen on finish,
/// skip, or when zero targets survive the mounted-filter.
///
/// Outside a [HubShellScope] (standalone route, widget tests) the tour never
/// auto-starts. Hidden IndexedStack tabs never start: visibility is a build
/// dependency via [HubShellScope.currentOf]. Losing visibility while a tour
/// is RUNNING dismisses the overlay (which marks the tab seen — same
/// semantics as Skip); `_tourRunning` gates both the dismiss and the
/// mark-seen so a tour that never started can't be marked seen by a mere tab
/// switch (showcaseview's dismiss() fires onDismiss even when idle), and the
/// dismiss is deferred post-frame (overlay teardown must not run during
/// build).
class FeatureTourHost extends ConsumerStatefulWidget {
  const FeatureTourHost({
    required this.tab,
    required this.isAdmin,
    required this.stepKeys,
    required this.child,
    this.ready = true,
    super.key,
  });

  final AdaptiveDestination tab;
  final bool isAdmin;

  /// Gate for data-dependent tabs: pass `!isLoading` so the tour doesn't
  /// anchor onto skeleton content. Chrome-only tabs leave it true.
  final bool ready;

  /// The screen's stable per-step keys; ids missing from the tab's catalog
  /// are ignored, ids whose target isn't currently rendered are dropped at
  /// start (see `isTargetRendered` in `_start`).
  final Map<TourStepId, GlobalKey> stepKeys;

  final Widget child;

  @override
  ConsumerState<FeatureTourHost> createState() => _FeatureTourHostState();
}

class _FeatureTourHostState extends ConsumerState<FeatureTourHost> {
  bool _started = false;
  bool _wasVisible = false;

  /// True from startShowCase until onFinish/onDismiss. Gates the
  /// tab-switch dismiss AND the mark-seen: without it, dismissing a scope
  /// whose tour never started could fire onDismiss and permanently mark an
  /// unseen tour as seen.
  bool _tourRunning = false;

  String get _scope => tourScopeName(widget.tab);

  @override
  void initState() {
    super.initState();
    // register() REPLACES an existing scope of the same name (verified in
    // showcaseview 5.1.0) — that makes this safe on a hub identity-change
    // rebuild: the replacement State registers here, and this subtree's
    // Showcase widgets mount afterwards, binding to THIS registration.
    ShowcaseView.register(
      scope: _scope,
      onFinish: _onTourEnd,
      onDismiss: (_) => _onTourEnd(),
    );
  }

  @override
  void dispose() {
    // Deliberately NO unregister: on an identity-change rebuild the new
    // State's initState runs before this dispose finalizes, so unregistering
    // here would tear down the registration the replacement just made (and
    // getNamed on a torn-down scope throws). A stale registration is
    // harmless — the next register replaces it. Just close a live overlay.
    if (_tourRunning) {
      _tourRunning = false; // suppress _onTourEnd: unfinished, not seen
      try {
        ShowcaseView.getNamed(_scope).dismiss();
      } catch (_) {
        // Scope already replaced/gone — nothing to close.
      }
    }
    super.dispose();
  }

  /// Finish and dismiss both end the tour; only a tour that actually ran
  /// marks the tab seen.
  void _onTourEnd() {
    if (!_tourRunning) return;
    _tourRunning = false;
    _markSeen();
  }

  void _markSeen() {
    unawaited(ref.read(tourSeenProvider.notifier).markSeen(widget.tab));
  }

  @override
  Widget build(BuildContext context) {
    final seen = ref.watch(tourSeenProvider);
    final visible = HubShellScope.currentOf(context) == widget.tab;
    if (_wasVisible && !visible && _tourRunning) {
      // Tab switched away mid-tour: never leave the overlay over another
      // tab. Post-frame — overlay teardown (and the provider write its
      // onDismiss triggers) must not run during build. onDismiss then marks
      // this tab seen (switching away == skipping).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_tourRunning) return;
        try {
          ShowcaseView.getNamed(_scope).dismiss();
        } catch (_) {
          _tourRunning = false;
        }
      });
    }
    _wasVisible = visible;
    if (seen.contains(widget.tab)) {
      // Re-arm so a Settings "replay" reset can start the tour again.
      _started = false;
    } else if (visible && widget.ready && !_started) {
      _started = true;
      unawaited(_start());
    }
    return widget.child;
  }

  Future<void> _start() async {
    // Never act on the optimistic empty default — see TourSeenController.
    await ref.read(tourSeenProvider.notifier).ready;
    if (!mounted) return;
    if (ref.read(tourSeenProvider).contains(widget.tab)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Conditions may have changed across the await/frame boundary.
      if (HubShellScope.readCurrentOf(context) != widget.tab) return;
      final steps = tourStepsFor(widget.tab, isAdmin: widget.isAdmin);
      try {
        final showcaseView = ShowcaseView.getNamed(_scope);
        // showcaseview 5.x no longer attaches the GlobalKey to the Showcase
        // widget's Element (it's stored as a registry id only), so
        // `key.currentContext` is always null here — `isTargetRendered` is
        // the package's own replacement for "is this target mounted".
        final keys = <GlobalKey>[
          for (final id in steps)
            if (widget.stepKeys[id] case final key?
                when showcaseView.isTargetRendered(key))
              key,
        ];
        if (keys.isEmpty) {
          // Nothing to point at (layout variant, role) — don't retry
          // forever. Direct markSeen: _onTourEnd is only for tours that ran.
          _markSeen();
          return;
        }
        _tourRunning = true;
        showcaseView.startShowCase(keys);
      } catch (_) {
        // getNamed throws if the scope vanished (shouldn't happen — nothing
        // unregisters — but a dead tour must not crash the tab).
        _tourRunning = false;
      }
    });
  }
}

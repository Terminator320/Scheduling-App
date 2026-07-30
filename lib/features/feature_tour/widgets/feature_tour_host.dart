import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scheduling/core/navigation/app_destination.dart';
import 'package:scheduling/core/navigation/hub_shell_scope.dart';
import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/features/feature_tour/application/tour_seen_store.dart';
import 'package:scheduling/features/feature_tour/domain/tour_definitions.dart';
import 'package:scheduling/features/feature_tour/domain/tour_step_id.dart';
import 'package:showcaseview/showcaseview.dart';

/// Runs one hub tab's feature tour — registers the scope, auto-starts once
/// ready, and marks the tab seen when the tour finishes.
class FeatureTourHost extends ConsumerStatefulWidget {
  const FeatureTourHost({
    required this.destination,
    required this.isAdmin,
    required this.stepKeys,
    required this.child,
    this.ready = true,
    this.autoScroll = false,
    super.key,
  });

  final AppDestination destination;
  final bool isAdmin;

  /// Gate for tabs whose content loads asynchronously — pass `!isLoading`
  /// so the tour doesn't end up targeting skeleton placeholders.
  final bool ready;

  /// Keys for each step — an id that's missing or not yet rendered is just skipped.
  final Map<TourStepId, GlobalKey> stepKeys;

  /// Enable auto-scroll for tabs with below-fold targets (e.g., Settings).
  final bool autoScroll;

  final Widget child;

  @override
  ConsumerState<FeatureTourHost> createState() => _FeatureTourHostState();
}

class _FeatureTourHostState extends ConsumerState<FeatureTourHost> {
  bool _started = false;
  bool _wasVisible = false;

  /// True while the tour is actually running, from startShowCase until
  /// onFinish/onDismiss. Gates markSeen so we never mark a tour seen that
  /// didn't actually run.
  bool _tourRunning = false;

  String get _scope => tourScopeName(widget.destination);

  /// Captured each build in route mode. ModalRoute.of cannot be called from
  /// a post-frame callback without registering a spurious dependency, so
  /// the one-shot recheck reads this field instead.
  ModalRoute<Object?>? _route;

  /// A hub tab is visible when the shell says so; a pushed destination is
  /// visible when its own route is on top. The sealed type picks the mode —
  /// NOT a null HubShellScope, which also describes a hub screen hosted
  /// standalone in a test, where "never start" must be preserved.
  bool _isVisible(BuildContext context) {
    switch (widget.destination) {
      case final HubTab tab:
        return HubShellScope.currentOf(context) == tab;
      case PushedDestination():
        // Depends on the route's _ModalScopeStatus, which notifies on
        // isCurrent changes — this dependency is the only rebuild trigger
        // route mode has, and it re-opens the gate when a route above pops.
        final route = ModalRoute.of(context);
        _route = route;
        return route?.isCurrent ?? false;
    }
  }

  /// Route mode only (hub mode never sets _route): waits out the page's
  /// entrance transition so showcase measures settled target positions.
  Future<void> _routeTransitionSettled() async {
    final animation = _route?.animation;
    if (animation == null || !animation.isAnimating) return;
    final completer = Completer<void>();
    void onStatus(AnimationStatus status) {
      if (status == AnimationStatus.forward ||
          status == AnimationStatus.reverse) {
        return;
      }
      animation.removeStatusListener(onStatus);
      if (!completer.isCompleted) completer.complete();
    }

    animation.addStatusListener(onStatus);
    await completer.future;
  }

  @override
  void initState() {
    super.initState();
    // register() replaces any existing scope with the same name, so this is
    // safe to call again on an identity rebuild.
    ShowcaseView.register(
      scope: _scope,
      onFinish: _onTourEnd,
      onDismiss: (_) => _onTourEnd(),
      enableAutoScroll: widget.autoScroll,
    );
  }

  @override
  void dispose() {
    // No unregister here — on an identity rebuild, the new widget's initState
    // runs before this dispose does.
    if (_tourRunning) {
      _tourRunning = false; // Don't mark seen (unfinished tour).
      try {
        ShowcaseView.getNamed(_scope).dismiss();
      } catch (e, st) {
        ref.read(loggerProvider).warn('TOUR dispose dismiss failed', e, st);
      }
    }
    super.dispose();
  }

  /// Finish and dismiss both end the tour, but only a tour that actually ran
  /// marks the tab seen.
  void _onTourEnd() {
    if (!_tourRunning) return;
    _tourRunning = false;
    _markSeen();
  }

  void _markSeen() {
    unawaited(ref.read(tourSeenProvider.notifier).markSeen(widget.destination));
  }

  @override
  Widget build(BuildContext context) {
    final seen = ref.watch(tourSeenProvider);
    final visible = _isVisible(context);
    if (_wasVisible && !visible && _tourRunning) {
      // Dismiss post-frame when tab switched away mid-tour.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_tourRunning) return;
        try {
          ShowcaseView.getNamed(_scope).dismiss();
        } catch (e, st) {
          _tourRunning = false;
          ref.read(loggerProvider).warn('TOUR dismiss failed', e, st);
        }
      });
    }
    _wasVisible = visible;
    if (seen.contains(widget.destination)) {
      // Re-arm so a Settings "replay" reset can start the tour again.
      _started = false;
    } else if (visible && widget.ready && !_started) {
      _started = true;
      unawaited(_start());
    }
    return widget.child;
  }

  Future<void> _start() async {
    // Wait for ready — we never want to act on the optimistic empty default.
    await ref.read(tourSeenProvider.notifier).ready;
    if (!mounted) return;
    if (ref.read(tourSeenProvider).contains(widget.destination)) return;
    await _routeTransitionSettled();
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Reset _started when the destination's been navigated away from, so
      // we don't get stuck and can retry later.
      final stillVisible = switch (widget.destination) {
        final HubTab tab => HubShellScope.readCurrentOf(context) == tab,
        PushedDestination() => _route?.isCurrent ?? false,
      };
      if (!stillVisible) {
        _started = false;
        return;
      }
      final steps = tourStepsFor(widget.destination, isAdmin: widget.isAdmin);
      try {
        final showcaseView = ShowcaseView.getNamed(_scope);
        // showcaseview 5.x never forwards key to Element; use isTargetRendered.
        final keys = <GlobalKey>[
          for (final id in steps)
            if (widget.stepKeys[id] case final key?
                when showcaseView.isTargetRendered(key))
              key,
        ];
        if (keys.isEmpty) {
          // No targets for this layout/role, so just mark it seen directly.
          _markSeen();
          return;
        }
        _tourRunning = true;
        showcaseView.startShowCase(keys);
      } catch (e, st) {
        // getNamed throws if the scope's already gone — don't let that crash the tab.
        _tourRunning = false;
        ref.read(loggerProvider).warn('TOUR start failed', e, st);
      }
    });
  }
}

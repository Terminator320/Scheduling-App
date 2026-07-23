import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scheduling/core/layout/adaptive_shell.dart';
import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/features/feature_tour/application/tour_seen_store.dart';
import 'package:scheduling/features/feature_tour/domain/tour_definitions.dart';
import 'package:scheduling/features/feature_tour/domain/tour_step_id.dart';
import 'package:showcaseview/showcaseview.dart';

/// One hub tab's feature tour: registers scope, auto-starts when ready, marks seen on finish.
class FeatureTourHost extends ConsumerStatefulWidget {
  const FeatureTourHost({
    required this.tab,
    required this.isAdmin,
    required this.stepKeys,
    required this.child,
    this.ready = true,
    this.autoScroll = false,
    super.key,
  });

  final AdaptiveDestination tab;
  final bool isAdmin;

  /// Gate for data-dependent tabs; pass `!isLoading` to avoid targeting skeleton content.
  final bool ready;

  /// Per-step keys; missing or unrendered ids are ignored.
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

  /// True from startShowCase until onFinish/onDismiss; gates mark-seen to prevent marking unseen tours seen.
  bool _tourRunning = false;

  String get _scope => tourScopeName(widget.tab);

  @override
  void initState() {
    super.initState();
    // register() replaces existing scope of same name; safe on identity rebuild.
    ShowcaseView.register(
      scope: _scope,
      onFinish: _onTourEnd,
      onDismiss: (_) => _onTourEnd(),
      enableAutoScroll: widget.autoScroll,
    );
  }

  @override
  void dispose() {
    // No unregister — identity rebuild's new initState runs before dispose.
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
    // Await ready; never act on optimistic empty default.
    await ref.read(tourSeenProvider.notifier).ready;
    if (!mounted) return;
    if (ref.read(tourSeenProvider).contains(widget.tab)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Reset _started on tab-switch to allow later retry (avoid wedging).
      if (HubShellScope.readCurrentOf(context) != widget.tab) {
        _started = false;
        return;
      }
      final steps = tourStepsFor(widget.tab, isAdmin: widget.isAdmin);
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
          // No targets (layout variant/role) — mark seen directly.
          _markSeen();
          return;
        }
        _tourRunning = true;
        showcaseView.startShowCase(keys);
      } catch (e, st) {
        // getNamed throws if scope vanished; don't crash the tab.
        _tourRunning = false;
        ref.read(loggerProvider).warn('TOUR start failed', e, st);
      }
    });
  }
}

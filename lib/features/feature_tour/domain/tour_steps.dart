import 'package:flutter/widgets.dart';

import 'package:scheduling/features/feature_tour/domain/tour_definitions.dart';
import 'package:scheduling/features/feature_tour/domain/tour_scope.dart';
import 'package:scheduling/features/feature_tour/domain/tour_step_id.dart';
import 'package:scheduling/features/feature_tour/widgets/tour_showcase.dart';

/// One screen's tour: its ordered step ids, a `GlobalKey` per step, and the
/// [step] wrapper that ties a widget to one of them.
///
/// This was copy-pasted into six screens as a `_tourSteps` + `_tourKeys` +
/// `_tourStep` trio that differed only in the destination. They had to stay in
/// sync — `_tourKeys[id]!` force-unwraps, and `indexOf`/`length` feed the
/// "step N of M" chrome — and Settings had already drifted by dropping the
/// border-radius parameter. Adding a step to [tourStepsFor] for a screen whose
/// local copy had diverged would crash on that `!`.
///
/// Build it once in the `State` as a `late final` field, exactly where the
/// three members used to live.
class TourSteps {
  TourSteps(this.scope, {required bool isAdmin})
    : ids = tourStepsFor(scope, isAdmin: isAdmin) {
    keys = {for (final id in ids) id: GlobalKey()};
  }

  final TourScope scope;

  /// Ordered — the index in this list IS the step number the tour shows.
  final List<TourStepId> ids;

  late final Map<TourStepId, GlobalKey> keys;

  /// True when [id] belongs to this destination's catalog. The admin-only
  /// screens have empty employee catalogs, so their wraps are guarded on this.
  bool has(TourStepId id) => ids.contains(id);

  /// Wraps [child] as the tour step for [id] when this scope+role catalog
  /// includes it, and returns it untouched otherwise.
  ///
  /// This is the form nearly every call site wants: the admin-only screens
  /// have empty employee catalogs, and [step] force-unwraps `keys[id]!`, so
  /// an unguarded wrap crashes for an employee. Prefer this over
  /// `has(id) ? step(id, child: c) : c`, which was being re-spelled per
  /// screen.
  Widget stepIf(
    TourStepId id,
    Widget child, {
    BorderRadius? targetBorderRadius,
  }) => has(id)
      ? step(id, child: child, targetBorderRadius: targetBorderRadius)
      : child;

  /// Wraps [child] as the tour step for [id]. Throws if [id] isn't in this
  /// catalog — use [stepIf] where that's possible.
  Widget step(
    TourStepId id, {
    required Widget child,
    BorderRadius? targetBorderRadius,
  }) => TourShowcase(
    showcaseKey: keys[id]!,
    scope: scope,
    id: id,
    index: ids.indexOf(id),
    count: ids.length,
    targetBorderRadius: targetBorderRadius,
    child: child,
  );
}

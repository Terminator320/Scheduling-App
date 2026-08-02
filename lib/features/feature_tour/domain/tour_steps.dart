import 'package:flutter/widgets.dart';

import 'package:scheduling/core/navigation/app_destination.dart';
import 'package:scheduling/features/feature_tour/domain/tour_definitions.dart';
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
  TourSteps(this.destination, {required bool isAdmin})
    : ids = tourStepsFor(destination, isAdmin: isAdmin) {
    keys = {for (final id in ids) id: GlobalKey()};
  }

  final AppDestination destination;

  /// Ordered — the index in this list IS the step number the tour shows.
  final List<TourStepId> ids;

  late final Map<TourStepId, GlobalKey> keys;

  /// True when [id] belongs to this destination's catalog. The admin-only
  /// screens have empty employee catalogs, so their wraps are guarded on this.
  bool has(TourStepId id) => ids.contains(id);

  /// Wraps [child] as the tour step for [id].
  Widget step(
    TourStepId id, {
    required Widget child,
    BorderRadius? targetBorderRadius,
  }) => TourShowcase(
    showcaseKey: keys[id]!,
    destination: destination,
    id: id,
    index: ids.indexOf(id),
    count: ids.length,
    targetBorderRadius: targetBorderRadius,
    child: child,
  );
}

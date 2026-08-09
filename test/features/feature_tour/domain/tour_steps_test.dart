// Pins TourSteps — the class that exists to stop a documented crash-on-`!`.
//
// `step` force-unwraps `keys[id]!`, and the admin-only screens have EMPTY
// employee catalogs, so an unguarded wrap crashes for an employee. `stepIf`
// and `stepBarIf` are the guarded forms every call site is supposed to use;
// without a test, a change that made them force-unwrap too would pass the
// suite and crash only on a non-admin device.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/core/navigation/app_destination.dart';
import 'package:scheduling/features/feature_tour/domain/tour_scope.dart';
import 'package:scheduling/features/feature_tour/domain/tour_step_id.dart';
import 'package:scheduling/features/feature_tour/domain/tour_steps.dart';

/// A trivial PreferredSizeWidget for the app-bar `bottom:` slot.
class _Bar extends StatelessWidget implements PreferredSizeWidget {
  const _Bar();

  @override
  Size get preferredSize => const Size.fromHeight(48);

  @override
  Widget build(BuildContext context) => const SizedBox();
}

void main() {
  // Clients is admin-only, so its employee catalog is empty — the exact shape
  // that made an unguarded wrap crash.
  const scope = DestinationTour(HubTab.clients);

  group('stepIf', () {
    test('returns the child untouched for an id outside the catalog', () {
      final tour = TourSteps(scope, isAdmin: false);
      const child = SizedBox(key: Key('target'));

      expect(tour.ids, isEmpty);
      // Identical, not merely equivalent: an untoured screen must render its
      // own widget, not a wrapper around it.
      expect(
        identical(tour.stepIf(TourStepId.clientsSearch, child), child),
        isTrue,
      );
    });

    test('wraps the child for an id the catalog holds', () {
      final tour = TourSteps(scope, isAdmin: true);
      const child = SizedBox(key: Key('target'));

      expect(tour.has(TourStepId.clientsSearch), isTrue);
      expect(
        identical(tour.stepIf(TourStepId.clientsSearch, child), child),
        isFalse,
      );
    });

    test('does not throw on a catalog with no keys at all', () {
      final tour = TourSteps(scope, isAdmin: false);
      // The force-unwrap this class exists to prevent.
      expect(
        () => tour.stepIf(TourStepId.clientsRow, const SizedBox()),
        returnsNormally,
      );
    });
  });

  group('stepBarIf', () {
    test('returns the bar untouched for an id outside the catalog', () {
      final tour = TourSteps(scope, isAdmin: false);
      const bar = _Bar();

      expect(
        identical(tour.stepBarIf(TourStepId.clientsSearch, bar), bar),
        isTrue,
      );
    });

    test('wraps the bar and preserves its preferred size', () {
      final tour = TourSteps(scope, isAdmin: true);
      const bar = _Bar();
      final wrapped = tour.stepBarIf(TourStepId.clientsSearch, bar);

      expect(identical(wrapped, bar), isFalse);
      // The app bar reserves height from this — a wrapper that reported its
      // own size would clip the search field.
      expect(wrapped.preferredSize, bar.preferredSize);
    });
  });

  group('keys', () {
    test('one unique GlobalKey per catalog id', () {
      final tour = TourSteps(scope, isAdmin: true);

      expect(tour.keys.length, tour.ids.length);
      // A shared key would put two showcase targets on one element.
      expect(tour.keys.values.toSet().length, tour.ids.length);
    });
  });
}

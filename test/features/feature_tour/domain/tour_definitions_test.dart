import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/core/navigation/app_destination.dart';
import 'package:scheduling/features/feature_tour/domain/tour_definitions.dart';
import 'package:scheduling/features/feature_tour/domain/tour_scope.dart';
import 'package:scheduling/features/feature_tour/domain/tour_step_id.dart';

/// Destinations that mount a FeatureTourHost. A new destination must
/// either join this set with a catalog, or keep an empty one.
const toured = <AppDestination>{
  HubTab.calendar,
  HubTab.clients,
  HubTab.employees,
  HubTab.liveMap,
  PushedDestination.history,
  PushedDestination.settings,
};

void main() {
  test('employee tours exist only for calendar and settings', () {
    for (final destination in allDestinations) {
      final steps = tourStepsFor(
        DestinationTour(destination),
        isAdmin: false,
      );
      if (destination == HubTab.calendar ||
          destination == PushedDestination.settings) {
        expect(
          steps,
          isNotEmpty,
          reason: '$destination should have an employee tour',
        );
      } else {
        expect(steps, isEmpty, reason: '$destination is admin-only');
      }
    }
  });

  test('employee calendar tour has no admin-only steps', () {
    final steps = tourStepsFor(
      const DestinationTour(HubTab.calendar),
      isAdmin: false,
    );
    expect(steps, isNot(contains(TourStepId.calendarAddAppointment)));
  });

  test('admin calendar tour showcases booking', () {
    final steps = tourStepsFor(
      const DestinationTour(HubTab.calendar),
      isAdmin: true,
    );
    expect(steps, contains(TourStepId.calendarAddAppointment));
  });

  test(
    'every toured destination has an admin tour and no catalog has duplicates',
    () {
      for (final destination in allDestinations) {
        final steps = tourStepsFor(
          DestinationTour(destination),
          isAdmin: true,
        );
        if (toured.contains(destination)) {
          expect(
            steps,
            isNotEmpty,
            reason: '$destination should have an admin tour',
          );
        } else {
          expect(steps, isEmpty, reason: '$destination has no tour host');
        }
        expect(
          steps.toSet().length,
          steps.length,
          reason: '$destination catalog has duplicate steps',
        );
      }
    },
  );

  test('no catalog anywhere repeats a step', () {
    for (final scope in allTourScopes) {
      final steps = tourStepsFor(scope, isAdmin: true);
      expect(
        steps.toSet().length,
        steps.length,
        reason: '${scope.storageKey} catalog has duplicate steps',
      );
    }
  });
}

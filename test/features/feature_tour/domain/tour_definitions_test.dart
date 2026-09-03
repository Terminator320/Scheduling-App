import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/core/navigation/app_destination.dart';
import 'package:scheduling/features/feature_tour/domain/tour_definitions.dart';
import 'package:scheduling/features/feature_tour/domain/tour_scope.dart';
import 'package:scheduling/features/feature_tour/domain/tour_step_id.dart';

/// Destinations that mount a FeatureTourHost.
const toured = <AppDestination>{
  HubTab.calendar,
  HubTab.clients,
  HubTab.employees,
  HubTab.liveMap,
  PushedDestination.history,
  PushedDestination.settings,
  PushedDestination.dashboard,
  PushedDestination.dayRoute,
};

/// The destinations an employee can actually reach — exactly the drawer rows
/// `drawerGroups(isAdmin: false)` offers.
const employeeToured = <AppDestination>{
  HubTab.calendar,
  PushedDestination.dayRoute,
  PushedDestination.history,
  PushedDestination.settings,
};

void main() {
  test(
    'employee tours exist only for the destinations employees can reach',
    () {
      for (final destination in allDestinations) {
        final steps = tourStepsFor(
          DestinationTour(destination),
          isAdmin: false,
        );
        if (employeeToured.contains(destination)) {
          expect(
            steps,
            isNotEmpty,
            reason: '$destination should have an employee tour',
          );
        } else {
          expect(steps, isEmpty, reason: '$destination is admin-only');
        }
      }
    },
  );

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

  test('dashboard has a 4-step admin tour and none for employees', () {
    const scope = DestinationTour(PushedDestination.dashboard);
    expect(tourStepsFor(scope, isAdmin: true), hasLength(4));
    expect(tourStepsFor(scope, isAdmin: false), isEmpty);
  });

  test('day route tours both roles, with the picker admin-only', () {
    const scope = DestinationTour(PushedDestination.dayRoute);
    expect(tourStepsFor(scope, isAdmin: true), hasLength(4));
    final employee = tourStepsFor(scope, isAdmin: false);
    expect(employee, hasLength(3));
    expect(employee, isNot(contains(TourStepId.dayRouteEmployee)));
  });

  test('the gap-filled catalogs grew to their new lengths', () {
    int len(AppDestination d) =>
        tourStepsFor(DestinationTour(d), isAdmin: true).length;
    expect(len(HubTab.calendar), 5);
    expect(len(HubTab.clients), 4);
    expect(len(HubTab.employees), 3);
    expect(len(PushedDestination.history), 3);
  });

  test('the appointment walkthrough is admin-only and 6 steps in order', () {
    const scope = FormTour(TourForm.addAppointment);
    expect(tourStepsFor(scope, isAdmin: true), [
      TourStepId.apptTemplates,
      TourStepId.apptClient,
      TourStepId.apptCrew,
      TourStepId.apptSchedule,
      TourStepId.apptDetails,
      TourStepId.apptSave,
    ]);
    expect(tourStepsFor(scope, isAdmin: false), isEmpty);
  });

  test('the client walkthrough is 4 steps in order', () {
    const scope = FormTour(TourForm.addClient);
    expect(tourStepsFor(scope, isAdmin: true), [
      TourStepId.clientWho,
      TourStepId.clientReach,
      TourStepId.clientSite,
      TourStepId.clientSave,
    ]);
  });

  test('the invite walkthrough is 4 steps in order', () {
    const scope = FormTour(TourForm.invitePerson);
    expect(tourStepsFor(scope, isAdmin: true), [
      TourStepId.personDetails,
      TourStepId.personJobTitle,
      TourStepId.personColour,
      TourStepId.personCreate,
    ]);
    expect(tourStepsFor(scope, isAdmin: false), isEmpty);
  });

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

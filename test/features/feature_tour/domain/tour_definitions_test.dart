import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/core/navigation/app_destination.dart';
import 'package:scheduling/core/navigation/hub_shell_scope.dart';
import 'package:scheduling/features/feature_tour/domain/tour_definitions.dart';
import 'package:scheduling/features/feature_tour/domain/tour_step_id.dart';

void main() {
  test('employee tours exist only for calendar and settings', () {
    for (final tab in allDestinations) {
      final steps = tourStepsFor(tab, isAdmin: false);
      if (tab == HubTab.calendar ||
          tab == PushedDestination.settings) {
        expect(steps, isNotEmpty, reason: '$tab should have an employee tour');
      } else {
        expect(steps, isEmpty, reason: '$tab is admin-only');
      }
    }
  });

  test('employee calendar tour has no admin-only steps', () {
    final steps = tourStepsFor(HubTab.calendar, isAdmin: false);
    expect(steps, isNot(contains(TourStepId.calendarAddAppointment)));
  });

  test('admin calendar tour showcases booking', () {
    final steps = tourStepsFor(HubTab.calendar, isAdmin: true);
    expect(steps, contains(TourStepId.calendarAddAppointment));
  });

  test('every admin tab has a tour and no catalog has duplicates', () {
    for (final tab in allDestinations) {
      final steps = tourStepsFor(tab, isAdmin: true);
      expect(steps, isNotEmpty, reason: '$tab should have an admin tour');
      expect(
        steps.toSet().length,
        steps.length,
        reason: '$tab catalog has duplicate steps',
      );
    }
  });
}

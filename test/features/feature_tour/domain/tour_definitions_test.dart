import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/core/layout/adaptive_shell.dart';
import 'package:scheduling/features/feature_tour/domain/tour_definitions.dart';
import 'package:scheduling/features/feature_tour/domain/tour_step_id.dart';

void main() {
  test('employee tours exist only for calendar and settings', () {
    for (final tab in AdaptiveDestination.values) {
      final steps = tourStepsFor(tab, isAdmin: false);
      if (tab == AdaptiveDestination.calendar ||
          tab == AdaptiveDestination.settings) {
        expect(steps, isNotEmpty, reason: '$tab should have an employee tour');
      } else {
        expect(steps, isEmpty, reason: '$tab is admin-only');
      }
    }
  });

  test('employee calendar tour has no admin-only steps', () {
    final steps = tourStepsFor(AdaptiveDestination.calendar, isAdmin: false);
    expect(steps, isNot(contains(TourStepId.calendarAddAppointment)));
  });

  test('admin calendar tour showcases booking', () {
    final steps = tourStepsFor(AdaptiveDestination.calendar, isAdmin: true);
    expect(steps, contains(TourStepId.calendarAddAppointment));
  });

  test('every admin tab has a tour and no catalog has duplicates', () {
    for (final tab in AdaptiveDestination.values) {
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

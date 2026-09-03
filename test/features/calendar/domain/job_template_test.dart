import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/features/calendar/domain/models/job_template.dart';

// The seeded end time itself is `AppointmentDraftDefaults.endTimeFor`, pinned
// in appointment_draft_defaults_test.dart with these templates' durations.
void main() {
  test('every template has a positive default duration', () {
    for (final t in JobTemplate.values) {
      expect(t.defaultDurationMinutes, greaterThan(0), reason: '$t');
    }
  });
}

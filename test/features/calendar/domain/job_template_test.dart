import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/features/calendar/domain/models/job_template.dart';

void main() {
  group('JobTemplate.endMinutesOfDay', () {
    test('adds the template duration to the start minutes', () {
      // Water heater is a 120-minute job, so 09:00 (540) becomes 11:00 (660).
      expect(JobTemplate.waterHeater.endMinutesOfDay(540), 660);
      // Leak diagnostic is a 30-minute job, so 14:15 (855) becomes 14:45 (885).
      expect(JobTemplate.leakDiagnostic.endMinutesOfDay(855), 885);
    });

    test(
      'clamps inside the same day so a late start cannot wrap past midnight',
      () {
        // 23:30 (1410) plus 120 minutes would land at 1530, but it's clamped
        // to 23:59 (1439).
        expect(JobTemplate.waterHeater.endMinutesOfDay(1410), 24 * 60 - 1);
      },
    );
  });

  test('every template has a positive default duration', () {
    for (final t in JobTemplate.values) {
      expect(t.defaultDurationMinutes, greaterThan(0), reason: '$t');
    }
  });
}

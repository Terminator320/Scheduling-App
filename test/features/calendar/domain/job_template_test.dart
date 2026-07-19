import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/features/calendar/domain/models/job_template.dart';

void main() {
  group('JobTemplate.endMinutesOfDay', () {
    test('adds the template duration to the start minutes', () {
      // Water heater = 120 min; 09:00 (540) → 11:00 (660).
      expect(JobTemplate.waterHeater.endMinutesOfDay(540), 660);
      // Leak diagnostic = 30 min; 14:15 (855) → 14:45 (885).
      expect(JobTemplate.leakDiagnostic.endMinutesOfDay(855), 885);
    });

    test(
      'clamps inside the same day so a late start cannot wrap past midnight',
      () {
        // 23:30 (1410) + 120 min would be 1530; clamped to 23:59 (1439).
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

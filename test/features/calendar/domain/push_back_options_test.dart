import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/features/calendar/domain/policies/push_back_options.dart';

void main() {
  test('a mid-morning job is offered every offset', () {
    expect(pushBackOptionsFor(DateTime(2026, 9, 1, 9, 30)), pushBackMinutes);
  });

  test('offsets that cross midnight are withheld, not clamped', () {
    // 23:30 + 15 stays on the day; +30 lands at 00:00 tomorrow, which would
    // move the job into tomorrow's agenda with nothing on screen saying so.
    expect(pushBackOptionsFor(DateTime(2026, 9, 1, 23, 30)), [15]);
  });

  test('a job at the last minutes of the day has no option at all', () {
    expect(pushBackOptionsFor(DateTime(2026, 9, 1, 23, 50)), isEmpty);
  });

  test('the offsets are ascending and in minutes', () {
    expect(pushBackMinutes, [15, 30, 60, 120]);
  });
}

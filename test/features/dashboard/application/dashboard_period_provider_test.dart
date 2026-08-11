import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/dashboard/application/dashboard_providers.dart';
import 'package:scheduling/features/dashboard/domain/dashboard_period.dart';

/// Fixed clock: Wednesday 2026-07-08, noon.
final _now = DateTime(2026, 7, 8, 12);

void main() {
  late ProviderContainer container;

  setUp(() {
    // The listens keep AutoDispose state alive across reads.
    container =
        ProviderContainer(
            overrides: [dashboardClockProvider.overrideWithValue(() => _now)],
          )
          ..listen(dashboardPeriodProvider, (_, _) {})
          ..listen(dashboardRangeProvider, (_, _) {})
          ..listen(dashboardLiveRangeProvider, (_, _) {})
          ..listen(dashboardHistoryRangeProvider, (_, _) {});
  });

  tearDown(() => container.dispose());

  test('the selected period never reaches the query layer', () {
    // The load-bearing invariant of the whole control: all three periods are
    // served from data the dashboard already fetched, so selecting one must
    // not move a single range. A period that widened the LIVE range would undo
    // the 2026-08-08 split that took the 1000-doc cap off the trend charts.
    AppointmentDateRange live() => container.read(dashboardLiveRangeProvider);
    AppointmentDateRange history() =>
        container.read(dashboardHistoryRangeProvider);
    AppointmentDateRange whole() => container.read(dashboardRangeProvider);

    final liveBefore = live();
    final historyBefore = history();
    final wholeBefore = whole();

    for (final period in DashboardPeriod.values) {
      container.read(dashboardPeriodProvider.notifier).select(period);

      expect(live(), liveBefore, reason: '${period.name} moved the live range');
      expect(history(), historyBefore);
      expect(whole(), wholeBefore);
    }
  });

  test('defaults to today', () {
    expect(container.read(dashboardPeriodProvider), DashboardPeriod.today);
  });

  test('selecting the active period leaves the state identical', () {
    var notifications = 0;
    container.listen(dashboardPeriodProvider, (_, _) => notifications++);

    container.read(dashboardPeriodProvider.notifier)
      ..select(DashboardPeriod.week)
      ..select(DashboardPeriod.week);

    expect(notifications, 1);
  });
}

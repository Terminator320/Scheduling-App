import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/features/calendar/application/appointments_providers.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/clients/application/clients_providers.dart';
import 'package:scheduling/features/dashboard/domain/dashboard_aggregator.dart';
import 'package:scheduling/features/dashboard/domain/dashboard_stats.dart';
import 'package:scheduling/features/employees/application/employees_providers.dart';

/// Injectable clock for tests. The range below is midnight-aligned, which
/// keeps it stable and avoids extra listener churn.
final dashboardClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

/// The whole 8-week window. Only the new-clients read uses it now — the
/// appointment side is split into a live half and a one-shot half below.
final dashboardRangeProvider = Provider.autoDispose<AppointmentDateRange>(
  (ref) => DashboardAggregator.rangeAround(ref.watch(dashboardClockProvider)()),
);

/// The current week onwards — the only part of the window that can change
/// while the dashboard is open, and therefore the only part worth a listener.
final dashboardLiveRangeProvider = Provider.autoDispose<AppointmentDateRange>(
  (ref) =>
      DashboardAggregator.liveRangeAround(ref.watch(dashboardClockProvider)()),
);

/// The seven settled weeks behind it, read ONCE.
final dashboardHistoryRangeProvider =
    Provider.autoDispose<AppointmentDateRange>(
      (ref) => DashboardAggregator.historyRangeAround(
        ref.watch(dashboardClockProvider)(),
      ),
    );

/// One-shot read of the settled weeks.
///
/// A `.get()`, not a `.snapshots()`: these weeks are closed and cannot change
/// under the screen, so a live listener over them was pure cost — and, held
/// together with the live half in ONE 1000-doc-capped stream, it was also what
/// silently truncated the trend charts above ~14 jobs/day.
final dashboardHistoryProvider =
    FutureProvider.autoDispose<List<AppointmentRecord>>((ref) {
      final range = ref.watch(dashboardHistoryRangeProvider);
      return ref.watch(appointmentsRepositoryProvider).fetchInRange(range);
    });

/// Client createdAt timestamps within the dashboard window. Legacy docs that
/// don't have a createdAt are excluded.
final newClientDatesProvider = FutureProvider.autoDispose<List<DateTime>>((
  ref,
) async {
  final range = ref.watch(dashboardRangeProvider);
  final clients = await ref
      .watch(clientsRepositoryProvider)
      .fetchClientsCreatedSince(range.start);
  return [
    for (final client in clients)
      if (client.createdAt != null) client.createdAt!,
  ];
});

/// Combine appointments range, active employees, and new-clients into dashboard stats.
final dashboardStatsProvider = Provider.autoDispose<AsyncValue<DashboardStats>>(
  (ref) {
    final liveRange = ref.watch(dashboardLiveRangeProvider);
    final appointments = ref.watch(appointmentsInRangeProvider(liveRange));
    final history = ref.watch(dashboardHistoryProvider);
    final employees = ref.watch(employeesStreamProvider);
    final clientDates = ref.watch(newClientDatesProvider);

    final sources = <AsyncValue<Object?>>[
      appointments,
      history,
      employees,
      clientDates,
    ];
    for (final source in sources) {
      if (source.hasError) {
        return AsyncValue.error(
          source.error!,
          source.stackTrace ?? StackTrace.current,
        );
      }
    }
    if (sources.any((source) => source.isLoading)) {
      return const AsyncValue.loading();
    }
    return AsyncValue.data(
      DashboardAggregator.computeStats(
        // Merged by doc id, not concatenated: each query reaches back to its
        // own `fetchStart` to catch a run already under way, so the live half
        // re-reads the last fortnight of the history half.
        appointments: DashboardAggregator.mergeById(
          appointments.requireValue,
          history.requireValue,
        ),
        employees: employees.requireValue,
        clientCreatedDates: clientDates.requireValue,
        now: ref.read(dashboardClockProvider)(),
      ),
    );
  },
);

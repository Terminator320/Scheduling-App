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

final dashboardRangeProvider = Provider.autoDispose<AppointmentDateRange>(
  (ref) => DashboardAggregator.rangeAround(ref.watch(dashboardClockProvider)()),
);

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
    final range = ref.watch(dashboardRangeProvider);
    final appointments = ref.watch(appointmentsInRangeProvider(range));
    final employees = ref.watch(employeesStreamProvider);
    final clientDates = ref.watch(newClientDatesProvider);

    final sources = <AsyncValue<Object?>>[
      appointments,
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
        appointments: appointments.requireValue,
        employees: employees.requireValue,
        clientCreatedDates: clientDates.requireValue,
        now: ref.read(dashboardClockProvider)(),
      ),
    );
  },
);

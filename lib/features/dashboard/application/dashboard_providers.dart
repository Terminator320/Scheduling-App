import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/features/calendar/application/appointments_providers.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/clients/application/clients_providers.dart';
import 'package:scheduling/features/dashboard/domain/dashboard_aggregator.dart';
import 'package:scheduling/features/dashboard/domain/dashboard_stats.dart';
import 'package:scheduling/features/employees/application/employees_providers.dart';

/// Injectable clock so tests pin "now". The derived range is midnight-aligned,
/// so the appointments family key stays stable all day (no listener churn).
final dashboardClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

final dashboardRangeProvider = Provider.autoDispose<AppointmentDateRange>(
  (ref) => DashboardAggregator.rangeAround(ref.watch(dashboardClockProvider)()),
);

/// createdAt of every client created inside the dashboard window (one-shot
/// get; legacy docs without createdAt are excluded — accepted undercount).
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

/// Combines the one appointments range stream, the active-employees stream,
/// and the one-shot new-clients read into the full dashboard reduction.
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

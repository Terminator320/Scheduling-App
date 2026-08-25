import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/features/calendar/application/appointments_providers.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/clients/application/clients_providers.dart';
import 'package:scheduling/features/clients/domain/models/client_record.dart';
import 'package:scheduling/features/dashboard/domain/dashboard_aggregator.dart';
import 'package:scheduling/features/dashboard/domain/dashboard_period.dart';
import 'package:scheduling/features/dashboard/domain/dashboard_stats.dart';
import 'package:scheduling/features/employees/application/employees_providers.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';
import 'package:scheduling/features/employees/domain/policies/availability_conflict_policy.dart';

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
/// Kept warm on the same grace as the live half — see [keepWarmWithGrace].
final dashboardHistoryProvider =
    FutureProvider.autoDispose<List<AppointmentRecord>>((ref) {
      keepWarmWithGrace(ref);
      final range = ref.watch(dashboardHistoryRangeProvider);
      return ref.watch(appointmentsRepositoryProvider).fetchInRange(range);
    });

/// Clients created within the dashboard window, newest first.
///
/// Two exclusions, and the second is a deliberate behaviour change:
///
/// - **No `createdAt`** — a legacy doc has nothing to bucket by.
/// - **Archived** — the dashboard answers *what should I look at now*, and an
///   archived client is one you decided not to look at (owner call
///   2026-08-10). Filtered in Dart on purpose: a
///   `.where('archived', isEqualTo: false)` would need an
///   `(archived, createdAt)` composite index and a deploy. The repo's "never
///   filter a server page in Dart" rule is about `fetchClientsPage`, where a
///   shortened page breaks the cursor and truncates the list permanently —
///   this is a bounded one-shot read with no cursor and no pagination, so that
///   hazard does not apply.
/// Kept warm on the same grace as the live half — see [keepWarmWithGrace].
final newClientsProvider = FutureProvider.autoDispose<List<ClientRecord>>((
  ref,
) async {
  keepWarmWithGrace(ref);
  final range = ref.watch(dashboardRangeProvider);
  final clients = await ref
      .watch(clientsRepositoryProvider)
      .fetchClientsCreatedSince(range.start);
  final recent = [
    for (final client in clients)
      if (client.createdAt != null && !client.archived) client,
  ]..sort((a, b) => b.createdAt!.compareTo(a.createdAt!));
  return recent;
});

/// Client createdAt timestamps within the dashboard window, derived from
/// [newClientsProvider] so the two can never disagree about which clients
/// count — and so the fetch happens once.
final newClientDatesProvider = Provider.autoDispose<AsyncValue<List<DateTime>>>(
  (ref) => ref
      .watch(newClientsProvider)
      .whenData((clients) => [for (final c in clients) c.createdAt!]),
);

/// The period the KPI numbers are counted over.
///
/// Deliberately reaches NO query: all three periods fit inside the window
/// already fetched, so this is a pure in-memory filter. Nothing below may pass
/// it to a range provider — a period that widened the live listener would undo
/// the 2026-08-08 split.
final dashboardPeriodProvider =
    NotifierProvider.autoDispose<DashboardPeriodController, DashboardPeriod>(
      DashboardPeriodController.new,
    );

class DashboardPeriodController extends Notifier<DashboardPeriod> {
  @override
  DashboardPeriod build() => DashboardPeriod.today;

  /// Re-tapping the active segment is a no-op rather than a rebuild of every
  /// section watching this.
  void select(DashboardPeriod period) {
    if (period == state) return;
    state = period;
  }
}

/// The two halves of the window, merged by doc id — **jobs only**.
///
/// Split out so the KPI summary and the stats can share one merge, and so
/// changing the period recomputes four counters rather than every section.
///
/// Time off is dropped HERE rather than in each reducer, so every number on
/// the screen answers the same question: a booked absence is not work done,
/// not capacity used, and not an availability conflict. The dashboard is all
/// counts and charts — the surfaces that still show a day off as a card are
/// the calendar agenda and the team detail's TODAY panel.
final dashboardRecordsProvider =
    Provider.autoDispose<AsyncValue<List<AppointmentRecord>>>((ref) {
      final liveRange = ref.watch(dashboardLiveRangeProvider);
      final appointments = ref.watch(appointmentsInRangeProvider(liveRange));
      final history = ref.watch(dashboardHistoryProvider);

      final failure = _firstFailure<List<AppointmentRecord>>([
        appointments,
        history,
      ]);
      if (failure != null) return failure;
      // Merged by doc id, not concatenated: each query reaches back to its own
      // `fetchStart` to catch a run already under way, so the live half
      // re-reads the last fortnight of the history half.
      return AsyncValue.data([
        for (final record in DashboardAggregator.mergeById(
          appointments.requireValue,
          history.requireValue,
        ))
          if (!record.isTimeOff) record,
      ]);
    });

/// The KPI numbers for the selected period.
final dashboardPeriodSummaryProvider =
    Provider.autoDispose<AsyncValue<PeriodSummary>>((ref) {
      final records = ref.watch(dashboardRecordsProvider);
      final clientDates = ref.watch(newClientDatesProvider);

      final failure = _firstFailure<PeriodSummary>([records, clientDates]);
      if (failure != null) return failure;
      return AsyncValue.data(
        DashboardAggregator.computePeriodSummary(
          appointments: records.requireValue,
          clientCreatedDates: clientDates.requireValue,
          window: ref
              .watch(dashboardPeriodProvider)
              .windowFor(ref.read(dashboardClockProvider)()),
        ),
      );
    });

/// Combine appointments range, assignable employees, and new-clients into
/// dashboard stats.
///
/// [assignableEmployeesProvider], not the unfiltered active stream: a
/// dispatcher would sit at a permanent zero in the workload rows and still add
/// their `maxJobsPerDay` to every daily-capacity bar.
final dashboardStatsProvider = Provider.autoDispose<AsyncValue<DashboardStats>>(
  (ref) {
    final records = ref.watch(dashboardRecordsProvider);
    final employees = ref.watch(assignableEmployeesProvider);
    final clientDates = ref.watch(newClientDatesProvider);

    final failure = _firstFailure<DashboardStats>([
      records,
      employees,
      clientDates,
    ]);
    if (failure != null) return failure;
    return AsyncValue.data(
      DashboardAggregator.computeStats(
        appointments: records.requireValue,
        employees: employees.requireValue,
        clientCreatedDates: clientDates.requireValue,
        now: ref.read(dashboardClockProvider)(),
      ),
    );
  },
);

/// Accounts an admin created that were never set up.
///
/// The person is still sitting on the starting password they were handed,
/// which is the one operational risk the P4c design creates — so the dashboard
/// says so.
///
/// Read from [allUsersStreamProvider], never `employeesStreamProvider` or
/// `assignableEmployeesProvider`: the first filters to `status == 'active'`, so
/// this list would be permanently empty and the flag would silently never fire,
/// and the second would additionally hide a pending dispatcher — an account
/// still sitting on its starting password, which is the whole point of the
/// flag. `watchAllUsers()` is already
/// always-on, so this costs no extra listener.
///
/// Sorted oldest-first, and a **null `createdAt` still lists** — the field is
/// function-owned and absent on legacy docs, so "unknown age" must not become
/// "not shown"; those sort last rather than being dropped.
final neverSetUpAccountsProvider =
    Provider.autoDispose<AsyncValue<List<EmployeeRecord>>>(
      (ref) => ref.watch(allUsersStreamProvider).whenData((users) {
        // Exact match: an empty or unknown status is not an invited account.
        return [
          for (final user in users)
            if (user.isInvited) user,
        ]..sort((a, b) {
          final aAt = a.createdAt;
          final bAt = b.createdAt;
          if (aAt == null) return bAt == null ? 0 : 1;
          if (bAt == null) return -1;
          return aAt.compareTo(bAt);
        });
      }),
    );

/// A person and the weekdays they hold booked work on while being marked
/// unavailable for them.
typedef AvailabilityConflict = ({EmployeeRecord employee, Set<int> days});

/// Roster-wide availability conflicts over the dashboard's live window.
///
/// Scoped to that window on purpose: it is the data already on screen, and a
/// wider question would need its own query. A conflict further out than next
/// Monday surfaces when the window reaches it.
final availabilityConflictsProvider =
    Provider.autoDispose<AsyncValue<List<AvailabilityConflict>>>((ref) {
      final records = ref.watch(dashboardRecordsProvider);
      final employees = ref.watch(assignableEmployeesProvider);

      final failure = _firstFailure<List<AvailabilityConflict>>([
        records,
        employees,
      ]);
      if (failure != null) return failure;

      final range = ref.watch(dashboardLiveRangeProvider);
      // Grouped by assignee in ONE pass. This used to rebuild a filtered copy
      // of the whole merged list per employee — O(employees × records) `contains`
      // checks plus a fresh list each, on every live snapshot.
      final byEmployee = <String, List<AppointmentRecord>>{};
      for (final a in records.requireValue) {
        for (final id in a.employeeIds) {
          (byEmployee[id] ??= <AppointmentRecord>[]).add(a);
        }
      }
      return AsyncValue.data([
        for (final employee in employees.requireValue)
          if (daysBookedOutsideAvailability(
                appointments: byEmployee[employee.id] ?? const [],
                range: range,
                workingDays: employee.workingDays,
              )
              case final days when days.isNotEmpty)
            (employee: employee, days: days),
      ]);
    });

/// The first error or loading state among [sources], or null when every one of
/// them has settled with data.
///
/// Error before loading, deliberately: a source that has already failed must
/// not be masked by a sibling still in flight, or the screen sits on a
/// skeleton with nothing ever surfacing the failure.
AsyncValue<T>? _firstFailure<T>(List<AsyncValue<Object?>> sources) {
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
  return null;
}

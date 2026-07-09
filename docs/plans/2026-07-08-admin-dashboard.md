# Admin Dashboard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an admin-only Dashboard screen (Today's operations, Employee workload, Business trends, Attention flags) reachable from the settings end-drawer and the Settings screen, fed by ONE Firestore appointments range stream plus one one-shot clients query.

**Architecture:** Pure Dart aggregation (`DashboardAggregator`, every function takes `now`) over the existing `appointmentsInRangeProvider` with a midnight-aligned 8-week range; employees come from existing providers; new clients from a new one-shot `fetchClientsCreatedSince` repository method. UI is one pushed route (`/dashboard`, no HubShell/AdaptiveShell/endDrawer): a full-bleed hero summary band + four section widgets and a single `fl_chart` wrapper.

**UI treatment (user-selected 2026-07-08 from three mockups):** Option B "hero summary" as the base — big total + segmented status bar + unassigned pill in a primary-gradient hero, workload rows with progress bars, one combined trends card (grouped chart + new-clients sparkline) — with two sections taken from Option C: "Next up today" renders as a **timeline with a time rail**, and "Needs attention" renders as **compact severity-striped alert rows**. Mockup: claude.ai artifact "Admin Dashboard — 3 UI options".

**Tech Stack:** Flutter/Dart 3.10, Riverpod 3 (manual providers), Firestore, freezed (client model), `fl_chart ^1.2.0` (new dep), `gen_l10n` EN/FR.

**Source spec:** `C:\Users\GeorgeVogas\.claude\plans\harmonic-kindling-anchor.md`

**Deviations from spec (flagged, not silent):**
1. The spec lists `DashboardArgs{isAdmin, employeeId}` for the route. The screen uses neither field (no shell, no drawer, both entry points are already inside admin-only blocks), so the route takes **no arguments** — modeled on the `login` case instead of `forgotPassword`. Adding an unused args class violates the repo's no-dead-code rule. If per-user behavior is ever added, introduce the args class then.
2. Chart animation uses `AppDuration.normal` (250 ms) — the spec said "AppDuration token" without naming one; `AppDuration` only has `fast`/`normal`/`shimmer`.
3. The spec's "stat tiles" became the hero's segmented status bar + legend (user chose this in mockup review). Same counts, same `displayStatus` semantics — only the presentation changed.
4. The hero's in-progress segment hue is a widget-local `Color` constant (`0xFF00A6F4`). Justification: the hero ground is `scheme.primary` in BOTH themes (see `appBarTheme` in `themes.dart`), so this on-primary data hue is deliberately theme-invariant; `ColorScheme` has no role for "data color on primary", and the frontend rules' `ThemeExtension` mechanism is for values that *differ* per theme. The legend text carries the meaning, so color is never the sole indicator.

**Accepted limitations (from spec — document in code, do not "fix"):**
- Overdue flags look back only 8 weeks (the range start).
- "Today" is computed at provider build; autoDispose refreshes it on reopen, not across midnight while the screen stays open.
- Legacy client docs without `createdAt` are excluded from the new-clients count (accepted undercount).
- Trends are job-volume, not revenue (no money data exists client-side).

---

## File map

New files:

```
lib/features/dashboard/
  domain/dashboard_stats.dart          # plain immutable value classes (no freezed — never serialized)
  domain/dashboard_aggregator.dart     # pure static fns, all take `now`
  application/dashboard_providers.dart # clock, range, newClientDates, dashboardStats
  screens/dashboard_screen.dart        # Scaffold + AppTopBar, full-bleed ListView: hero + 4 sections
  widgets/charts/weekly_bar_chart.dart # the ONE fl_chart wrapper (1–2 series)
  widgets/sections/dashboard_hero.dart            # primary-gradient band: big total, date,
                                                  # segmented status bar + legend, unassigned pill
  widgets/sections/upcoming_today_section.dart    # timeline with time rail (≤5 upcoming visits)
  widgets/sections/employee_workload_section.dart # avatar + name + week progress bar + counts
  widgets/sections/business_trends_section.dart   # ONE card: grouped chart + new-clients sparkline;
                                                  # busiest-weekday text row
  widgets/sections/attention_flags_section.dart   # severity-striped alert rows or all-clear

test/features/dashboard/domain/dashboard_aggregator_test.dart
test/features/dashboard/screens/dashboard_screen_test.dart
```

Modified files:

```
pubspec.yaml                                              # + fl_chart: ^1.2.0
lib/features/clients/domain/models/client_record.dart     # + DateTime? createdAt (fromMap only; toMap UNCHANGED)
lib/features/clients/domain/clients_repository.dart       # + fetchClientsCreatedSince
lib/features/clients/data/firebase_clients_repository.dart# + implementation
lib/routes/app_routes.dart                                # + '/dashboard' route (plain AppPageRoute, NOT _hubRoute)
lib/features/settings/widgets/views/settings_drawer.dart  # + admin _NavItem (portrait entry)
lib/features/settings/screens/settings_screen.dart        # + Management/Dashboard SettingsTile (split-layout entry)
lib/l10n/app_en.arb + lib/l10n/app_fr.arb                 # + dashboard_ bucket, settings_management, error_introLoadDashboard
test/features/clients/client_record_test.dart             # + createdAt parse test
```

Do NOT touch: `AdaptiveDestination`, `destinationRoute`, `HubShell`, the nav rail, `ClientRecord.toMap` (must never emit `createdAt` or wave fields).

Counting semantics (single source of truth for tasks below):
- **The hero's total / segments / legend** count by a pure re-implementation of `displayStatus` with `now` as a parameter (the model getter calls `DateTime.now()` — untestable), normalized through `AppointmentStatus.fromRaw` so `'completed'` counts as done and unknown raws count as pending. Keeps the hero consistent with the `StatusChip`s in the timeline below it.
- **Attention flags** use RAW `status`: `pendingSoon` = raw `pending` && `now < startTime ≤ now+48h`; `overdueOpen` = `endTime < now` && raw status not done/completed/cancelled.
- **Unassigned** = starts today, empty `employeeIds`, not cancelled. **Workload** excludes cancelled; a multi-assignee visit counts once per assignee.

---

### Task 1: Add fl_chart dependency

**Files:**
- Modify: `pubspec.yaml`

- [ ] **Step 1: Add the dependency**

In `pubspec.yaml`, under the `# UI` group (after `font_awesome_flutter: ^11.0.0`), add:

```yaml
  fl_chart: ^1.2.0
```

- [ ] **Step 2: Fetch packages**

Run: `flutter pub get`
Expected: `Got dependencies!` (exit 0).
NOTE (this machine): `flutter pub get` after a dependency change fails under the command sandbox (plugin-symlink error) — run it with sandbox disabled.

- [ ] **Step 3: Commit**

```bash
git add pubspec.yaml pubspec.lock
git commit -m "feat(dashboard): add fl_chart dependency"
```

---

### Task 2: Domain — stats value classes + aggregator (TDD)

**Files:**
- Create: `lib/features/dashboard/domain/dashboard_stats.dart`
- Create: `lib/features/dashboard/domain/dashboard_aggregator.dart`
- Test: `test/features/dashboard/domain/dashboard_aggregator_test.dart`

Date facts used throughout (fixed clock = Wednesday 2026-07-08 12:00): `mondayOf` → 2026-07-06; range start = 2026-05-18 (Mon, 7 weeks earlier); next Monday = 2026-07-13; startOfToday+3d = 2026-07-11; the 8 week starts oldest-first are May 18, May 25, Jun 1, Jun 8, Jun 15, Jun 22, Jun 29, Jul 6.

- [ ] **Step 1: Write the failing tests**

Create `test/features/dashboard/domain/dashboard_aggregator_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/dashboard/domain/dashboard_aggregator.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';

/// Fixed clock: Wednesday 2026-07-08, noon.
final _now = DateTime(2026, 7, 8, 12);

const _e1 = EmployeeRecord(id: 'e1', name: 'Jane', status: 'active');
const _e2 = EmployeeRecord(id: 'e2', name: 'Marc', status: 'active');

AppointmentRecord _appt({
  required String id,
  required DateTime start,
  Duration duration = const Duration(hours: 1),
  String status = 'pending',
  List<String> employeeIds = const ['e1'],
}) => AppointmentRecord(
  id: id,
  title: 'Job $id',
  startTime: start,
  endTime: start.add(duration),
  status: status,
  employeeIds: employeeIds,
);

void main() {
  group('mondayOf', () {
    test('returns Monday midnight for a mid-week day', () {
      expect(
        DashboardAggregator.mondayOf(DateTime(2026, 7, 8, 15, 30)),
        DateTime(2026, 7, 6),
      );
    });

    test('is idempotent on a Monday', () {
      expect(
        DashboardAggregator.mondayOf(DateTime(2026, 7, 6)),
        DateTime(2026, 7, 6),
      );
    });

    test('a late Sunday still belongs to the week that started 6 days ago',
        () {
      expect(
        DashboardAggregator.mondayOf(DateTime(2026, 7, 12, 23, 59)),
        DateTime(2026, 7, 6),
      );
    });
  });

  group('rangeAround', () {
    test('mid-week: 8 Monday-aligned weeks back through next Monday', () {
      final range = DashboardAggregator.rangeAround(_now);
      expect(range.start, DateTime(2026, 5, 18));
      expect(range.end, DateTime(2026, 7, 13));
    });

    test('Sunday: the +3d arm extends past next Monday to cover 48h flags',
        () {
      final range = DashboardAggregator.rangeAround(DateTime(2026, 7, 12, 20));
      expect(range.start, DateTime(2026, 5, 18));
      expect(range.end, DateTime(2026, 7, 15));
    });

    test('midnight edge: exactly 00:00 counts as that day', () {
      final range = DashboardAggregator.rangeAround(DateTime(2026, 7, 8));
      expect(range.start, DateTime(2026, 5, 18));
      expect(range.end, DateTime(2026, 7, 13));
    });
  });

  group('displayStatusAt', () {
    test('non-terminal past start becomes in_progress', () {
      final a = _appt(id: 'a', start: DateTime(2026, 7, 8, 9));
      expect(DashboardAggregator.displayStatusAt(a, _now), 'in_progress');
    });

    test('terminal statuses pass through even when started', () {
      final done =
          _appt(id: 'a', start: DateTime(2026, 7, 8, 9), status: 'done');
      final cancelled =
          _appt(id: 'b', start: DateTime(2026, 7, 8, 9), status: 'cancelled');
      expect(DashboardAggregator.displayStatusAt(done, _now), 'done');
      expect(DashboardAggregator.displayStatusAt(cancelled, _now), 'cancelled');
    });

    test('future visit keeps its raw status (not promoted to in_progress)', () {
      final a = _appt(
        id: 'a',
        start: DateTime(2026, 7, 8, 14),
        status: 'pending',
      );
      expect(DashboardAggregator.displayStatusAt(a, _now), 'pending');
    });
  });

  group('computeTodayOps', () {
    test('counts today by normalized display status', () {
      final ops = DashboardAggregator.computeTodayOps([
        _appt(id: 'started', start: DateTime(2026, 7, 8, 9)), // -> in_progress
        _appt(
          id: 'later',
          start: DateTime(2026, 7, 8, 14),
          status: 'pending',
        ),
        // Legacy raw 'completed' normalizes to done.
        _appt(
          id: 'legacy',
          start: DateTime(2026, 7, 8, 8),
          status: 'completed',
        ),
        _appt(id: 'notToday', start: DateTime(2026, 7, 7, 9)),
      ], _now);
      expect(ops.statusCounts, {
        'in_progress': 1,
        'pending': 1,
        'done': 1,
      });
    });

    test('unassigned counts empty employeeIds today, excluding cancelled',
        () {
      final ops = DashboardAggregator.computeTodayOps([
        _appt(
          id: 'open',
          start: DateTime(2026, 7, 8, 15),
          employeeIds: const [],
        ),
        _appt(
          id: 'cancelledOpen',
          start: DateTime(2026, 7, 8, 16),
          status: 'cancelled',
          employeeIds: const [],
        ),
      ], _now);
      expect(ops.unassignedCount, 1);
    });

    test('upcoming is future, non-terminal, sorted, capped at 5', () {
      final appointments = [
        for (var h = 20; h >= 13; h--) // 8 future visits, reverse order
          _appt(id: 'h$h', start: DateTime(2026, 7, 8, h)),
        _appt(id: 'started', start: DateTime(2026, 7, 8, 9)),
        _appt(
          id: 'cancelled',
          start: DateTime(2026, 7, 8, 14, 30),
          status: 'cancelled',
        ),
      ];
      final ops = DashboardAggregator.computeTodayOps(appointments, _now);
      expect(ops.upcoming, hasLength(5));
      expect(ops.upcoming.first.id, 'h13');
      expect(ops.upcoming.last.id, 'h17');
    });
  });

  group('computeWorkload', () {
    test('per-assignee today/week counts, cancelled excluded', () {
      final workload = DashboardAggregator.computeWorkload(
        [
          // Monday of this week, e1 only.
          _appt(id: 'mon', start: DateTime(2026, 7, 6, 9)),
          // Today, both assignees — counts once per assignee.
          _appt(
            id: 'both',
            start: DateTime(2026, 7, 8, 14),
            employeeIds: const ['e1', 'e2'],
          ),
          // Cancelled today — excluded everywhere.
          _appt(
            id: 'cxl',
            start: DateTime(2026, 7, 8, 15),
            status: 'cancelled',
          ),
          // Next Monday — outside this week.
          _appt(id: 'next', start: DateTime(2026, 7, 13, 9)),
        ],
        const [_e1, _e2],
        _now,
      );
      expect(workload, hasLength(2));
      expect(workload[0].employee.id, 'e1');
      expect(workload[0].todayCount, 1);
      expect(workload[0].weekCount, 2);
      expect(workload[1].employee.id, 'e2');
      expect(workload[1].todayCount, 1);
      expect(workload[1].weekCount, 1);
    });

    test('Monday 00:00 exactly belongs to this week', () {
      final workload = DashboardAggregator.computeWorkload(
        [_appt(id: 'edge', start: DateTime(2026, 7, 6))],
        const [_e1],
        _now,
      );
      expect(workload.single.weekCount, 1);
    });
  });

  group('computeWeekBuckets', () {
    test('8 buckets; boundaries land in the newer week; legacy completed '
        'counts as completed', () {
      final buckets = DashboardAggregator.computeWeekBuckets(
        [
          // Exactly the range start -> bucket 0.
          _appt(id: 'first', start: DateTime(2026, 5, 18), status: 'done'),
          // One second before the range start -> dropped.
          _appt(
            id: 'before',
            start: DateTime(2026, 5, 17, 23, 59, 59),
            status: 'done',
          ),
          // Legacy raw.
          _appt(
            id: 'legacy',
            start: DateTime(2026, 5, 20),
            status: 'completed',
          ),
          // Current week.
          _appt(id: 'thisWk', start: DateTime(2026, 7, 7), status: 'done'),
          _appt(
            id: 'cxl',
            start: DateTime(2026, 7, 7, 10),
            status: 'cancelled',
          ),
        ],
        [
          DateTime(2026, 5, 19), // bucket 0
          DateTime(2026, 7, 8, 11), // bucket 7
        ],
        _now,
      );
      expect(buckets, hasLength(8));
      expect(buckets.first.weekStart, DateTime(2026, 5, 18));
      expect(buckets.last.weekStart, DateTime(2026, 7, 6));
      expect(buckets[0].completed, 2); // 'first' + 'legacy'
      expect(buckets[0].newClients, 1);
      expect(buckets[7].completed, 1);
      expect(buckets[7].cancelled, 1);
      expect(buckets[7].newClients, 1);
      final total =
          buckets.fold(0, (sum, b) => sum + b.completed + b.cancelled);
      expect(total, 4); // 'before' was dropped
    });
  });

  group('computeBusiestWeekday', () {
    test('tie resolves to the earliest weekday; cancelled excluded', () {
      final busiest = DashboardAggregator.computeBusiestWeekday([
        _appt(id: 'f1', start: DateTime(2026, 6, 5, 9)), // Friday
        _appt(id: 'f2', start: DateTime(2026, 6, 12, 9)), // Friday
        _appt(id: 'm1', start: DateTime(2026, 6, 1, 9)), // Monday
        _appt(id: 'm2', start: DateTime(2026, 6, 8, 9)), // Monday
        _appt(
          id: 'fCxl',
          start: DateTime(2026, 6, 19, 9), // Friday, cancelled
          status: 'cancelled',
        ),
      ], _now);
      expect(busiest, isNotNull);
      expect(busiest!.weekday, DateTime.monday);
      expect(busiest.count, 2);
    });

    test('returns null with nothing to count', () {
      expect(DashboardAggregator.computeBusiestWeekday(const [], _now), isNull);
    });
  });

  group('computeAttentionFlags', () {
    test('pendingSoon: raw pending inside (now, now+48h]', () {
      final flags = DashboardAggregator.computeAttentionFlags([
        _appt(id: 'in47', start: _now.add(const Duration(hours: 47))),
        _appt(id: 'out49', start: _now.add(const Duration(hours: 49))),
        // Already started pending is NOT "starting soon".
        _appt(id: 'started', start: _now.subtract(const Duration(hours: 1))),
        // Raw status must be pending — a done visit starting soon is excluded.
        _appt(
          id: 'doneSoon',
          start: _now.add(const Duration(hours: 5)),
          status: 'done',
        ),
      ], _now);
      expect(flags.pendingSoon.map((a) => a.id), ['in47']);
    });

    test('overdueOpen: ended, raw status non-terminal', () {
      final flags = DashboardAggregator.computeAttentionFlags([
        _appt(
          id: 'overdue',
          start: DateTime(2026, 7, 7, 9),
          status: 'in_progress',
        ),
        _appt(id: 'closed', start: DateTime(2026, 7, 7, 10), status: 'done'),
        _appt(
          id: 'cxl',
          start: DateTime(2026, 7, 7, 11),
          status: 'cancelled',
        ),
        // Started but not ended yet — not overdue.
        _appt(
          id: 'running',
          start: _now.subtract(const Duration(minutes: 30)),
        ),
      ], _now);
      expect(flags.overdueOpen.map((a) => a.id), ['overdue']);
      expect(flags.isAllClear, isFalse);
    });

    test('isAllClear when both lists are empty', () {
      final flags = DashboardAggregator.computeAttentionFlags(const [], _now);
      expect(flags.isAllClear, isTrue);
    });
  });
}
```

- [ ] **Step 2: Run it to make sure it fails**

Run: `flutter test test/features/dashboard/domain/dashboard_aggregator_test.dart`
Expected: FAIL — `Error: Couldn't resolve the package 'scheduling/features/dashboard/...'` (files don't exist yet).

- [ ] **Step 3: Create the stats value classes**

Create `lib/features/dashboard/domain/dashboard_stats.dart`:

```dart
import 'package:flutter/foundation.dart' show immutable;

import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';

/// Today's status counts, unassigned jobs, and the next upcoming visits.
@immutable
class TodayOps {
  const TodayOps({
    required this.statusCounts,
    required this.unassignedCount,
    required this.upcoming,
  });

  /// Keyed by normalized display-status raw value
  /// ('pending', 'in_progress', 'done', 'cancelled').
  final Map<String, int> statusCounts;
  final int unassignedCount;
  final List<AppointmentRecord> upcoming;

  /// Every visit today regardless of status — the hero's big number.
  int get total => statusCounts.values.fold(0, (sum, n) => sum + n);
}

@immutable
class EmployeeWorkload {
  const EmployeeWorkload({
    required this.employee,
    required this.todayCount,
    required this.weekCount,
  });

  final EmployeeRecord employee;
  final int todayCount;
  final int weekCount;
}

@immutable
class WeekBucket {
  const WeekBucket({
    required this.weekStart,
    required this.completed,
    required this.cancelled,
    required this.newClients,
  });

  final DateTime weekStart;
  final int completed;
  final int cancelled;
  final int newClients;
}

@immutable
class BusiestWeekday {
  const BusiestWeekday({required this.weekday, required this.count});

  /// DateTime.monday (1) .. DateTime.sunday (7).
  final int weekday;
  final int count;
}

@immutable
class AttentionFlags {
  const AttentionFlags({
    required this.pendingSoon,
    required this.overdueOpen,
  });

  final List<AppointmentRecord> pendingSoon;
  final List<AppointmentRecord> overdueOpen;

  bool get isAllClear => pendingSoon.isEmpty && overdueOpen.isEmpty;
}

@immutable
class DashboardStats {
  const DashboardStats({
    required this.todayOps,
    required this.workload,
    required this.weekBuckets,
    required this.busiestWeekday,
    required this.flags,
  });

  final TodayOps todayOps;
  final List<EmployeeWorkload> workload;
  final List<WeekBucket> weekBuckets;
  final BusiestWeekday? busiestWeekday;
  final AttentionFlags flags;
}
```

- [ ] **Step 4: Create the aggregator**

Create `lib/features/dashboard/domain/dashboard_aggregator.dart`. All date arithmetic goes through the `DateTime(y, m, d ± n)` constructor (which normalizes) — never `add/subtract(Duration(days: n))` on a midnight, which drifts an hour across DST:

```dart
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/dashboard/domain/dashboard_stats.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';
import 'package:scheduling/shared/widgets/feedback/status_chip.dart';

/// Pure reducers over the one dashboard appointments range. Every function
/// takes `now` explicitly so the whole feature tests with a fixed clock.
///
/// Accepted limitations (see docs/plans/2026-07-08-admin-dashboard.md):
/// overdue flags look back only as far as the 8-week range start, and "today"
/// is fixed at provider build (autoDispose refreshes on reopen, not across
/// midnight while the screen stays open).
class DashboardAggregator {
  DashboardAggregator._();

  static const int weekCount = 8;
  static const Duration pendingSoonWindow = Duration(hours: 48);
  static const int upcomingLimit = 5;

  /// Midnight on the Monday of [day]'s week (ISO week start).
  static DateTime mondayOf(DateTime day) =>
      DateTime(day.year, day.month, day.day - (day.weekday - DateTime.monday));

  /// The single midnight-aligned query range every section reduces off:
  /// 8 ISO weeks back through at least next Monday; the `+3 days` arm keeps
  /// the 48 h pending window covered when `now` is a Sunday.
  static AppointmentDateRange rangeAround(DateTime now) {
    final monday = mondayOf(now);
    final start =
        DateTime(monday.year, monday.month, monday.day - 7 * (weekCount - 1));
    final nextMonday = DateTime(monday.year, monday.month, monday.day + 7);
    final pendingHorizon = DateTime(now.year, now.month, now.day + 3);
    return AppointmentDateRange(
      start: start,
      end: nextMonday.isAfter(pendingHorizon) ? nextMonday : pendingHorizon,
    );
  }

  /// Pure re-implementation of [AppointmentRecord.displayStatus] (the model
  /// getter reads DateTime.now() and is untestable): terminal statuses pass
  /// through; a non-terminal visit whose start has passed is in_progress.
  static String displayStatusAt(AppointmentRecord appointment, DateTime now) {
    if (_isTerminal(appointment)) return appointment.status;
    if (now.isAfter(appointment.startTime)) return 'in_progress';
    return appointment.status;
  }

  static TodayOps computeTodayOps(
    List<AppointmentRecord> appointments,
    DateTime now,
  ) {
    final dayStart = DateTime(now.year, now.month, now.day);
    final counts = <String, int>{};
    var unassigned = 0;
    final upcoming = <AppointmentRecord>[];
    for (final a in appointments) {
      if (!_startsOnDay(a, dayStart)) continue;
      final display = AppointmentStatus.fromRaw(displayStatusAt(a, now)).raw;
      counts[display] = (counts[display] ?? 0) + 1;
      if (a.employeeIds.isEmpty && !_isCancelled(a)) unassigned++;
      if (a.startTime.isAfter(now) && !_isTerminal(a)) upcoming.add(a);
    }
    upcoming.sort((x, y) => x.startTime.compareTo(y.startTime));
    return TodayOps(
      statusCounts: counts,
      unassignedCount: unassigned,
      upcoming: upcoming.take(upcomingLimit).toList(),
    );
  }

  /// Jobs per employee today / this ISO week, cancelled excluded; a
  /// multi-assignee visit counts once per assignee. [employees] is the
  /// active-only list from `employeesStreamProvider`.
  static List<EmployeeWorkload> computeWorkload(
    List<AppointmentRecord> appointments,
    List<EmployeeRecord> employees,
    DateTime now,
  ) {
    final dayStart = DateTime(now.year, now.month, now.day);
    final weekStart = mondayOf(now);
    final weekEnd =
        DateTime(weekStart.year, weekStart.month, weekStart.day + 7);
    final today = <String, int>{};
    final week = <String, int>{};
    for (final a in appointments) {
      if (_isCancelled(a)) continue;
      if (a.startTime.isBefore(weekStart) || !a.startTime.isBefore(weekEnd)) {
        continue;
      }
      final inDay = _startsOnDay(a, dayStart);
      for (final id in a.employeeIds) {
        week[id] = (week[id] ?? 0) + 1;
        if (inDay) today[id] = (today[id] ?? 0) + 1;
      }
    }
    return [
      for (final e in employees)
        EmployeeWorkload(
          employee: e,
          todayCount: today[e.id] ?? 0,
          weekCount: week[e.id] ?? 0,
        ),
    ];
  }

  /// The 8 Monday-midnight week starts, oldest first, ending with the
  /// current week.
  static List<DateTime> weekStartsFor(DateTime now) {
    final monday = mondayOf(now);
    return [
      for (var i = weekCount - 1; i >= 0; i--)
        DateTime(monday.year, monday.month, monday.day - 7 * i),
    ];
  }

  static List<WeekBucket> computeWeekBuckets(
    List<AppointmentRecord> appointments,
    List<DateTime> clientCreatedDates,
    DateTime now,
  ) {
    final weekStarts = weekStartsFor(now);
    final horizon = _weekAfter(weekStarts.last);
    final completed = List<int>.filled(weekCount, 0);
    final cancelled = List<int>.filled(weekCount, 0);
    final newClients = List<int>.filled(weekCount, 0);
    for (final a in appointments) {
      final i = _bucketIndex(weekStarts, horizon, a.startTime);
      if (i < 0) continue;
      final s = a.status.toLowerCase();
      if (s == 'done' || s == 'completed') completed[i]++;
      if (s == 'cancelled') cancelled[i]++;
    }
    for (final date in clientCreatedDates) {
      final i = _bucketIndex(weekStarts, horizon, date);
      if (i >= 0) newClients[i]++;
    }
    return [
      for (var i = 0; i < weekCount; i++)
        WeekBucket(
          weekStart: weekStarts[i],
          completed: completed[i],
          cancelled: cancelled[i],
          newClients: newClients[i],
        ),
    ];
  }

  /// Busiest weekday over the whole window, cancelled excluded; ties resolve
  /// to the earliest weekday (Monday first). Null when nothing counts.
  static BusiestWeekday? computeBusiestWeekday(
    List<AppointmentRecord> appointments,
    DateTime now,
  ) {
    final weekStarts = weekStartsFor(now);
    final horizon = _weekAfter(weekStarts.last);
    final counts = List<int>.filled(DateTime.daysPerWeek + 1, 0);
    for (final a in appointments) {
      if (_isCancelled(a)) continue;
      if (_bucketIndex(weekStarts, horizon, a.startTime) < 0) continue;
      counts[a.startTime.weekday]++;
    }
    var bestDay = 0;
    var bestCount = 0;
    for (var day = DateTime.monday; day <= DateTime.sunday; day++) {
      if (counts[day] > bestCount) {
        bestDay = day;
        bestCount = counts[day];
      }
    }
    if (bestCount == 0) return null;
    return BusiestWeekday(weekday: bestDay, count: bestCount);
  }

  static AttentionFlags computeAttentionFlags(
    List<AppointmentRecord> appointments,
    DateTime now,
  ) {
    final soonCutoff = now.add(pendingSoonWindow);
    final pendingSoon = <AppointmentRecord>[];
    final overdueOpen = <AppointmentRecord>[];
    for (final a in appointments) {
      if (a.status.toLowerCase() == 'pending' &&
          a.startTime.isAfter(now) &&
          !a.startTime.isAfter(soonCutoff)) {
        pendingSoon.add(a);
      }
      if (a.endTime.isBefore(now) && !_isTerminal(a)) {
        overdueOpen.add(a);
      }
    }
    pendingSoon.sort((x, y) => x.startTime.compareTo(y.startTime));
    overdueOpen.sort((x, y) => x.startTime.compareTo(y.startTime));
    return AttentionFlags(pendingSoon: pendingSoon, overdueOpen: overdueOpen);
  }

  static DashboardStats computeStats({
    required List<AppointmentRecord> appointments,
    required List<EmployeeRecord> employees,
    required List<DateTime> clientCreatedDates,
    required DateTime now,
  }) => DashboardStats(
    todayOps: computeTodayOps(appointments, now),
    workload: computeWorkload(appointments, employees, now),
    weekBuckets: computeWeekBuckets(appointments, clientCreatedDates, now),
    busiestWeekday: computeBusiestWeekday(appointments, now),
    flags: computeAttentionFlags(appointments, now),
  );

  static bool _isCancelled(AppointmentRecord a) =>
      a.status.toLowerCase() == 'cancelled';

  static bool _isTerminal(AppointmentRecord a) {
    final s = a.status.toLowerCase();
    return s == 'done' || s == 'completed' || s == 'cancelled';
  }

  static bool _startsOnDay(AppointmentRecord a, DateTime dayStart) {
    final dayEnd = DateTime(dayStart.year, dayStart.month, dayStart.day + 1);
    return !a.startTime.isBefore(dayStart) && a.startTime.isBefore(dayEnd);
  }

  static DateTime _weekAfter(DateTime weekStart) =>
      DateTime(weekStart.year, weekStart.month, weekStart.day + 7);

  /// Index of the week bucket containing [t], or -1 outside the window.
  static int _bucketIndex(
    List<DateTime> weekStarts,
    DateTime horizon,
    DateTime t,
  ) {
    if (!t.isBefore(horizon)) return -1;
    for (var i = weekStarts.length - 1; i >= 0; i--) {
      if (!t.isBefore(weekStarts[i])) return i;
    }
    return -1;
  }
}
```

- [ ] **Step 5: Run the tests and make sure they pass**

Run: `flutter test test/features/dashboard/domain/dashboard_aggregator_test.dart`
Expected: `All tests passed!`

- [ ] **Step 6: Commit**

```bash
git add lib/features/dashboard/domain test/features/dashboard
git commit -m "feat(dashboard): pure stats domain and aggregator with unit tests"
```

---

### Task 3: ClientRecord.createdAt + fetchClientsCreatedSince (TDD)

**Files:**
- Modify: `lib/features/clients/domain/models/client_record.dart`
- Modify: `lib/features/clients/domain/clients_repository.dart`
- Modify: `lib/features/clients/data/firebase_clients_repository.dart`
- Test: `test/features/clients/client_record_test.dart` (exists — append)

- [ ] **Step 1: Write the failing test**

Append inside `main()` of `test/features/clients/client_record_test.dart` (match the file's existing group style):

```dart
  group('createdAt', () {
    test('fromMap parses a DateTime createdAt', () {
      final record = ClientRecord.fromMap('c1', {
        'name': 'Alice',
        'createdAt': DateTime(2026, 7, 1, 10, 30),
      });
      expect(record.createdAt, DateTime(2026, 7, 1, 10, 30));
    });

    test('fromMap defaults createdAt to null when absent', () {
      expect(ClientRecord.fromMap('c2', {'name': 'Bob'}).createdAt, isNull);
    });

    test('toMap never emits createdAt (function-owned server timestamp)', () {
      final record = ClientRecord.fromMap('c3', {
        'name': 'Carol',
        'createdAt': DateTime(2026, 7, 1),
      });
      expect(record.toMap().containsKey('createdAt'), isFalse);
    });
  });
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/features/clients/client_record_test.dart`
Expected: FAIL — `The getter 'createdAt' isn't defined for the type 'ClientRecord'`.

- [ ] **Step 3: Add the field to the model**

In `lib/features/clients/domain/models/client_record.dart`:

(a) Add to the `ClientRecord` factory constructor, after `noFixedAddress`:

```dart
    // Server timestamp written by the repository / Wave import; read-only in
    // the app (dashboard new-clients trend). NEVER emitted by toMap.
    DateTime? createdAt,
```

(b) In `ClientRecord.fromMap`, after the `noFixedAddress:` line, add:

```dart
      createdAt: _parseDateTime(data['createdAt']),
```

(c) Add the parser as a static method on `ClientRecord` (same handling as `AppointmentRecord._parseDateTime`), after `displayName`:

```dart
  static DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    final typeName = value.runtimeType.toString();
    if (typeName == 'Timestamp') {
      return (value as dynamic).toDate() as DateTime;
    }
    return null;
  }
```

(d) `toMap()` stays UNCHANGED — it must never emit `createdAt`, `waveCustomerId`, or `wave`.

- [ ] **Step 4: Regenerate freezed**

Run: `dart run build_runner build --delete-conflicting-outputs`
Expected: `Succeeded after ...` with `client_record.freezed.dart` rebuilt.

- [ ] **Step 5: Run the model test to verify it passes**

Run: `flutter test test/features/clients/client_record_test.dart`
Expected: `All tests passed!`

- [ ] **Step 6: Add the repository method**

In `lib/features/clients/domain/clients_repository.dart`, after `fetchClientsPage`, add:

```dart
  /// One-shot fetch of clients created at or after [since] (dashboard
  /// new-clients trend). Legacy docs without `createdAt` are excluded by the
  /// orderBy — an accepted undercount (they're old imports anyway).
  Future<List<ClientRecord>> fetchClientsCreatedSince(DateTime since);
```

In `lib/features/clients/data/firebase_clients_repository.dart`, after `getClientById`, add:

```dart
  @override
  Future<List<ClientRecord>> fetchClientsCreatedSince(DateTime since) async {
    final snapshot = await _clients
        .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(since))
        .orderBy('createdAt')
        .get();
    return snapshot.docs
        .map((doc) => ClientRecord.fromMap(doc.id, doc.data()))
        .toList();
  }
```

(No new composite index: single-field range + orderBy on the same field is automatic. The admin-only clients read rule already covers the query. No unit test — the repo's Firestore query methods aren't unit-tested in this codebase; there is no fake_cloud_firestore. Device verification covers it.)

- [ ] **Step 7: Check nothing else broke**

Run: `flutter test test/features/clients`
Expected: `All tests passed!` (any test that mocks `ClientsRepository` with mocktail tolerates the new abstract method automatically).

- [ ] **Step 8: Commit**

```bash
git add lib/features/clients test/features/clients/client_record_test.dart
git commit -m "feat(clients): createdAt on ClientRecord and fetchClientsCreatedSince"
```

---

### Task 4: Localization keys (EN + FR lockstep)

**Files:**
- Modify: `lib/l10n/app_en.arb`
- Modify: `lib/l10n/app_fr.arb`

- [ ] **Step 1: Add EN keys**

Append to `lib/l10n/app_en.arb` (before the closing `}`, keeping valid JSON — mind the comma on the previous last entry). Every key carries its `@key` block (`required-resource-attributes: true` fails the build otherwise):

```json
  "dashboard_title": "Dashboard",
  "@dashboard_title": {
    "description": "Admin dashboard screen title, drawer nav item, and settings tile label"
  },
  "dashboard_visitsToday": "{count, plural, =1{visit today} other{visits today}}",
  "@dashboard_visitsToday": {
    "description": "Label rendered beside the hero's big count of today's visits; the number itself is a separate Text",
    "placeholders": {
      "count": {
        "type": "int"
      }
    }
  },
  "dashboard_employeeWorkload": "Employee workload",
  "@dashboard_employeeWorkload": {
    "description": "Dashboard section header: jobs per active employee today / this week"
  },
  "dashboard_workloadCounts": "{today} today · {week} this week",
  "@dashboard_workloadCounts": {
    "description": "Trailing counts on a workload row: jobs today and jobs this week",
    "placeholders": {
      "today": {
        "type": "int"
      },
      "week": {
        "type": "int"
      }
    }
  },
  "dashboard_businessTrends": "Business trends",
  "@dashboard_businessTrends": {
    "description": "Dashboard section header: 8-week completed/cancelled chart and new-client sparkline"
  },
  "dashboard_attentionFlags": "Needs attention",
  "@dashboard_attentionFlags": {
    "description": "Dashboard section header: pending-soon and never-closed visit flags"
  },
  "dashboard_unassignedCount": "{count, plural, =1{1 unassigned job today} other{{count} unassigned jobs today}}",
  "@dashboard_unassignedCount": {
    "description": "Warning pill in the hero counting today's visits with no assignee",
    "placeholders": {
      "count": {
        "type": "int"
      }
    }
  },
  "dashboard_unassigned": "Unassigned",
  "@dashboard_unassigned": {
    "description": "Assignee line on a timeline or alert row for a visit with no employees"
  },
  "dashboard_upcomingToday": "Next up today",
  "@dashboard_upcomingToday": {
    "description": "Section header above the timeline of today's upcoming visits"
  },
  "dashboard_noVisitsToday": "No upcoming visits today",
  "@dashboard_noVisitsToday": {
    "description": "Empty state under the next-up header when today has no future visits"
  },
  "dashboard_noActiveEmployees": "No active employees",
  "@dashboard_noActiveEmployees": {
    "description": "Empty state for the workload section when there are no active employees"
  },
  "dashboard_completedVsCancelled": "Completed vs cancelled — last 8 weeks",
  "@dashboard_completedVsCancelled": {
    "description": "Title of the grouped weekly bar chart of done vs cancelled visits"
  },
  "dashboard_newClients": "New clients",
  "@dashboard_newClients": {
    "description": "Caption of the new-clients sparkline inside the trends card"
  },
  "dashboard_newClientsTotal": "{count, plural, =1{1 in the last 8 weeks} other{{count} in the last 8 weeks}}",
  "@dashboard_newClientsTotal": {
    "description": "Total line under the new-clients caption, summing the 8 weekly buckets",
    "placeholders": {
      "count": {
        "type": "int"
      }
    }
  },
  "dashboard_busiestWeekday": "Busiest day: {day}",
  "@dashboard_busiestWeekday": {
    "description": "Text row naming the weekday with the most visits over the 8-week window",
    "placeholders": {
      "day": {
        "type": "String"
      }
    }
  },
  "dashboard_allClear": "All clear — nothing needs attention",
  "@dashboard_allClear": {
    "description": "Shown in the attention section when there are no flags"
  },
  "dashboard_pendingSoonHeader": "{count, plural, =1{1 pending visit starts within 48 hours} other{{count} pending visits start within 48 hours}}",
  "@dashboard_pendingSoonHeader": {
    "description": "Attention flag group header for pending visits starting within 48 hours",
    "placeholders": {
      "count": {
        "type": "int"
      }
    }
  },
  "dashboard_overdueOpenHeader": "{count, plural, =1{1 past visit was never closed} other{{count} past visits were never closed}}",
  "@dashboard_overdueOpenHeader": {
    "description": "Attention flag group header for ended visits never marked done or cancelled",
    "placeholders": {
      "count": {
        "type": "int"
      }
    }
  },
  "settings_management": "Management",
  "@settings_management": {
    "description": "Settings section header for the admin management area (dashboard entry)"
  },
  "error_introLoadDashboard": "Couldn't load the dashboard",
  "@error_introLoadDashboard": {"description": "Error intro for DASH-LOAD"}
```

- [ ] **Step 2: Add FR keys**

Append to `lib/l10n/app_fr.arb` (values only, matching the file's existing style):

```json
  "dashboard_title": "Tableau de bord",
  "dashboard_visitsToday": "{count, plural, =1{visite aujourd'hui} other{visites aujourd'hui}}",
  "dashboard_employeeWorkload": "Charge de travail des employés",
  "dashboard_workloadCounts": "{today} auj. · {week} cette sem.",
  "dashboard_businessTrends": "Tendances de l'activité",
  "dashboard_attentionFlags": "À surveiller",
  "dashboard_unassignedCount": "{count, plural, =1{1 visite non assignée aujourd'hui} other{{count} visites non assignées aujourd'hui}}",
  "dashboard_unassigned": "Non assignée",
  "dashboard_upcomingToday": "À venir aujourd'hui",
  "dashboard_noVisitsToday": "Aucune visite à venir aujourd'hui",
  "dashboard_noActiveEmployees": "Aucun employé actif",
  "dashboard_completedVsCancelled": "Terminées vs annulées — 8 dernières semaines",
  "dashboard_newClients": "Nouveaux clients",
  "dashboard_newClientsTotal": "{count, plural, =1{1 au cours des 8 dernières semaines} other{{count} au cours des 8 dernières semaines}}",
  "dashboard_busiestWeekday": "Journée la plus occupée : {day}",
  "dashboard_allClear": "Tout est en ordre — rien à signaler",
  "dashboard_pendingSoonHeader": "{count, plural, =1{1 visite en attente commence d'ici 48 heures} other{{count} visites en attente commencent d'ici 48 heures}}",
  "dashboard_overdueOpenHeader": "{count, plural, =1{1 visite passée n'a jamais été clôturée} other{{count} visites passées n'ont jamais été clôturées}}",
  "settings_management": "Gestion",
  "error_introLoadDashboard": "Impossible de charger le tableau de bord"
```

- [ ] **Step 3: Regenerate and verify no drift**

Run: `flutter gen-l10n`
Expected: exits 0. Then check `lib/l10n/.gen/untranslated.json` — it must not list any `dashboard_` key, `settings_management`, or `error_introLoadDashboard`.

- [ ] **Step 4: Commit**

```bash
git add lib/l10n/app_en.arb lib/l10n/app_fr.arb
git commit -m "feat(dashboard): EN/FR localization keys"
```

---

### Task 5: Providers

**Files:**
- Create: `lib/features/dashboard/application/dashboard_providers.dart`

(No dedicated provider test — the combination logic is exercised end-to-end by the Task 9 screen tests with all sources overridden; the reduction logic itself is already unit-tested in Task 2.)

- [ ] **Step 1: Create the providers file**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/features/calendar/application/appointments_providers.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/clients/application/clients_providers.dart';
import 'package:scheduling/features/dashboard/domain/dashboard_aggregator.dart';
import 'package:scheduling/features/dashboard/domain/dashboard_stats.dart';
import 'package:scheduling/features/employees/application/employees_providers.dart';

/// Injectable clock so tests pin "now". The derived range is midnight-aligned,
/// so the appointments family key stays stable all day (no listener churn).
final dashboardClockProvider =
    Provider<DateTime Function()>((ref) => DateTime.now);

final dashboardRangeProvider = Provider.autoDispose<AppointmentDateRange>(
  (ref) => DashboardAggregator.rangeAround(ref.watch(dashboardClockProvider)()),
);

/// createdAt of every client created inside the dashboard window (one-shot
/// get; legacy docs without createdAt are excluded — accepted undercount).
final newClientDatesProvider =
    FutureProvider.autoDispose<List<DateTime>>((ref) async {
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
final dashboardStatsProvider =
    Provider.autoDispose<AsyncValue<DashboardStats>>((ref) {
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
    });
```

- [ ] **Step 2: Analyze**

Run: `flutter analyze 2>&1 | grep -E "error -|warning -"`
Expected: no output (info-level lints are pre-existing noise).

- [ ] **Step 3: Commit**

```bash
git add lib/features/dashboard/application
git commit -m "feat(dashboard): stats providers over one appointments range stream"
```

---

### Task 6: WeeklyBarChart (the one fl_chart wrapper)

**Files:**
- Create: `lib/features/dashboard/widgets/charts/weekly_bar_chart.dart`

- [ ] **Step 1: Create the widget**

Grouped (not stacked) bars, no touch, reduce-motion aware, `Semantics` summary, legend only when 2 series (color never the sole indicator — the 1-series chart's meaning is carried by its card title):

```dart
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:scheduling/core/theme/design_tokens.dart';

/// One series of weekly values; the chart draws 1–2 of these as grouped bars.
class WeeklyBarSeries {
  const WeeklyBarSeries({
    required this.values,
    required this.color,
    required this.label,
  });

  final List<int> values;
  final Color color;
  final String label;
}

/// The one fl_chart wrapper on the dashboard: 8 weekly buckets, 1–2 grouped
/// series, no touch interaction, text legend when two series are shown.
class WeeklyBarChart extends StatelessWidget {
  const WeeklyBarChart({
    required this.weekStarts,
    required this.series,
    super.key,
  }) : assert(
         series.length == 1 || series.length == 2,
         'WeeklyBarChart draws 1 or 2 series',
       );

  final List<DateTime> weekStarts;
  final List<WeeklyBarSeries> series;

  static const double _chartHeight = 160;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final axisStyle =
        theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant);
    final monthDay = DateFormat.Md(Localizations.localeOf(context).toString());
    var maxValue = 0;
    for (final s in series) {
      for (final v in s.values) {
        if (v > maxValue) maxValue = v;
      }
    }
    final summary = [
      for (final s in series)
        '${s.label}: ${s.values.fold(0, (sum, v) => sum + v)}',
    ].join(', ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          label: summary,
          child: ExcludeSemantics(
            child: SizedBox(
              height: _chartHeight,
              child: BarChart(
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : AppDuration.normal,
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: (maxValue == 0 ? 1 : maxValue).toDouble(),
                  barTouchData: BarTouchData(enabled: false),
                  gridData: FlGridData(
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (_) =>
                        FlLine(color: scheme.outlineVariant, strokeWidth: 1),
                  ),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(),
                    rightTitles: const AxisTitles(),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 32,
                        getTitlesWidget: (value, meta) => value % 1 == 0
                            ? Text(value.toInt().toString(), style: axisStyle)
                            : const SizedBox.shrink(),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 28,
                        getTitlesWidget: (value, meta) {
                          final index = value.toInt();
                          // Every other week label, or the axis gets crowded.
                          if (index < 0 ||
                              index >= weekStarts.length ||
                              index.isOdd) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding:
                                const EdgeInsets.only(top: AppSpacing.sp4),
                            child: Text(
                              monthDay.format(weekStarts[index]),
                              style: axisStyle,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  barGroups: [
                    for (var i = 0; i < weekStarts.length; i++)
                      BarChartGroupData(
                        x: i,
                        barRods: [
                          for (final s in series)
                            BarChartRodData(
                              toY: (i < s.values.length ? s.values[i] : 0)
                                  .toDouble(),
                              color: s.color,
                              width: series.length == 1 ? 14 : 7,
                              borderRadius: BorderRadius.circular(2),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (series.length == 2) ...[
          const SizedBox(height: AppSpacing.sp8),
          Wrap(
            spacing: AppSpacing.sp16,
            runSpacing: AppSpacing.sp4,
            children: [
              for (final s in series)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: s.color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sp4),
                    Text(s.label, style: theme.textTheme.labelSmall),
                  ],
                ),
            ],
          ),
        ],
      ],
    );
  }
}
```

NOTE for the implementer: this targets the fl_chart 1.x API. If `flutter analyze` flags a renamed member (e.g. `duration` vs older `swapAnimationDuration`), adapt to the resolved version's API — do NOT pin an older fl_chart.

- [ ] **Step 2: Analyze**

Run: `flutter analyze 2>&1 | grep -E "error -|warning -"`
Expected: no output.

- [ ] **Step 3: Commit**

```bash
git add lib/features/dashboard/widgets/charts
git commit -m "feat(dashboard): WeeklyBarChart fl_chart wrapper"
```

---

### Task 7: Section widgets

**Files:**
- Create: `lib/features/dashboard/widgets/sections/dashboard_hero.dart`
- Create: `lib/features/dashboard/widgets/sections/upcoming_today_section.dart`
- Create: `lib/features/dashboard/widgets/sections/employee_workload_section.dart`
- Create: `lib/features/dashboard/widgets/sections/business_trends_section.dart`
- Create: `lib/features/dashboard/widgets/sections/attention_flags_section.dart`

All five are plain `StatelessWidget`s fed data by constructor (the screen resolves providers once). No raw colors — everything through `scheme.*` / `theme.statusColors` / `appCardDecoration`, except the two hero segment constants documented in deviation 4.

- [ ] **Step 1: dashboard_hero.dart**

Full-bleed band under the app bar, gradient matching the settings drawer header. Big total + `visitsToday` label, the date via `DateUtilsHelper.formatDayHeader`, a proportional status bar (`Expanded(flex: count)` segments inside a `ClipRRect`), a legend `Wrap` (all five statuses, zero counts included — stable layout), and the unassigned pill on translucent onPrimary:

```dart
import 'package:flutter/material.dart';

import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/core/utils/date_utils_helper.dart';
import 'package:scheduling/features/dashboard/domain/dashboard_stats.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/feedback/status_chip.dart';

/// Hero summary band: today's total, the date, a proportional status bar
/// with legend, and the unassigned warning pill.
class DashboardHero extends StatelessWidget {
  const DashboardHero({required this.ops, required this.now, super.key});

  final TodayOps ops;
  final DateTime now;

  // On-primary data hue, deliberately theme-invariant: the hero ground is
  // scheme.primary in BOTH themes (appBarTheme), and ColorScheme has no
  // "data color on primary" role. The legend text carries the meaning.
  static const Color _inProgressSegment = Color(0xFF00A6F4);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final statusColors = theme.statusColors;
    final l10n = context.l10n;
    final segments = [
      (AppointmentStatus.inProgress, _inProgressSegment),
      (AppointmentStatus.pending, statusColors.warning),
      (AppointmentStatus.done, statusColors.success),
      (AppointmentStatus.cancelled, scheme.error),
    ];
    final total = ops.total;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sp16,
        AppSpacing.sp4,
        AppSpacing.sp16,
        AppSpacing.sp16,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            scheme.primary,
            Color.alphaBlend(
              Colors.black.withValues(alpha: 0.2),
              scheme.primary,
            ),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(
              text: '$total ',
              style: theme.textTheme.headlineLarge?.copyWith(
                color: scheme.onPrimary,
                fontWeight: FontWeight.w800,
              ),
              children: [
                TextSpan(
                  text: l10n.dashboard_visitsToday(total),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onPrimary.withValues(alpha: 0.85),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Text(
            DateUtilsHelper.formatDayHeader(now),
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onPrimary.withValues(alpha: 0.85),
            ),
          ),
          const SizedBox(height: AppSpacing.sp12),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.rFull),
            child: SizedBox(
              height: 8,
              width: double.infinity,
              child: total == 0
                  ? ColoredBox(
                      color: scheme.onPrimary.withValues(alpha: 0.18),
                    )
                  : Row(
                      children: [
                        for (final (status, color) in segments)
                          if ((ops.statusCounts[status.raw] ?? 0) > 0)
                            Expanded(
                              flex: ops.statusCounts[status.raw]!,
                              child: ColoredBox(color: color),
                            ),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: AppSpacing.sp8),
          Wrap(
            spacing: AppSpacing.sp12,
            runSpacing: AppSpacing.sp4,
            children: [
              for (final (status, color) in segments)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sp4),
                    Text(
                      '${ops.statusCounts[status.raw] ?? 0} '
                      '${statusLabel(l10n, status)}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onPrimary,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          if (ops.unassignedCount > 0) ...[
            const SizedBox(height: AppSpacing.sp12),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sp12,
                vertical: AppSpacing.sp4,
              ),
              decoration: BoxDecoration(
                color: scheme.onPrimary.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(AppRadius.rFull),
                border: Border.all(
                  color: scheme.onPrimary.withValues(alpha: 0.25),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.person_off_rounded,
                    size: 14,
                    color: statusColors.warning,
                  ),
                  const SizedBox(width: AppSpacing.sp8),
                  Flexible(
                    child: Text(
                      l10n.dashboard_unassignedCount(ops.unassignedCount),
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: scheme.onPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: upcoming_today_section.dart** (Option C timeline)

Time column, colored rail dot per first assignee, title + live `StatusChip`, assignee line. `IntrinsicHeight` stretches the rail per row (same precedent as `AppointmentCard` — keep `LayoutBuilder`/`AutoSizeText` out of this subtree):

```dart
import 'package:flutter/material.dart';

import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/core/utils/date_utils_helper.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/dashboard/domain/dashboard_stats.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/feedback/status_chip.dart';
import 'package:scheduling/shared/widgets/primitives/section_label.dart';

/// Today's upcoming visits as a timeline with a time rail.
class UpcomingTodaySection extends StatelessWidget {
  const UpcomingTodaySection({
    required this.ops,
    required this.colorMap,
    required this.nameMap,
    super.key,
  });

  final TodayOps ops;
  final Map<String, Color> colorMap;
  final Map<String, String> nameMap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel(l10n.dashboard_upcomingToday),
        const SizedBox(height: AppSpacing.sp8),
        if (ops.upcoming.isEmpty)
          Text(
            l10n.dashboard_noVisitsToday,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        else
          Container(
            decoration:
                appCardDecoration(theme, color: theme.colorScheme.surface),
            padding: const EdgeInsets.all(AppSpacing.sp16),
            child: Column(
              children: [
                for (var i = 0; i < ops.upcoming.length; i++)
                  _TimelineRow(
                    appointment: ops.upcoming[i],
                    isLast: i == ops.upcoming.length - 1,
                    colorMap: colorMap,
                    nameMap: nameMap,
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.appointment,
    required this.isLast,
    required this.colorMap,
    required this.nameMap,
  });

  final AppointmentRecord appointment;
  final bool isLast;
  final Map<String, Color> colorMap;
  final Map<String, String> nameMap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dotColor = appointment.employeeIds.isNotEmpty
        ? colorMap[appointment.employeeIds.first] ?? scheme.outlineVariant
        : scheme.outlineVariant;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 64,
            child: Text(
              DateUtilsHelper.formatTime(appointment.startTime),
              textAlign: TextAlign.right,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: scheme.onSurface,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sp8),
          Column(
            children: [
              Container(
                width: 10,
                height: 10,
                margin: const EdgeInsets.only(top: 3),
                decoration:
                    BoxDecoration(color: dotColor, shape: BoxShape.circle),
              ),
              if (!isLast)
                Expanded(
                  child: Container(width: 2, color: scheme.outlineVariant),
                ),
            ],
          ),
          const SizedBox(width: AppSpacing.sp12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : AppSpacing.sp12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          appointment.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sp8),
                      StatusChip(
                        status: AppointmentStatus.fromRaw(
                          appointment.displayStatus,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _assigneeNames(appointment) ??
                        context.l10n.dashboard_unassigned,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String? _assigneeNames(AppointmentRecord appointment) {
    final names = [
      for (final id in appointment.employeeIds)
        if (nameMap[id] != null) nameMap[id]!,
    ];
    if (names.isNotEmpty) return names.join(', ');
    // Denormalized fallback for assignees missing from the users stream.
    if (appointment.employeeNames.isNotEmpty) {
      return appointment.employeeNames.join(', ');
    }
    return null;
  }
}
```

- [ ] **Step 3: employee_workload_section.dart** (Option B progress rows)

Avatar + name + a week-share bar in the employee's color (filled relative to the busiest employee), trailing `workloadCounts` text:

```dart
import 'package:flutter/material.dart';

import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/features/dashboard/domain/dashboard_stats.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/primitives/app_avatar.dart';
import 'package:scheduling/shared/widgets/primitives/section_label.dart';

/// Jobs per active employee: avatar, name, week-share bar, counts.
class EmployeeWorkloadSection extends StatelessWidget {
  const EmployeeWorkloadSection({required this.workload, super.key});

  final List<EmployeeWorkload> workload;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = context.l10n;
    var maxWeek = 0;
    for (final row in workload) {
      if (row.weekCount > maxWeek) maxWeek = row.weekCount;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel(l10n.dashboard_employeeWorkload),
        const SizedBox(height: AppSpacing.sp8),
        if (workload.isEmpty)
          Text(
            l10n.dashboard_noActiveEmployees,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: scheme.onSurfaceVariant),
          )
        else
          Container(
            decoration: appCardDecoration(theme, color: scheme.surface),
            padding: const EdgeInsets.all(AppSpacing.sp12),
            child: Column(
              children: [
                for (var i = 0; i < workload.length; i++)
                  Padding(
                    padding: EdgeInsets.only(
                      bottom:
                          i == workload.length - 1 ? 0 : AppSpacing.sp12,
                    ),
                    child: _WorkloadRow(row: workload[i], maxWeek: maxWeek),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _WorkloadRow extends StatelessWidget {
  const _WorkloadRow({required this.row, required this.maxWeek});

  final EmployeeWorkload row;
  final int maxWeek;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fillFraction =
        maxWeek == 0 ? 0.0 : (row.weekCount / maxWeek).clamp(0.0, 1.0);
    return Row(
      children: [
        AppAvatar(
          name: row.employee.name,
          color: row.employee.color,
          size: AvatarSize.sm,
        ),
        const SizedBox(width: AppSpacing.sp12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                row.employee.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: AppSpacing.sp4),
              Container(
                height: 6,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(AppRadius.rFull),
                ),
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: fillFraction,
                  heightFactor: 1,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: row.employee.color,
                      borderRadius: BorderRadius.circular(AppRadius.rFull),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.sp12),
        Text(
          context.l10n.dashboard_workloadCounts(
            row.todayCount,
            row.weekCount,
          ),
          style: theme.textTheme.bodySmall
              ?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}
```

- [ ] **Step 4: business_trends_section.dart** (Option B combined card)

ONE card: title, the grouped `WeeklyBarChart` (still the only fl_chart use), a divider, then the new-clients caption + 8-week total + a custom sparkline (plain `Row` of bars — no second fl_chart). Busiest-weekday text row below the card. The new-clients block stacks vertically so long FR strings never overflow at large text scales:

```dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/features/dashboard/domain/dashboard_stats.dart';
import 'package:scheduling/features/dashboard/widgets/charts/weekly_bar_chart.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/feedback/status_chip.dart';
import 'package:scheduling/shared/widgets/primitives/section_label.dart';

/// One trends card: grouped done/cancelled chart, the new-clients sparkline
/// with its 8-week total — then the busiest-weekday text row.
class BusinessTrendsSection extends StatelessWidget {
  const BusinessTrendsSection({
    required this.buckets,
    required this.busiestWeekday,
    super.key,
  });

  final List<WeekBucket> buckets;
  final BusiestWeekday? busiestWeekday;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final statusColors = theme.statusColors;
    final l10n = context.l10n;
    final newClientValues = [for (final b in buckets) b.newClients];
    final newClientTotal = newClientValues.fold(0, (sum, v) => sum + v);
    final busiest = busiestWeekday;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel(l10n.dashboard_businessTrends),
        const SizedBox(height: AppSpacing.sp8),
        Container(
          decoration: appCardDecoration(theme, color: scheme.surface),
          padding: const EdgeInsets.all(AppSpacing.sp16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.dashboard_completedVsCancelled,
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: AppSpacing.sp12),
              WeeklyBarChart(
                weekStarts: [for (final b in buckets) b.weekStart],
                series: [
                  WeeklyBarSeries(
                    values: [for (final b in buckets) b.completed],
                    color: statusColors.success,
                    label: statusLabel(l10n, AppointmentStatus.done),
                  ),
                  WeeklyBarSeries(
                    values: [for (final b in buckets) b.cancelled],
                    color: scheme.error,
                    label: statusLabel(l10n, AppointmentStatus.cancelled),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sp12),
              Divider(height: 1, color: scheme.outlineVariant),
              const SizedBox(height: AppSpacing.sp12),
              Text(
                l10n.dashboard_newClients,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
              Text(
                l10n.dashboard_newClientsTotal(newClientTotal),
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: AppSpacing.sp8),
              Semantics(
                label:
                    '${l10n.dashboard_newClients}: '
                    '${l10n.dashboard_newClientsTotal(newClientTotal)}',
                child: ExcludeSemantics(
                  child: _SparklineBars(
                    values: newClientValues,
                    color: scheme.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (busiest != null) ...[
          const SizedBox(height: AppSpacing.sp16),
          Row(
            children: [
              Icon(Icons.event_rounded, size: 18, color: scheme.primary),
              const SizedBox(width: AppSpacing.sp8),
              Expanded(
                child: Text(
                  l10n.dashboard_busiestWeekday(
                    _weekdayName(context, busiest.weekday),
                  ),
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  /// Localized full weekday name. 2024-01-01 is a Monday, so day N of that
  /// month falls on ISO weekday N.
  String _weekdayName(BuildContext context, int weekday) {
    final locale = Localizations.localeOf(context).toString();
    return DateFormat('EEEE', locale).format(DateTime(2024, 1, weekday));
  }
}

class _SparklineBars extends StatelessWidget {
  const _SparklineBars({required this.values, required this.color});

  final List<int> values;
  final Color color;

  static const double _height = 36;

  @override
  Widget build(BuildContext context) {
    var maxValue = 0;
    for (final v in values) {
      if (v > maxValue) maxValue = v;
    }
    return SizedBox(
      height: _height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final v in values)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1.5),
                child: SizedBox(
                  height: maxValue == 0 ? 0 : _height * v / maxValue,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(2),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 5: attention_flags_section.dart** (Option C severity-striped alert rows)

Compact rows instead of full appointment cards: a 3 px severity stripe (warning amber for pending-soon, error red for never-closed), title + live `StatusChip`, and one detail line "date · time · assignee". No `colorMap` needed — the stripe encodes severity, not employee:

```dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/core/utils/date_utils_helper.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/dashboard/domain/dashboard_stats.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/feedback/status_chip.dart';
import 'package:scheduling/shared/widgets/primitives/section_label.dart';

/// Pending-soon and never-closed visits as compact severity-striped rows.
class AttentionFlagsSection extends StatelessWidget {
  const AttentionFlagsSection({
    required this.flags,
    required this.nameMap,
    super.key,
  });

  final AttentionFlags flags;
  final Map<String, String> nameMap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColors = theme.statusColors;
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel(l10n.dashboard_attentionFlags),
        const SizedBox(height: AppSpacing.sp8),
        if (flags.isAllClear)
          Row(
            children: [
              Icon(
                Icons.check_circle_rounded,
                size: 18,
                color: statusColors.success,
              ),
              const SizedBox(width: AppSpacing.sp8),
              Expanded(
                child: Text(
                  l10n.dashboard_allClear,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          )
        else ...[
          if (flags.pendingSoon.isNotEmpty)
            _FlagGroup(
              title: l10n.dashboard_pendingSoonHeader(flags.pendingSoon.length),
              appointments: flags.pendingSoon,
              stripeColor: statusColors.warning,
              nameMap: nameMap,
            ),
          if (flags.pendingSoon.isNotEmpty && flags.overdueOpen.isNotEmpty)
            const SizedBox(height: AppSpacing.sp16),
          if (flags.overdueOpen.isNotEmpty)
            _FlagGroup(
              title: l10n.dashboard_overdueOpenHeader(flags.overdueOpen.length),
              appointments: flags.overdueOpen,
              stripeColor: theme.colorScheme.error,
              nameMap: nameMap,
            ),
        ],
      ],
    );
  }
}

class _FlagGroup extends StatelessWidget {
  const _FlagGroup({
    required this.title,
    required this.appointments,
    required this.stripeColor,
    required this.nameMap,
  });

  final String title;
  final List<AppointmentRecord> appointments;
  final Color stripeColor;
  final Map<String, String> nameMap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style:
              theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: AppSpacing.sp8),
        for (final appointment in appointments)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sp8),
            child: _AlertRow(
              appointment: appointment,
              stripeColor: stripeColor,
              nameMap: nameMap,
            ),
          ),
      ],
    );
  }
}

class _AlertRow extends StatelessWidget {
  const _AlertRow({
    required this.appointment,
    required this.stripeColor,
    required this.nameMap,
  });

  final AppointmentRecord appointment;
  final Color stripeColor;
  final Map<String, String> nameMap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // Flagged visits can be days away or days old — the date matters.
    final dateLabel = DateFormat.MMMEd(
      Localizations.localeOf(context).toString(),
    ).format(appointment.startTime);
    final timeLabel = DateUtilsHelper.formatTime(appointment.startTime);
    final who = _assigneeNames(appointment) ?? context.l10n.dashboard_unassigned;
    return Container(
      decoration: appCardDecoration(theme, color: scheme.surface),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 3, color: stripeColor),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.sp12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            appointment.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sp8),
                        StatusChip(
                          status: AppointmentStatus.fromRaw(
                            appointment.displayStatus,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sp4),
                    Text(
                      '$dateLabel · $timeLabel · $who',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String? _assigneeNames(AppointmentRecord appointment) {
    final names = [
      for (final id in appointment.employeeIds)
        if (nameMap[id] != null) nameMap[id]!,
    ];
    if (names.isNotEmpty) return names.join(', ');
    if (appointment.employeeNames.isNotEmpty) {
      return appointment.employeeNames.join(', ');
    }
    return null;
  }
}
```

- [ ] **Step 6: Analyze**

Run: `flutter analyze 2>&1 | grep -E "error -|warning -"`
Expected: no output.

- [ ] **Step 7: Commit**

```bash
git add lib/features/dashboard/widgets/sections
git commit -m "feat(dashboard): hero band and four section widgets"
```

---

### Task 8: Dashboard screen

**Files:**
- Create: `lib/features/dashboard/screens/dashboard_screen.dart`

- [ ] **Step 1: Create the screen**

Plain pushed route — no AdaptiveShell, no endDrawer. `build()` stays under 60 lines by delegating to private body widgets. Error side effects live in `ref.listen` (fires once per data→error transition), never in the `.when`-style render branch:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/errors/error_cause.dart';
import 'package:scheduling/core/layout/breakpoints.dart';
import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/core/notices/notice_service.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/features/dashboard/application/dashboard_providers.dart';
import 'package:scheduling/features/dashboard/domain/dashboard_stats.dart';
import 'package:scheduling/features/dashboard/widgets/sections/attention_flags_section.dart';
import 'package:scheduling/features/dashboard/widgets/sections/business_trends_section.dart';
import 'package:scheduling/features/dashboard/widgets/sections/dashboard_hero.dart';
import 'package:scheduling/features/dashboard/widgets/sections/employee_workload_section.dart';
import 'package:scheduling/features/dashboard/widgets/sections/upcoming_today_section.dart';
import 'package:scheduling/features/employees/application/employees_providers.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/app_bars/app_top_bar.dart';
import 'package:scheduling/shared/widgets/feedback/skeleton_loader.dart';

/// Admin-only at-a-glance view of the business. Reached only from admin
/// surfaces (settings drawer / Settings screen) as a plain pushed route.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(dashboardStatsProvider);
    ref.listen<AsyncValue<DashboardStats>>(dashboardStatsProvider, (
      previous,
      next,
    ) {
      if (!next.hasError || (previous?.hasError ?? false)) return;
      ref
          .read(loggerProvider)
          .warn('DASH-LOAD dashboard failed', next.error, next.stackTrace);
      ref.read(noticeServiceProvider).error(
        composeErrorNotice(
          context,
          intro: context.l10n.error_introLoadDashboard,
          tag: 'DASH-LOAD',
          error: next.error!,
        ),
      );
    });

    return Scaffold(
      appBar: AppTopBar(
        title: context.l10n.dashboard_title,
        compact: context.isLandscape,
        onBack: () => Navigator.pop(context),
      ),
      body: switch (stats) {
        AsyncData(:final value) => _StatsList(stats: value),
        AsyncError() => const _ErrorBody(),
        _ => const _LoadingList(),
      },
    );
  }
}

class _StatsList extends ConsumerWidget {
  const _StatsList({required this.stats});

  final DashboardStats stats;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorMap = ref.watch(employeeColorMapProvider);
    final nameMap = ref.watch(employeeNameMapProvider);
    final now = ref.watch(dashboardClockProvider)();
    // Zero list padding so the hero bleeds edge-to-edge; the sections carry
    // their own sp16 inset.
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        DashboardHero(ops: stats.todayOps, now: now),
        Padding(
          padding: const EdgeInsets.all(AppSpacing.sp16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              UpcomingTodaySection(
                ops: stats.todayOps,
                colorMap: colorMap,
                nameMap: nameMap,
              ),
              const SizedBox(height: AppSpacing.sp24),
              EmployeeWorkloadSection(workload: stats.workload),
              const SizedBox(height: AppSpacing.sp24),
              BusinessTrendsSection(
                buckets: stats.weekBuckets,
                busiestWeekday: stats.busiestWeekday,
              ),
              const SizedBox(height: AppSpacing.sp24),
              AttentionFlagsSection(flags: stats.flags, nameMap: nameMap),
              const SizedBox(height: AppSpacing.sp16),
            ],
          ),
        ),
      ],
    );
  }
}

class _LoadingList extends StatelessWidget {
  const _LoadingList();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.sp16),
      children: [for (var i = 0; i < 8; i++) const SkeletonAppointmentRow()],
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sp24),
        child: Text(
          context.l10n.error_introLoadDashboard,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Analyze**

Run: `flutter analyze 2>&1 | grep -E "error -|warning -"`
Expected: no output.

- [ ] **Step 3: Commit**

```bash
git add lib/features/dashboard/screens
git commit -m "feat(dashboard): dashboard screen"
```

---

### Task 9: Wiring — route + drawer item + settings tile

**Files:**
- Modify: `lib/routes/app_routes.dart`
- Modify: `lib/features/settings/widgets/views/settings_drawer.dart`
- Modify: `lib/features/settings/screens/settings_screen.dart`

- [ ] **Step 1: Route**

In `lib/routes/app_routes.dart`:

(a) Add the import:

```dart
import 'package:scheduling/features/dashboard/screens/dashboard_screen.dart';
```

(b) Add the constant after `settings`:

```dart
  static const String dashboard = '/dashboard';
```

(c) Add the case after the `forgotPassword` case (plain `AppPageRoute` — NOT `_hubRoute`; entry points are admin-only, and the screen carries no per-user state, so no args class):

```dart
      case dashboard:
        return AppPageRoute(
          settings: settings,
          builder: (_) => const DashboardScreen(),
        );
```

- [ ] **Step 2: Drawer item (portrait entry)**

In `lib/features/settings/widgets/views/settings_drawer.dart`:

(a) Add the import (with the other `package:scheduling/` imports):

```dart
import 'package:scheduling/routes/app_routes.dart';
```

(b) Inside `_buildNavItems`'s `if (widget.isAdmin) ...[` block, after the History `Padding` (the one with `Icons.history_rounded`) and before the closing `],`, add a new item. It can't use `_goTo` (that's destinations-only); it pops the drawer then pushes the plain route:

```dart
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sp12),
          child: _NavItem(
            icon: Icons.insights_rounded,
            iconColor: scheme.secondary,
            label: context.l10n.dashboard_title,
            onTap: () {
              Navigator.pop(context);
              Navigator.pushNamed(context, AppRoutes.dashboard);
            },
          ),
        ),
```

- [ ] **Step 3: Settings tile (split-layout entry — the drawer is null there)**

In `lib/features/settings/screens/settings_screen.dart`:

(a) Add the import:

```dart
import 'package:scheduling/routes/app_routes.dart';
```

(b) In `_buildMaster`, at the TOP of the existing `if (_isAdmin) ...[` block (before the Integrations `SettingsSectionHeader`), add a Management section:

```dart
          const SizedBox(height: AppSpacing.sp24),
          SettingsSectionHeader(
            label: context.l10n.settings_management.toUpperCase(),
          ),
          SettingsSectionCard(
            child: SettingsTile(
              iconBg: scheme.primaryContainer,
              icon: Icons.insights_rounded,
              iconColor: scheme.primary,
              label: context.l10n.dashboard_title,
              trailing: Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: scheme.onSurfaceVariant,
              ),
              onTap: () => Navigator.pushNamed(context, AppRoutes.dashboard),
              isLast: true,
            ),
          ),
```

(The existing `const SizedBox(height: AppSpacing.sp24)` that used to lead the admin block now separates Management from Integrations — keep both spacings so each section header keeps its sp24 gap.)

- [ ] **Step 4: Analyze + existing settings tests**

Run: `flutter analyze 2>&1 | grep -E "error -|warning -"`
Expected: no output.

Run: `flutter test test/features/settings`
Expected: `All tests passed!` (settings-screen tests already mock secure storage / PackageInfo per testing.md; the new tile is additive).

- [ ] **Step 5: Commit**

```bash
git add lib/routes/app_routes.dart lib/features/settings
git commit -m "feat(dashboard): route plus drawer and settings entry points"
```

---

### Task 10: Screen widget tests

**Files:**
- Create: `test/features/dashboard/screens/dashboard_screen_test.dart`

Harness mirrors `test/features/calendar/screens/main_calendar_screen_test.dart`. Gotchas encoded below: each `Stream.value` is single-subscription, so build a fresh stream inside every override lambda (never share one instance between `employeesStreamProvider` and `allUsersStreamProvider`); mocktail's `any()` on a `DateTime` parameter needs `registerFallbackValue`.

- [ ] **Step 1: Write the tests**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:scheduling/core/theme/theme_notifier.dart';
import 'package:scheduling/core/theme/themes.dart';
import 'package:scheduling/features/calendar/application/appointments_providers.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/clients/application/clients_providers.dart';
import 'package:scheduling/features/clients/domain/clients_repository.dart';
import 'package:scheduling/features/clients/domain/models/client_record.dart';
import 'package:scheduling/features/dashboard/application/dashboard_providers.dart';
import 'package:scheduling/features/dashboard/screens/dashboard_screen.dart';
import 'package:scheduling/features/employees/application/employees_providers.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';
import 'package:scheduling/l10n/l10n.dart';

class _MockClientsRepo extends Mock implements ClientsRepository {}

/// Fixed clock: Wednesday 2026-07-08, noon.
final _now = DateTime(2026, 7, 8, 12);

const _jane = EmployeeRecord(
  id: 'e1',
  name: 'Jane Doe',
  email: 'jane@example.com',
  status: 'active',
);

AppointmentRecord _appt({
  required String id,
  required DateTime start,
  String status = 'pending',
  List<String> employeeIds = const ['e1'],
}) => AppointmentRecord(
  id: id,
  title: 'Job $id',
  startTime: start,
  endTime: start.add(const Duration(hours: 1)),
  status: status,
  employeeIds: employeeIds,
);

Widget _wrap({
  required List<AppointmentRecord> appointments,
  required ClientsRepository clientsRepo,
  Object? appointmentsError,
}) {
  return ProviderScope(
    overrides: [
      dashboardClockProvider.overrideWithValue(() => _now),
      appointmentsInRangeProvider.overrideWith(
        (_, _) => appointmentsError != null
            ? Stream<List<AppointmentRecord>>.error(appointmentsError)
            : Stream.value(appointments),
      ),
      // Fresh stream per provider: Stream.value is single-subscription.
      employeesStreamProvider.overrideWith((_) => Stream.value(const [_jane])),
      allUsersStreamProvider.overrideWith((_) => Stream.value(const [_jane])),
      clientsRepositoryProvider.overrideWithValue(clientsRepo),
    ],
    child: ThemeNotifier(
      themeMode: ThemeMode.light,
      toggleTheme: () {},
      textScale: 1,
      setTextScale: (_) {},
      setLanguage: (_) {},
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: lightTheme(),
        home: const DashboardScreen(),
      ),
    ),
  );
}

void main() {
  late _MockClientsRepo clientsRepo;

  setUpAll(() {
    registerFallbackValue(DateTime(2026));
  });

  setUp(() {
    clientsRepo = _MockClientsRepo();
    when(() => clientsRepo.fetchClientsCreatedSince(any())).thenAnswer(
      (_) async => [
        ClientRecord.fromMap('c1', {
          'name': 'Alice',
          'createdAt': DateTime(2026, 7, 7),
        }),
      ],
    );
  });

  Future<void> withPhoneViewport(WidgetTester tester) async {
    tester.view.physicalSize = const Size(412 * 3, 915 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('renders the hero, all section headers, and a workload row', (
    tester,
  ) async {
    await withPhoneViewport(tester);
    await tester.pumpWidget(
      _wrap(
        appointments: [
          // Upcoming today AND pending-within-48h.
          _appt(id: 'up', start: DateTime(2026, 7, 8, 14)),
          // Ended yesterday, never closed.
          _appt(
            id: 'overdue',
            start: DateTime(2026, 7, 7, 9),
            status: 'in_progress',
          ),
        ],
        clientsRepo: clientsRepo,
      ),
    );
    await tester.pumpAndSettle();

    // Hero big-number label lives in a Text.rich span.
    expect(
      find.textContaining('visits today', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('NEXT UP TODAY'), findsOneWidget);
    expect(find.text('EMPLOYEE WORKLOAD'), findsOneWidget);
    expect(find.text('BUSINESS TRENDS'), findsOneWidget);
    expect(find.text('NEEDS ATTENTION'), findsOneWidget);
    expect(find.text('Jane Doe'), findsWidgets);
    expect(
      find.text('1 pending visit starts within 48 hours'),
      findsOneWidget,
    );
    expect(find.text('1 past visit was never closed'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows the unassigned pill for an unassigned visit today', (
    tester,
  ) async {
    await withPhoneViewport(tester);
    await tester.pumpWidget(
      _wrap(
        appointments: [
          _appt(
            id: 'open',
            start: DateTime(2026, 7, 8, 15),
            employeeIds: const [],
          ),
        ],
        clientsRepo: clientsRepo,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('1 unassigned job today'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty data shows all-clear and no-visits states', (
    tester,
  ) async {
    await withPhoneViewport(tester);
    when(() => clientsRepo.fetchClientsCreatedSince(any()))
        .thenAnswer((_) async => const []);
    await tester.pumpWidget(
      _wrap(appointments: const [], clientsRepo: clientsRepo),
    );
    await tester.pumpAndSettle();

    expect(find.text('No upcoming visits today'), findsOneWidget);
    expect(
      find.text('All clear — nothing needs attention'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('stream error renders the error body without throwing', (
    tester,
  ) async {
    await withPhoneViewport(tester);
    await tester.pumpWidget(
      _wrap(
        appointments: const [],
        clientsRepo: clientsRepo,
        appointmentsError: Exception('boom'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text("Couldn't load the dashboard"), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
```

- [ ] **Step 2: Run the tests**

Run: `flutter test test/features/dashboard`
Expected: `All tests passed!` (aggregator + screen).

- [ ] **Step 3: Commit**

```bash
git add test/features/dashboard
git commit -m "test(dashboard): screen widget tests"
```

---

### Task 11: Full verification

- [ ] **Step 1: Analyzer**

Run: `flutter analyze 2>&1 | grep -E "error -|warning -"`
Expected: no output.

- [ ] **Step 2: Full test suite**

Run: `flutter test`
Expected: all green (≈750+ tests). Any failure outside `test/features/dashboard` means a wiring change broke something — fix before proceeding.

- [ ] **Step 3: l10n drift check**

Run: `flutter gen-l10n`
Then confirm `lib/l10n/.gen/untranslated.json` lists no `dashboard_`/`settings_management`/`error_introLoadDashboard` keys.

- [ ] **Step 4: Device pass (Android dev harness — manual)**

`flutter run` on the emulator/device and verify:
- Portrait: end-drawer shows the Dashboard item (admin), tap opens the screen, back returns.
- Landscape / split (`adb shell wm size 1600x900`, then `wm size reset`): drawer is gone; Settings → Management → Dashboard tile opens the same screen.
- Dark mode: chart colors legible; hero segmented bar + legend readable on the primary gradient.
- Text scale 2.0 (Settings → Text size XL): no overflows in the hero legend, timeline rows, workload rows, or flag headers.
- Signed in as a non-admin employee: neither entry point is visible.

- [ ] **Step 5: Final commit if the device pass required tweaks**

```bash
git add -A
git commit -m "fix(dashboard): device-pass polish"
```

---

## Self-review notes (already applied)

- Spec coverage: all four sections (hero + timeline + workload + trends + flags), one-listener data strategy, counting semantics, fl_chart specifics, both entry points, l10n bucket, and the verification list each map to a task. "Clients with no upcoming appointment" stays dropped per spec.
- UI treatment matches the user's mockup pick (Option B hero/workload/trends + Option C timeline/alert rows), recorded in the header and deviations 3–4.
- Type consistency: `DashboardAggregator` names match between Tasks 2/5 (`rangeAround`, `computeStats`, `weekStartsFor`); `WeekBucket.completed/cancelled/newClients` and `TodayOps.total` match between Tasks 2/7; `fetchClientsCreatedSince` matches between Tasks 3/5/10; `AttentionFlagsSection` takes `nameMap` only (no `colorMap`) in both Tasks 7 and 8.
- Known judgment calls an implementer may hit: fl_chart 1.x API drift (adapt, don't pin back) and the `AsyncValue` pattern-match in the screen (`AsyncData`/`AsyncError` sealed cases are Riverpod 3-safe; fall back to `.when` if the analyzer complains).

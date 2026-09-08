# Feature Tour 1.56/1.57 Update — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Status:** SHIPPED — all 10 tasks implemented 2026-09-05 (`4c82eb60` ->
`4ab95819`), released in 1.58.0+87. App-side only; nothing to deploy. The tour
now runs 52 steps across 12 scopes with per-STEP seen flags (`tour_seen_steps`).
Design doc: `docs/plans/2026-09-04-feature-tour-1-57-update.md`.

**Goal:** Cover the 1.56/1.57 features in the in-app tour, and change tour "seen" tracking from per-screen to per-step so devices that already toured a screen are shown only the newly-added steps.

**Architecture:** `TourSeenController` moves from `Set<TourScope>` in `tour_seen_tabs` to `Set<TourStepId>` in a new `tour_seen_steps` key, seeded once from the old key through a const legacy snapshot. `FeatureTourHost` filters a scope's catalog to unseen ids before the existing `isTargetRendered` pass, and marks seen only the ids that actually ran. Eight new steps are added across the calendar, Settings, and a new `sheet_jobDetails` scope on the appointment details sheet.

**Tech Stack:** Flutter/Dart 3.10, Riverpod 3 (`NotifierProvider`), `shared_preferences`, `showcaseview` 5.x, `gen_l10n` ARB localization.

**Design doc:** `docs/plans/2026-09-04-feature-tour-1-57-update.md`

---

## File Structure

**Modified — tour core:**
- `lib/features/feature_tour/application/tour_seen_store.dart` — state becomes `Set<TourStepId>`; owns the legacy migration.
- `lib/features/feature_tour/domain/tour_step_id.dart` — 8 new enum members.
- `lib/features/feature_tour/domain/tour_scope.dart` — `TourForm.jobDetails`.
- `lib/features/feature_tour/domain/tour_definitions.dart` — new catalogs and steps.
- `lib/features/feature_tour/widgets/feature_tour_host.dart` — per-step gating.
- `lib/features/feature_tour/widgets/tour_step_text.dart` — text for the 8 new ids.
- `lib/features/feature_tour/CLAUDE.md` — rules rewritten for per-step seen.

**Created:**
- `lib/features/feature_tour/domain/legacy_tour_steps.dart` — the const 1.57 snapshot the migration reads. Its own file because it is frozen data that must never be edited again, unlike `tour_definitions.dart` which changes every release.

**Modified — screens and widgets carrying new targets:**
- `lib/features/calendar/screens/main_calendar_screen.dart`
- `lib/features/settings/screens/settings_screen.dart`
- `lib/features/settings/widgets/cards/notifications_settings_card.dart`
- `lib/features/calendar/widgets/views/event_details_view.dart`
- `lib/features/calendar/widgets/views/details_view_body.dart`
- `lib/features/calendar/widgets/views/details_action_bar.dart`

Push back is rendered by `_ClientSection` inside `details_view_body.dart` itself (a `QuickActionButton`), so `details_view_widgets.dart` is NOT touched.

**Modified — localization:**
- `lib/l10n/app_en.arb`, `lib/l10n/app_fr.arb`

**Modified — tests:**
- `test/features/feature_tour/application/tour_seen_store_test.dart`
- `test/features/feature_tour/domain/tour_definitions_test.dart`
- `test/features/feature_tour/widgets/feature_tour_host_test.dart`
- `test/support/tour_test_support.dart`

---

### Task 1: Per-step seen store with one-time migration

**Files:**
- Create: `lib/features/feature_tour/domain/legacy_tour_steps.dart`
- Modify: `lib/features/feature_tour/domain/tour_step_id.dart`
- Modify: `lib/features/feature_tour/application/tour_seen_store.dart`
- Test: `test/features/feature_tour/application/tour_seen_store_test.dart`

- [ ] **Step 1: Write the legacy snapshot**

Create `lib/features/feature_tour/domain/legacy_tour_steps.dart`:

```dart
import 'package:scheduling/features/feature_tour/domain/tour_step_id.dart';

/// The steps each tour scope carried at 1.57, keyed by `TourScope.storageKey`,
/// as the union across both roles.
///
/// FROZEN. It exists only to seed `tour_seen_steps` from the per-scope
/// `tour_seen_tabs` flags a device installed before this release already
/// holds: a device that saw a scope saw everything that scope could show it,
/// so every id here counts as seen. A step added after 1.57 must NOT be added
/// here, or it is marked seen on upgrade and no existing device ever sees it.
const Map<String, List<TourStepId>> kLegacyTourSteps = {
  'calendar': [
    TourStepId.calendarGrid,
    TourStepId.calendarDayList,
    TourStepId.calendarCollapse,
    TourStepId.calendarAddAppointment,
    TourStepId.calendarDayRoute,
  ],
  'clients': [
    TourStepId.clientsSearch,
    TourStepId.clientsFilter,
    TourStepId.clientsAdd,
    TourStepId.clientsRow,
  ],
  'employees': [
    TourStepId.employeesSearch,
    TourStepId.employeesAdd,
    TourStepId.employeesRow,
  ],
  'liveMap': [TourStepId.liveMapRoster, TourStepId.liveMapRecenter],
  'history': [
    TourStepId.historySearch,
    TourStepId.historyFilter,
    TourStepId.historyRow,
  ],
  'settings': [
    TourStepId.settingsAppearance,
    TourStepId.settingsNotifications,
    TourStepId.settingsReplay,
  ],
  'dayRoute': [
    TourStepId.dayRouteDaySwitcher,
    TourStepId.dayRouteEmployee,
    TourStepId.dayRouteStops,
    TourStepId.dayRouteNavigate,
  ],
  'dashboard': [
    TourStepId.dashboardHero,
    TourStepId.dashboardUpcoming,
    TourStepId.dashboardWorkload,
    TourStepId.dashboardAttention,
  ],
  'sheet_addAppointment': [
    TourStepId.apptTemplates,
    TourStepId.apptClient,
    TourStepId.apptCrew,
    TourStepId.apptSchedule,
    TourStepId.apptDetails,
    TourStepId.apptSave,
  ],
  'sheet_addClient': [
    TourStepId.clientWho,
    TourStepId.clientReach,
    TourStepId.clientSite,
    TourStepId.clientSave,
  ],
  'sheet_invitePerson': [
    TourStepId.personDetails,
    TourStepId.personJobTitle,
    TourStepId.personColour,
    TourStepId.personCreate,
  ],
};
```

- [ ] **Step 2: Add the 8 new enum members**

They are inert until Task 3 gives them text, but the Step 3 tests reference them. Append to the enum in `lib/features/feature_tour/domain/tour_step_id.dart`, keeping the existing grouping-comment style:

```dart
  // The 1.56/1.57 features.
  calendarWeekToggle,
  calendarCrewFilter,
  settingsLocationSharing,
  // The job-details sheet walkthrough.
  jobPushBack,
  jobFieldRecord,
  jobStart,
  jobMarkDone,
  jobBookAgain,
```

- [ ] **Step 3: Write the failing tests**

Replace `test/features/feature_tour/application/tour_seen_store_test.dart` entirely with:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/features/feature_tour/application/tour_seen_store.dart';
import 'package:scheduling/features/feature_tour/domain/tour_step_id.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ProviderContainer newContainer() {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    // Keep the notifier alive across reads (project testing rule).
    c.listen(tourSeenProvider, (_, _) {});
    return c;
  }

  test('loads persisted step ids after ready resolves', () async {
    SharedPreferences.setMockInitialValues({
      'tour_seen_steps': ['calendarGrid', 'settingsReplay'],
    });
    final container = newContainer();
    await container.read(tourSeenProvider.notifier).ready;
    expect(container.read(tourSeenProvider), {
      TourStepId.calendarGrid,
      TourStepId.settingsReplay,
    });
  });

  test('an id that no longer exists is dropped, not resurrected', () async {
    SharedPreferences.setMockInitialValues({
      'tour_seen_steps': ['calendarGrid', 'retiredStepFromAnOldBuild'],
    });
    final container = newContainer();
    await container.read(tourSeenProvider.notifier).ready;
    expect(container.read(tourSeenProvider), {TourStepId.calendarGrid});
  });

  test('migrates the legacy per-scope flags into step ids', () async {
    SharedPreferences.setMockInitialValues({
      'tour_seen_tabs': ['calendar', 'sheet_addClient'],
    });
    final container = newContainer();
    await container.read(tourSeenProvider.notifier).ready;
    final seen = container.read(tourSeenProvider);
    // Every 1.57 step of a seen scope counts as seen...
    expect(seen, contains(TourStepId.calendarGrid));
    expect(seen, contains(TourStepId.calendarDayRoute));
    expect(seen, contains(TourStepId.clientSave));
    // ...but a step added after 1.57 does not, or nobody would ever see it.
    expect(seen, isNot(contains(TourStepId.calendarWeekToggle)));
    expect(seen, isNot(contains(TourStepId.calendarCrewFilter)));
    // A scope the device never saw contributes nothing.
    expect(seen, isNot(contains(TourStepId.dashboardHero)));
    // The migration persists, so it only runs once.
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('tour_seen_steps'), contains('calendarGrid'));
  });

  test('an unknown legacy scope key is ignored by the migration', () async {
    SharedPreferences.setMockInitialValues({
      'tour_seen_tabs': ['someRetiredTab'],
    });
    final container = newContainer();
    await container.read(tourSeenProvider.notifier).ready;
    expect(container.read(tourSeenProvider), isEmpty);
  });

  test('an existing step list wins over the legacy flags', () async {
    SharedPreferences.setMockInitialValues({
      'tour_seen_tabs': ['calendar'],
      'tour_seen_steps': ['settingsReplay'],
    });
    final container = newContainer();
    await container.read(tourSeenProvider.notifier).ready;
    expect(container.read(tourSeenProvider), {TourStepId.settingsReplay});
  });

  test('markSteps adds the ids and persists them', () async {
    SharedPreferences.setMockInitialValues({});
    final container = newContainer();
    final notifier = container.read(tourSeenProvider.notifier);
    await notifier.ready;
    await notifier.markSteps([TourStepId.jobStart, TourStepId.jobMarkDone]);
    expect(container.read(tourSeenProvider), {
      TourStepId.jobStart,
      TourStepId.jobMarkDone,
    });
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('tour_seen_steps'), contains('jobStart'));
  });

  test('markSteps with nothing new neither writes nor notifies', () async {
    SharedPreferences.setMockInitialValues({});
    final container = newContainer();
    final notifier = container.read(tourSeenProvider.notifier);
    await notifier.ready;
    await notifier.markSteps(const []);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('tour_seen_steps'), isNull);
  });

  test('resetAll clears storage without re-migrating', () async {
    SharedPreferences.setMockInitialValues({
      'tour_seen_tabs': ['calendar'],
    });
    final container = newContainer();
    final notifier = container.read(tourSeenProvider.notifier);
    await notifier.ready;
    expect(container.read(tourSeenProvider), isNotEmpty);
    await notifier.resetAll();
    expect(container.read(tourSeenProvider), isEmpty);
    // An EMPTY list is still a PRESENT key, so a later load must not pull the
    // legacy flags back in — that would undo the replay the user just asked
    // for.
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('tour_seen_steps'), isEmpty);
    final second = newContainer();
    await second.read(tourSeenProvider.notifier).ready;
    expect(second.read(tourSeenProvider), isEmpty);
  });
}
```

- [ ] **Step 4: Run the tests to verify they fail**

Run: `flutter test test/features/feature_tour/application/tour_seen_store_test.dart`
Expected: FAIL to compile — "The method 'markSteps' isn't defined for the type 'TourSeenController'".

- [ ] **Step 5: Rewrite the store**

Replace `lib/features/feature_tour/application/tour_seen_store.dart` with:

```dart
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/features/feature_tour/domain/legacy_tour_steps.dart';
import 'package:scheduling/features/feature_tour/domain/tour_step_id.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// SharedPreferences key: the step ids this device has already been shown.
const _keyTourSeenSteps = 'tour_seen_steps';

/// The old key, one entry per SCOPE. Read exactly once, by the migration.
const _keyTourSeenTabs = 'tour_seen_tabs';

TourStepId? _stepByName(String name) {
  for (final id in TourStepId.values) {
    if (id.name == name) return id;
  }
  return null;
}

/// Tracks which tour STEPS this device has already seen. Await `ready` before
/// reading it, or a cold start can replay steps that were already shown.
///
/// Per STEP, not per screen: a release that adds a step to a screen someone
/// already toured has to be able to show them that one step. The scope flag
/// this replaced could not, and a tour that dropped a step because its target
/// hadn't rendered still marked the whole scope seen, losing it for good.
class TourSeenController extends Notifier<Set<TourStepId>> {
  late final Future<void> ready = _load();

  @override
  Set<TourStepId> build() {
    unawaited(ready);
    return const {};
  }

  Future<void> _load() async {
    final logger = ref.read(loggerProvider);
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getStringList(_keyTourSeenSteps);
      if (stored != null) {
        // Lookup-based, so a name that no longer maps to a step is dropped
        // rather than resurrecting a dead one.
        state = {for (final name in stored) ?_stepByName(name)};
        return;
      }
      // First run on this build: seed from the per-scope flags. The ABSENCE of
      // the step key is the marker, so a resetAll writing an empty list can
      // never re-trigger this.
      final legacy = prefs.getStringList(_keyTourSeenTabs) ?? const <String>[];
      state = {for (final key in legacy) ...?kLegacyTourSteps[key]};
      await _save();
    } catch (e, st) {
      // This is unawaited from build(), so on failure we just fall back to
      // treating the device like a fresh install.
      logger.warn('TOUR read seen flags failed', e, st);
    }
  }

  /// Marks the steps that actually ran — never a whole scope. A step whose
  /// target wasn't rendered has not been seen and must be offered again.
  Future<void> markSteps(Iterable<TourStepId> ids) async {
    final next = {...state, ...ids};
    if (next.length == state.length) return;
    state = next;
    await _save();
  }

  Future<void> resetAll() async {
    state = const {};
    await _save();
  }

  /// Saves aren't serialized, but that's fine since writers never overlap.
  Future<void> _save() async {
    final logger = ref.read(loggerProvider);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_keyTourSeenSteps, [
        for (final id in state) id.name,
      ]);
    } catch (e, st) {
      logger.warn('TOUR write seen flags failed', e, st);
    }
  }
}

final tourSeenProvider = NotifierProvider<TourSeenController, Set<TourStepId>>(
  TourSeenController.new,
);
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `flutter test test/features/feature_tour/application/tour_seen_store_test.dart`
Expected: PASS, 8 tests. `flutter analyze` will still report errors in `feature_tour_host.dart` — Task 2 fixes those.

- [ ] **Step 7: Commit**

```bash
git add lib/features/feature_tour/domain/legacy_tour_steps.dart lib/features/feature_tour/domain/tour_step_id.dart lib/features/feature_tour/application/tour_seen_store.dart test/features/feature_tour/application/tour_seen_store_test.dart
git commit -m "Track tour progress per step instead of per screen"
```

---

### Task 2: FeatureTourHost shows only unseen steps

**Files:**
- Modify: `lib/features/feature_tour/widgets/feature_tour_host.dart`
- Test: `test/features/feature_tour/widgets/feature_tour_host_test.dart`

- [ ] **Step 1: Port the existing test file to step storage**

Run: `cat test/features/feature_tour/widgets/feature_tour_host_test.dart`

The file has a local `harness({current, scope, stepKeys, child, container})` builder and a `newContainer()` helper, and each test mounts its targets as explicit `TourShowcase` widgets. There is no `pumpHost`/`keyFor`/`finishTour` — use `harness` directly.

Two mechanical edits first, so the file compiles against Task 1:

- `SharedPreferences.setMockInitialValues({'tour_seen_tabs': ['clients']})` in the "does not start when already seen" test becomes the step names of that catalog: `{'tour_seen_steps': [TourStepId.clientsSearch.name, TourStepId.clientsFilter.name, TourStepId.clientsAdd.name, TourStepId.clientsRow.name]}`. A scope counts as seen only when every step in it does.
- Any assertion reading `tourSeenProvider` for a `TourScope` becomes one for a `TourStepId`.

One existing test changes MEANING and must be rewritten, not ported: **"marks seen without starting when no target is mounted"**. Zero rendered targets now marks NOTHING. Rename it to `'marks nothing seen when no target is mounted'` and invert its assertion to `expect(container.read(tourSeenProvider), isEmpty);`.

- [ ] **Step 2: Write the failing tests**

Append inside `main()`, in the file's own style:

```dart
  testWidgets('starts only the steps this device has not seen', (tester) async {
    SharedPreferences.setMockInitialValues({
      'tour_seen_steps': [TourStepId.clientsSearch.name],
    });
    final container = newContainer();
    final searchKey = GlobalKey();
    final addKey = GlobalKey();
    await tester.pumpWidget(
      harness(
        current: HubTab.clients,
        scope: const DestinationTour(HubTab.clients),
        stepKeys: {
          TourStepId.clientsSearch: searchKey,
          TourStepId.clientsAdd: addKey,
        },
        container: container,
        child: Column(
          children: [
            TourShowcase(
              showcaseKey: searchKey,
              scope: const DestinationTour(HubTab.clients),
              id: TourStepId.clientsSearch,
              index: 0,
              count: 2,
              child: const Text('search target'),
            ),
            TourShowcase(
              showcaseKey: addKey,
              scope: const DestinationTour(HubTab.clients),
              id: TourStepId.clientsAdd,
              index: 1,
              count: 2,
              child: const Text('add target'),
            ),
          ],
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    // The seen step is skipped, so the tour opens on the next one.
    expect(find.text('Find a client'), findsNothing);
    expect(find.text('Add a client'), findsOneWidget);
  });

  testWidgets('marks only the steps that actually ran', (tester) async {
    SharedPreferences.setMockInitialValues({'tour_seen_steps': <String>[]});
    final container = newContainer();
    final searchKey = GlobalKey();
    // Registered as a step, but never mounted — isTargetRendered drops it.
    final addKey = GlobalKey();
    await tester.pumpWidget(
      harness(
        current: HubTab.clients,
        scope: const DestinationTour(HubTab.clients),
        stepKeys: {
          TourStepId.clientsSearch: searchKey,
          TourStepId.clientsAdd: addKey,
        },
        container: container,
        child: TourShowcase(
          showcaseKey: searchKey,
          scope: const DestinationTour(HubTab.clients),
          id: TourStepId.clientsSearch,
          index: 0,
          count: 1,
          child: const Text('search target'),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Skip'));
    await tester.pump(const Duration(seconds: 1));
    final seen = container.read(tourSeenProvider);
    expect(seen, {TourStepId.clientsSearch});
    // The dropped step stays unseen, so a later visit offers it again.
    expect(seen, isNot(contains(TourStepId.clientsAdd)));
  });
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `flutter test test/features/feature_tour/widgets/feature_tour_host_test.dart`
Expected: FAIL to compile — the host still calls `markSeen(widget.scope)` and `seen.contains(widget.scope)` against a `Set<TourStepId>`.

- [ ] **Step 4: Change the host**

In `lib/features/feature_tour/widgets/feature_tour_host.dart`:

Add the field and helper beside `_scope`:

```dart
  /// The ids handed to startShowCase, so only they are marked seen. A step
  /// dropped by isTargetRendered was never shown and must stay unseen.
  List<TourStepId> _runningIds = const [];

  /// This scope's catalog minus what the device has already been shown.
  List<TourStepId> _pendingSteps(Set<TourStepId> seen) => [
    for (final id in tourStepsFor(widget.scope, isAdmin: widget.isAdmin))
      if (!seen.contains(id)) id,
  ];
```

Replace `_markSeen` with:

```dart
  void _markRanStepsSeen() {
    unawaited(ref.read(tourSeenProvider.notifier).markSteps(_runningIds));
    _runningIds = const [];
  }
```

Point `_onTourEnd` at it:

```dart
  void _onTourEnd() {
    if (!_tourRunning) return;
    _tourRunning = false;
    _markRanStepsSeen();
  }
```

In `dispose`, clear the ids alongside the flag in the unfinished-tour branch:

```dart
      _tourRunning = false; // Don't mark seen (unfinished tour).
      _runningIds = const [];
```

In `build`, replace the `seen.contains(widget.scope)` branch:

```dart
    final seen = ref.watch(tourSeenProvider);
```

```dart
    if (_pendingSteps(seen).isEmpty) {
      // Re-arm so a Settings "replay" reset can start the tour again.
      _started = false;
    } else if (visible && widget.ready && !_started) {
      _started = true;
      unawaited(_start());
    }
```

In `_start`, replace the early bail:

```dart
    await ref.read(tourSeenProvider.notifier).ready;
    if (!mounted) return;
    if (_pendingSteps(ref.read(tourSeenProvider)).isEmpty) return;
```

and the key-collection block inside the post-frame callback:

```dart
      final steps = _pendingSteps(ref.read(tourSeenProvider));
      try {
        final showcaseView = ShowcaseView.getNamed(_scope);
        // showcaseview 5.x never forwards key to Element; use isTargetRendered.
        final running = <TourStepId>[];
        final keys = <GlobalKey>[];
        for (final id in steps) {
          if (widget.stepKeys[id] case final key?
              when showcaseView.isTargetRendered(key)) {
            running.add(id);
            keys.add(key);
          }
        }
        if (keys.isEmpty) {
          // Nothing rendered for this layout, role or job state. Mark NOTHING —
          // these steps haven't been seen, and the next visit retries them.
          return;
        }
        // A form sheet may autofocus its first field, and the keyboard then
        // covers the lower half of every target. Harmless on the screen
        // tours — none of them autofocus.
        FocusManager.instance.primaryFocus?.unfocus();
        _runningIds = running;
        _tourRunning = true;
        showcaseView.startShowCase(keys);
      } catch (e, st) {
        // getNamed throws if the scope's already gone — don't crash the tab.
        _tourRunning = false;
        _started = false;
        _runningIds = const [];
        _logger.warn('TOUR start failed', e, st);
      }
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `flutter test test/features/feature_tour/widgets/feature_tour_host_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/features/feature_tour/widgets/feature_tour_host.dart test/features/feature_tour/widgets/feature_tour_host_test.dart
git commit -m "Start only the tour steps a device has not seen"
```

---

### Task 3: Text and localization for the eight new steps

**Files:**
- Modify: `lib/l10n/app_en.arb`, `lib/l10n/app_fr.arb`
- Modify: `lib/features/feature_tour/widgets/tour_step_text.dart`

- [ ] **Step 1: Add the EN keys**

Append to `lib/l10n/app_en.arb` alongside the other `tour_*` entries. Every key needs its `@key` block — `required-resource-attributes: true` makes `flutter gen-l10n` fail on a bare key:

```json
  "tour_calendarWeekToggleTitle": "One day, or the whole week",
  "@tour_calendarWeekToggleTitle": {
    "description": "Tour step title: calendar day/week agenda toggle"
  },
  "tour_calendarWeekToggleDesc": "Switch the agenda between the selected day and the whole week, each day under its own bar with its job count.",
  "@tour_calendarWeekToggleDesc": {
    "description": "Tour step description: calendar day/week agenda toggle"
  },
  "tour_calendarCrewFilterTitle": "Follow one person",
  "@tour_calendarCrewFilterTitle": {
    "description": "Tour step title: calendar crew filter button"
  },
  "tour_calendarCrewFilterDesc": "Narrow the whole calendar to one crew member. A banner names who, and Clear brings everyone back.",
  "@tour_calendarCrewFilterDesc": {
    "description": "Tour step description: calendar crew filter button"
  },
  "tour_settingsLocationSharingTitle": "Sharing your location",
  "@tour_settingsLocationSharingTitle": {
    "description": "Tour step title: settings location sharing row"
  },
  "tour_settingsLocationSharingDesc": "Your position reaches the staff map only while this is on. Turning it off also erases the position already stored.",
  "@tour_settingsLocationSharingDesc": {
    "description": "Tour step description: settings location sharing row"
  },
  "tour_jobPushBackTitle": "Running late",
  "@tour_jobPushBackTitle": {
    "description": "Tour step title: job details push back action"
  },
  "tour_jobPushBackDesc": "Move this job later by a set amount without opening the edit form.",
  "@tour_jobPushBackDesc": {
    "description": "Tour step description: job details push back action"
  },
  "tour_jobFieldRecordTitle": "What you found",
  "@tour_jobFieldRecordTitle": {
    "description": "Tour step title: job details crew field record"
  },
  "tour_jobFieldRecordDesc": "Your own notes and photos for this job, kept separate from the brief the office wrote so neither can overwrite the other.",
  "@tour_jobFieldRecordDesc": {
    "description": "Tour step description: job details crew field record"
  },
  "tour_jobStartTitle": "Say you have arrived",
  "@tour_jobStartTitle": {
    "description": "Tour step title: job details start button"
  },
  "tour_jobStartDesc": "Start stamps your arrival and begins the clock, so the job shows when it started, when it finished and how long it took.",
  "@tour_jobStartDesc": {
    "description": "Tour step description: job details start button"
  },
  "tour_jobMarkDoneTitle": "Closing the job",
  "@tour_jobMarkDoneTitle": {
    "description": "Tour step title: job details mark complete button"
  },
  "tour_jobMarkDoneDesc": "Marks the job finished and records the time. Closed one by mistake? The confirmation carries an Undo for as long as it is on screen.",
  "@tour_jobMarkDoneDesc": {
    "description": "Tour step description: job details mark complete button"
  },
  "tour_jobBookAgainTitle": "Book it again",
  "@tour_jobBookAgainTitle": {
    "description": "Tour step title: job details book again action"
  },
  "tour_jobBookAgainDesc": "Opens a new appointment already carrying the client, address, crew and brief — you only pick the date and time.",
  "@tour_jobBookAgainDesc": {
    "description": "Tour step description: job details book again action"
  },
```

- [ ] **Step 2: Add the FR keys**

Append the same 16 keys to `lib/l10n/app_fr.arb`. FR is not the template, so it carries no `@` blocks:

```json
  "tour_calendarWeekToggleTitle": "Un jour, ou toute la semaine",
  "tour_calendarWeekToggleDesc": "Basculez l'agenda entre le jour choisi et la semaine complète, chaque jour sous sa propre barre avec son nombre de travaux.",
  "tour_calendarCrewFilterTitle": "Suivre une personne",
  "tour_calendarCrewFilterDesc": "Limitez tout le calendrier à un membre de l'équipe. Une bannière indique qui, et Effacer les affiche tous de nouveau.",
  "tour_settingsLocationSharingTitle": "Le partage de votre position",
  "tour_settingsLocationSharingDesc": "Votre position n'atteint la carte de l'équipe que lorsque ceci est activé. La désactiver efface aussi la position déjà enregistrée.",
  "tour_jobPushBackTitle": "En retard",
  "tour_jobPushBackDesc": "Reportez ce travail d'une durée déterminée sans ouvrir le formulaire de modification.",
  "tour_jobFieldRecordTitle": "Ce que vous avez constaté",
  "tour_jobFieldRecordDesc": "Vos propres notes et photos pour ce travail, distinctes des consignes rédigées au bureau : aucune ne peut écraser l'autre.",
  "tour_jobStartTitle": "Signaler votre arrivée",
  "tour_jobStartDesc": "Démarrer enregistre votre arrivée et lance le chronomètre : le travail indique son début, sa fin et sa durée.",
  "tour_jobMarkDoneTitle": "Clore le travail",
  "tour_jobMarkDoneDesc": "Marque le travail terminé et enregistre l'heure. Une erreur ? La confirmation offre Annuler tant qu'elle est affichée.",
  "tour_jobBookAgainTitle": "Réserver de nouveau",
  "tour_jobBookAgainDesc": "Ouvre un nouveau rendez-vous contenant déjà le client, l'adresse, l'équipe et les consignes — vous ne choisissez que la date et l'heure.",
```

- [ ] **Step 3: Add the switch arms**

`tourStepText`'s `switch (id)` is exhaustive over the enum, so it will not compile without all eight. Add to `lib/features/feature_tour/widgets/tour_step_text.dart`:

```dart
  TourStepId.calendarWeekToggle => (
    title: l.tour_calendarWeekToggleTitle,
    description: l.tour_calendarWeekToggleDesc,
  ),
  TourStepId.calendarCrewFilter => (
    title: l.tour_calendarCrewFilterTitle,
    description: l.tour_calendarCrewFilterDesc,
  ),
  TourStepId.settingsLocationSharing => (
    title: l.tour_settingsLocationSharingTitle,
    description: l.tour_settingsLocationSharingDesc,
  ),
  TourStepId.jobPushBack => (
    title: l.tour_jobPushBackTitle,
    description: l.tour_jobPushBackDesc,
  ),
  TourStepId.jobFieldRecord => (
    title: l.tour_jobFieldRecordTitle,
    description: l.tour_jobFieldRecordDesc,
  ),
  TourStepId.jobStart => (
    title: l.tour_jobStartTitle,
    description: l.tour_jobStartDesc,
  ),
  TourStepId.jobMarkDone => (
    title: l.tour_jobMarkDoneTitle,
    description: l.tour_jobMarkDoneDesc,
  ),
  TourStepId.jobBookAgain => (
    title: l.tour_jobBookAgainTitle,
    description: l.tour_jobBookAgainDesc,
  ),
```

- [ ] **Step 4: Verify generation and EN/FR drift**

The repo's ARB hook regenerates `lib/l10n/.gen/` on an ARB edit — do NOT run `flutter gen-l10n` by hand.

Run: `flutter analyze`
Expected: `No issues found!`, apart from the not-yet-wired screens.

Run: `grep -c 'tour_' lib/l10n/.gen/untranslated.json`
Expected: `0`, or the file absent. Anything else means a key landed in EN but not FR.

- [ ] **Step 5: Commit**

```bash
git add lib/l10n/app_en.arb lib/l10n/app_fr.arb lib/features/feature_tour/widgets/tour_step_text.dart
git commit -m "Add tour copy for the week view, crew filter, location sharing and job actions"
```

---

### Task 4: The job-details scope and the new catalogs

**Files:**
- Modify: `lib/features/feature_tour/domain/tour_scope.dart`
- Modify: `lib/features/feature_tour/domain/tour_definitions.dart`
- Test: `test/features/feature_tour/domain/tour_definitions_test.dart`

- [ ] **Step 1: Write the failing tests**

Append inside `main()` in `test/features/feature_tour/domain/tour_definitions_test.dart`:

```dart
  test('the job details sheet has a tour for both roles', () {
    const scope = FormTour(TourForm.jobDetails);
    expect(tourStepsFor(scope, isAdmin: true), isNotEmpty);
    expect(tourStepsFor(scope, isAdmin: false), isNotEmpty);
  });

  test('the job details tour splits by what each role may do', () {
    const scope = FormTour(TourForm.jobDetails);
    final admin = tourStepsFor(scope, isAdmin: true);
    final crew = tourStepsFor(scope, isAdmin: false);
    // Push back and book again are the admin's.
    expect(admin, contains(TourStepId.jobPushBack));
    expect(admin, contains(TourStepId.jobBookAgain));
    expect(crew, isNot(contains(TourStepId.jobPushBack)));
    expect(crew, isNot(contains(TourStepId.jobBookAgain)));
    // The field record is offered to a non-admin assignee only.
    expect(crew, contains(TourStepId.jobFieldRecord));
    expect(admin, isNot(contains(TourStepId.jobFieldRecord)));
    // Starting and closing a job belong to both.
    expect(admin, contains(TourStepId.jobStart));
    expect(crew, contains(TourStepId.jobStart));
    expect(admin, contains(TourStepId.jobMarkDone));
    expect(crew, contains(TourStepId.jobMarkDone));
  });

  test('the three create-flow sheets stay admin-only', () {
    const createFlows = [
      TourForm.addAppointment,
      TourForm.addClient,
      TourForm.invitePerson,
    ];
    for (final form in createFlows) {
      expect(
        tourStepsFor(FormTour(form), isAdmin: false),
        isEmpty,
        reason: '$form is admin-only',
      );
    }
  });

  test('the calendar week toggle is offered to both roles', () {
    expect(
      tourStepsFor(const DestinationTour(HubTab.calendar), isAdmin: false),
      contains(TourStepId.calendarWeekToggle),
    );
    expect(
      tourStepsFor(const DestinationTour(HubTab.calendar), isAdmin: true),
      contains(TourStepId.calendarWeekToggle),
    );
  });

  test('the crew filter is admin-only', () {
    expect(
      tourStepsFor(const DestinationTour(HubTab.calendar), isAdmin: false),
      isNot(contains(TourStepId.calendarCrewFilter)),
    );
  });

  test('every step id belongs to some catalog', () {
    final owned = <TourStepId>{};
    for (final scope in allTourScopes) {
      for (final isAdmin in [true, false]) {
        owned.addAll(tourStepsFor(scope, isAdmin: isAdmin));
      }
    }
    // A step in no catalog is copy nobody can ever see.
    expect(
      TourStepId.values.where((id) => !owned.contains(id)),
      isEmpty,
      reason: 'these ids are in no catalog',
    );
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/features/feature_tour/domain/tour_definitions_test.dart`
Expected: FAIL to compile — "There's no constant named 'jobDetails' in 'TourForm'".

- [ ] **Step 3: Add the enum member**

In `lib/features/feature_tour/domain/tour_scope.dart`, widen the doc comment and append the member. `.name` is persisted but enum ORDER is not, so appending is simply tidy:

```dart
/// The sheets that carry a walkthrough — the three create flows, plus the
/// job-details sheet. `.name` is persisted, so renaming a member replays or
/// orphans that tour.
enum TourForm { addAppointment, addClient, invitePerson, jobDetails }
```

- [ ] **Step 4: Add the two new destination steps**

In `lib/features/feature_tour/domain/tour_definitions.dart`, `calendarWeekToggle` sits next to `calendarDayList` because it controls that list, and `calendarCrewFilter` with the other header controls:

```dart
  HubTab.calendar => [
    TourStepId.calendarGrid,
    TourStepId.calendarDayList,
    TourStepId.calendarWeekToggle,
    // Portrait only — the handle doesn't exist in the split layout, so
    // isTargetRendered drops this step there.
    TourStepId.calendarCollapse,
    if (isAdmin) TourStepId.calendarCrewFilter,
    if (isAdmin) TourStepId.calendarAddAppointment,
    TourStepId.calendarDayRoute,
  ],
```

The location row lives inside the notifications card, so its step follows it:

```dart
  PushedDestination.settings => [
    TourStepId.settingsAppearance,
    TourStepId.settingsNotifications,
    TourStepId.settingsLocationSharing,
    TourStepId.settingsReplay,
  ],
```

- [ ] **Step 5: Rewrite `_formSteps`**

The blanket `if (!isAdmin) return const [];` has to move inside the switch — `jobDetails` is the first form scope with a crew catalog:

```dart
/// The sheet walkthroughs.
List<TourStepId> _formSteps(TourForm form, {required bool isAdmin}) =>
    switch (form) {
      TourForm.addAppointment => [
        if (isAdmin) ...[
          TourStepId.apptTemplates,
          TourStepId.apptClient,
          TourStepId.apptCrew,
          TourStepId.apptSchedule,
          TourStepId.apptDetails,
          TourStepId.apptSave,
        ],
      ],
      TourForm.addClient => [
        if (isAdmin) ...[
          TourStepId.clientWho,
          TourStepId.clientReach,
          TourStepId.clientSite,
          TourStepId.clientSave,
        ],
      ],
      TourForm.invitePerson => [
        if (isAdmin) ...[
          TourStepId.personDetails,
          TourStepId.personJobTitle,
          TourStepId.personColour,
          TourStepId.personCreate,
        ],
      ],
      // The sheet's own visual order: push back sits in the client block, the
      // field record above the action bar, the bar's buttons last. The field
      // record goes to a non-admin ASSIGNEE only — exactly the set the crew
      // branches of firestore.rules admit.
      TourForm.jobDetails => [
        if (isAdmin) TourStepId.jobPushBack,
        if (!isAdmin) TourStepId.jobFieldRecord,
        TourStepId.jobStart,
        TourStepId.jobMarkDone,
        if (isAdmin) TourStepId.jobBookAgain,
      ],
    };
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `flutter test test/features/feature_tour/domain/`
Expected: PASS, including the pre-existing drawer-set test.

- [ ] **Step 7: Commit**

```bash
git add lib/features/feature_tour/domain/tour_scope.dart lib/features/feature_tour/domain/tour_definitions.dart test/features/feature_tour/domain/tour_definitions_test.dart
git commit -m "Add the job-details tour scope and the new calendar and settings steps"
```

---

### Task 5: Wire the calendar targets

**Files:**
- Modify: `lib/features/calendar/screens/main_calendar_screen.dart` (~line 415 header block, ~line 590 agenda header)

- [ ] **Step 1: Wrap the agenda mode toggle**

In `_content`, the toggle is passed as `AgendaHeader.trailing`. Wrapping it there puts the highlight on the segmented control rather than the whole header:

```dart
            trailing: _tour.stepIf(
              TourStepId.calendarWeekToggle,
              _agendaModeToggle(context),
            ),
```

- [ ] **Step 2: Wrap the crew filter button**

In `build`, where `CalendarHeaderBlock.crewFilterButton` is supplied:

```dart
                  crewFilterButton: widget.isAdmin
                      ? _tour.stepIf(
                          TourStepId.calendarCrewFilter,
                          const CrewFilterButton(),
                        )
                      : null,
```

`stepIf`, never `step`: an employee's catalog has no `calendarCrewFilter` and `step` force-unwraps `keys[id]!`.

- [ ] **Step 3: Verify**

Run: `flutter analyze`
Expected: `No issues found!`

Run: `flutter test test/features/calendar/`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add lib/features/calendar/screens/main_calendar_screen.dart
git commit -m "Tour the calendar week toggle and crew filter"
```

---

### Task 6: Wire the Settings location-sharing target

**Files:**
- Modify: `lib/features/settings/widgets/cards/notifications_settings_card.dart`
- Modify: `lib/features/settings/screens/settings_screen.dart` (~line 487)

- [ ] **Step 1: Give the card an optional wrap callback**

The card is a reusable widget, so the tour reaches into it the way `ClientsListView` does — an injected wrap defaulting to identity. Add the parameter and field to `NotificationsSettingsCard`:

```dart
    this.wrapLocationSharing,
```

```dart
  /// Lets the Settings tour wrap the location row as its own step. Null
  /// off-tour, so the card stays usable untoured.
  final Widget Function(Widget)? wrapLocationSharing;
```

- [ ] **Step 2: Apply it to the location tile**

In `build`, inside `if (showLocationSharing) ...[`, the block is currently `const SettingsTileDivider()` followed by a `SettingsTile`. Bind the tile to a local so the wrap reads plainly:

```dart
          if (showLocationSharing) ...[
            const SettingsTileDivider(),
            Builder(
              builder: (context) {
                final tile = SettingsTile(
                  // ...every existing argument, unchanged...
                );
                return wrapLocationSharing?.call(tile) ?? tile;
              },
            ),
          ],
```

- [ ] **Step 3: Pass the wrap from Settings**

In `settings_screen.dart`, on the `NotificationsSettingsCard` already inside `_tour.step(TourStepId.settingsNotifications, ...)`, add:

```dart
        wrapLocationSharing: (child) =>
            _tour.stepIf(TourStepId.settingsLocationSharing, child),
```

The card stays wrapped as `settingsNotifications` as a whole, and the location row is a second, nested target. Two steps over nested targets is fine — they run one after the other.

- [ ] **Step 4: Verify**

Run: `flutter analyze`
Expected: `No issues found!`

Run: `flutter test test/features/settings/`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/settings/widgets/cards/notifications_settings_card.dart lib/features/settings/screens/settings_screen.dart
git commit -m "Tour the location sharing row in Settings"
```

---

### Task 7: Host and wire the job-details tour

**Files:**
- Modify: `lib/features/calendar/widgets/views/event_details_view.dart`
- Modify: `lib/features/calendar/widgets/views/details_view_body.dart`
- Modify: `lib/features/calendar/widgets/views/details_action_bar.dart`
- Modify: `lib/features/calendar/widgets/views/details_view_widgets.dart`

- [ ] **Step 1: Confirm the sheet is the only presentation**

`FormTour` gates on `ModalRoute.of(context)?.isCurrent`, which is correct only because the details view is always a modal bottom sheet.

Run: `grep -rn "EventDetailsView(\|EventDetailsSheet(" lib/ --include=*.dart`
Expected: hits only in `details_edit_sheet.dart` and `sheet_helpers.dart`. If a non-sheet call site exists, stop — the gate needs revisiting before continuing.

- [ ] **Step 2: Give DetailsActionBar its three wrap callbacks**

In `details_action_bar.dart`, add to the constructor and fields:

```dart
    this.wrapStart,
    this.wrapMarkDone,
    this.wrapBookAgain,
```

```dart
  /// Tour wraps, null off-tour so the bar stays usable untoured.
  final Widget Function(Widget)? wrapStart;
  final Widget Function(Widget)? wrapMarkDone;
  final Widget Function(Widget)? wrapBookAgain;
```

Add the helper beside `build`:

```dart
  static Widget _wrap(Widget Function(Widget)? wrap, Widget child) =>
      wrap?.call(child) ?? child;
```

Apply in `build`:

```dart
        if (onStart != null && !isDone && !isCancelled && !isInProgress) ...[
          _wrap(wrapStart, _startButton(context, compact)),
          const SizedBox(height: AppSpacing.sp8),
        ],
        if (!isDone && !isCancelled)
          _wrap(wrapMarkDone, _markDoneButton(context, compact)),
```

and in `_bookAgainSlot`, wrap the `OutlinedButton` it returns:

```dart
    _wrap(
      wrapBookAgain,
      OutlinedButton(
        // ...existing arguments, unchanged...
      ),
    ),
```

- [ ] **Step 3: Give the push-back affordance a wrap**

Push back is a `QuickActionButton` rendered by `_ClientSection`, a private class in `details_view_body.dart` (around line 588) — not in `details_view_widgets.dart`. Add the parameter and field to `_ClientSection` alongside its existing `onPushBack`:

```dart
    this.wrapPushBack,
```

```dart
  final Widget Function(Widget)? wrapPushBack;
```

and apply it at the button:

```dart
              if (onPushBack != null)
                DetailsViewBody._wrap(
                  wrapPushBack,
                  QuickActionButton(
                    icon: Icons.update_rounded,
                    label: context.l10n.calendar_pushBack,
                    onTap: onPushBack!,
                  ),
                ),
```

`DetailsViewBody._wrap` is the static helper added in Step 5; `_ClientSection` is in the same library, so the private access is fine.

- [ ] **Step 4: Build the TourSteps and host in EventDetailsView**

`DetailsViewBody` is a `ConsumerWidget` with no `State` to hold a `late final TourSteps`, so the host and the `TourSteps` live in `EventDetailsView` and the wraps are passed down as parameters — the shape `ClientsListView` already uses.

In the `State` of `event_details_view.dart`:

```dart
  late final _tour = TourSteps(
    const FormTour(TourForm.jobDetails),
    isAdmin: widget.showActions,
  );
```

`showActions` is this sheet's admin signal — it is exactly what gates edit, cancel, push back and book again in `DetailsViewBody`.

Wrap the returned subtree:

```dart
    return FeatureTourHost(
      scope: _tour.scope,
      isAdmin: widget.showActions,
      stepKeys: _tour.keys,
      autoScroll: true,
      child: /* the existing subtree */,
    );
```

The sheet scrolls and every target below the client block is off-fold, so `autoScroll` is required — `isTargetRendered` cannot find a target a lazy list never built and drops the step silently.

`FeatureTourHost` takes NO cache-extent parameter. `kTourScrollCacheExtent` is passed to the scrolling frame instead: the three create-flow sheets pass `scrollCacheExtent: kTourScrollCacheExtent` to `FormSheetFrame` (see `add_appointment_sheet.dart:282`). This sheet's frame is `DraggableSheetFrame` in `details_edit_sheet.dart`, which hands a `scrollController` to a scroll view inside `EventDetailsView`. Give that scroll view `cacheExtent: 3000` (the pixel value `kTourScrollCacheExtent` carries), or add a `scrollCacheExtent` parameter to `DraggableSheetFrame` mirroring `FormSheetFrame`'s — prefer the latter if `DraggableSheetFrame` owns the scroll view.

Run first, to see which of the two the frame is: `grep -n "scrollCacheExtent\|cacheExtent\|SingleChildScrollView\|ListView" lib/shared/widgets/sheets/sheet_widgets.dart lib/features/calendar/widgets/views/event_details_view.dart`

- [ ] **Step 5: Pass the wraps down**

From `EventDetailsView` into `DetailsViewBody`, and from there into `DetailsActionBar` and `_ClientSection`:

```dart
      wrapStart: (c) => _tour.stepIf(TourStepId.jobStart, c),
      wrapMarkDone: (c) => _tour.stepIf(TourStepId.jobMarkDone, c),
      wrapBookAgain: (c) => _tour.stepIf(TourStepId.jobBookAgain, c),
      wrapPushBack: (c) => _tour.stepIf(TourStepId.jobPushBack, c),
      wrapFieldRecord: (c) => _tour.stepIf(TourStepId.jobFieldRecord, c),
```

`DetailsFieldRecordView` is rendered directly by `DetailsViewBody`, so its wrap is applied there rather than inside another widget. Add the same `_wrap` static helper to `DetailsViewBody` and use it:

```dart
        if (canRecordFieldWork)
          _wrap(
            wrapFieldRecord,
            DetailsFieldRecordView(appointment: appointment),
          ),
```

- [ ] **Step 6: Verify**

Run: `flutter analyze`
Expected: `No issues found!`

Run: `flutter test test/features/calendar/`
Expected: PASS. A test that now times out inside `pumpAndSettle` is the sheet's tour starting against a fresh preferences store — that is Task 9's job. Note which files and continue.

- [ ] **Step 7: Commit**

```bash
git add lib/features/calendar/widgets/views/
git commit -m "Tour the job details sheet: start, field record, complete, push back, book again"
```

---

### Task 8: Refresh the three stale step descriptions

**Files:**
- Modify: `lib/l10n/app_en.arb`, `lib/l10n/app_fr.arb`

- [ ] **Step 1: Rewrite the EN descriptions**

Notifications became opt-in in 1.57 and both searches stopped being a capped local window, so these three now describe behaviour the app no longer has. Replace the VALUES in `lib/l10n/app_en.arb`, leaving their `@key` blocks and every title untouched:

```json
  "tour_settingsNotificationsDesc": "Notifications are off until you turn them on here — job assignments, \"time to leave\" and the daily digest all come through this row.",
```

```json
  "tour_clientsSearchDesc": "Search every client by name, phone or address — the whole list, not just the ones on screen.",
```

```json
  "tour_historySearchDesc": "Completed and cancelled visits live here. Search covers the whole archive, and you can filter by year.",
```

- [ ] **Step 2: Rewrite the FR descriptions**

Replace the same three keys in `lib/l10n/app_fr.arb`:

```json
  "tour_settingsNotificationsDesc": "Les notifications sont désactivées tant que vous ne les activez pas ici — affectations, « heure de partir » et résumé quotidien passent tous par cette ligne.",
```

```json
  "tour_clientsSearchDesc": "Cherchez parmi tous vos clients par nom, téléphone ou adresse — toute la liste, pas seulement ce qui est affiché.",
```

```json
  "tour_historySearchDesc": "Les visites terminées et annulées sont ici. La recherche couvre tout l'historique, et vous pouvez filtrer par année.",
```

- [ ] **Step 3: Verify**

Run: `flutter analyze`
Expected: `No issues found!` The ARB hook regenerates `lib/l10n/.gen/`; do not run `flutter gen-l10n` by hand.

- [ ] **Step 4: Commit**

```bash
git add lib/l10n/app_en.arb lib/l10n/app_fr.arb
git commit -m "Refresh tour copy that 1.57 made stale"
```

---

### Task 9: Test support, tour rules, and full verification

**Files:**
- Modify: `test/support/tour_test_support.dart`
- Modify: `lib/features/feature_tour/CLAUDE.md`

- [ ] **Step 1: Rewrite the test helper for per-step storage**

`markFormToursSeen` writes `tour_seen_tabs`, which is now read only by the migration — and the migration seeds the OLD steps, leaving the new `jobDetails` ones unseen and the tour still starting. Write the step key directly, derived from the live catalogs so a step added later cannot leave this behind:

```dart
import 'package:scheduling/features/feature_tour/domain/tour_definitions.dart';
import 'package:scheduling/features/feature_tour/domain/tour_scope.dart';
import 'package:scheduling/features/feature_tour/domain/tour_step_id.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Marks every sheet walkthrough as already seen.
///
/// A sheet's tour gates on `ModalRoute.isCurrent`, which is true the moment a
/// test pumps the sheet — so on a fresh-install preferences store the tour
/// starts, and showcaseview's tooltip animation repeats forever, which makes
/// `pumpAndSettle` time out. A hub tab can't hit this (a standalone screen has
/// no `HubShellScope`, so it never starts).
///
/// Call this from any test that pumps `AddEventSheet`, `AddClientSheet`,
/// `InvitePersonSheet` or the job-details sheet and isn't testing the tour
/// itself. It represents someone who has already been through the
/// walkthrough, which is the ordinary case.
///
/// Derived from the live catalogs across BOTH roles, so a step added to a
/// sheet can't hang a suite that never mentions the tour.
///
/// Pass [extra] to keep other preferences the test relies on.
void markFormToursSeen({Map<String, Object> extra = const {}}) {
  final seen = <TourStepId>{
    for (final form in TourForm.values)
      for (final isAdmin in [true, false])
        ...tourStepsFor(FormTour(form), isAdmin: isAdmin),
  };
  SharedPreferences.setMockInitialValues({
    ...extra,
    'tour_seen_steps': [for (final id in seen) id.name],
  });
}
```

- [ ] **Step 2: Call it from the details-sheet tests**

Run: `grep -rln "EventDetailsSheet\|EventDetailsView\|showEventDetails" test/`

For each hit that does not already call `markFormToursSeen`, add `markFormToursSeen();` to its `setUp`. Where the test already seeds preferences of its own, pass them through as `extra:` rather than replacing the call.

- [ ] **Step 3: Update the tour rules**

`lib/features/feature_tour/CLAUDE.md` currently states that a PARTIAL start marks the whole scope seen and loses its dropped steps for good. That is no longer true and would mislead the next session. Edit that paragraph to keep the `ready:` guidance but drop the permanence claim, and add this near the seen-flags paragraph at the end:

```markdown
  **Seen flags are per STEP, not per scope** (`tour_seen_steps`, 2026-09-04).
  A release that adds a step to a screen someone already toured has to be able
  to show them that one step; the per-scope flag could not.
  `tour_seen_tabs` is now read exactly once, by the migration in
  `TourSeenController._load`, through the FROZEN `kLegacyTourSteps` snapshot in
  `domain/legacy_tour_steps.dart`. **Never add a new step id to that
  snapshot** — every id in it is marked seen on upgrade, so a new one there is
  a step no existing device will ever see. ABSENCE of `tour_seen_steps` is the
  migration marker, so `resetAll` writing an EMPTY list can't re-trigger it.
  `markSteps` records only the ids that actually RAN, which retires the
  partial-start bug: a step dropped because its target hadn't rendered stays
  unseen and is offered on a later visit, and zero rendered targets marks
  NOTHING at all. The `ready:` gate still matters — it stops a tour starting
  against a skeleton in the first place — but a partial start is no longer
  permanent. `markFormToursSeen()` derives its set from the live catalogs, so
  a new sheet step can't leave a suite hanging on `pumpAndSettle`.
```

Also change "the three create-flow sheets" to "the sheets" where the file enumerates `FormTour`, and add `sheet_jobDetails` to its list of form keys.

- [ ] **Step 4: Run the full suite**

Run: `flutter analyze`
Expected: `No issues found!` — the repo baseline, so any lint here is from this work.

Run: `flutter test`
Expected: PASS. Record the count. A `pumpAndSettle` timeout is almost always a sheet tour starting — go back to Step 2 and check that file's `setUp`.

- [ ] **Step 5: Commit**

```bash
git add test/ lib/features/feature_tour/CLAUDE.md
git commit -m "Cover the job-details tour in test support and update the tour rules"
```

---

### Task 10: Changelog

**Files:**
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Add the entry**

This ships with 1.57.0+86, whose section is already at the top of the file and not yet committed. Add to its `### Added`:

```markdown
- **The app tour covers the new features.** The walkthrough now points out the
  week view and the crew filter on the calendar, the location-sharing control
  in Settings, and — on the job itself — Start, the notes and photos the crew
  writes, the Undo on a job closed by mistake, Push back and Book again.
  Anyone who has already been through the tour sees only what is new to them,
  in place, rather than sitting through the whole thing again.
```

- [ ] **Step 2: Commit**

```bash
git add CHANGELOG.md
git commit -m "Note the tour update in the changelog"
```

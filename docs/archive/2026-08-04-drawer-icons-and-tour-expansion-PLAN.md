# Drawer icons + tour expansion — Implementation Plan

> **For agentic workers:** Steps use checkbox (`- [ ]`) syntax for tracking.
> Design spec: `docs/plans/2026-08-04-drawer-icons-and-tour-expansion.md`.

**Goal:** Put icons back on the nav drawer rows, and grow the feature tour from
14 screen-level steps to 43 — adding the two untoured screens and, crucially,
three walkthrough tours that live inside the create-flow modal sheets.

**Architecture:** The tour's key type changes from `AppDestination` to a sealed
`TourScope` (`DestinationTour` | `FormTour`), whose `storageKey` doubles as the
showcaseview scope name and the SharedPreferences entry. A destination's key
stays its bare `.name`, so no device loses a seen flag. A `ModalBottomSheetRoute`
is a `ModalRoute`, so form sheets reuse the existing route-visibility branch.

**Tech Stack:** Flutter 3.10.7, Riverpod 3, showcaseview 5.x, gen_l10n
(EN template + FR), flutter_test.

**Verification baseline:** `flutter analyze` must stay at `No issues found!`.

---

## File map

**Create**
- `lib/features/feature_tour/domain/tour_scope.dart` — the sealed key type
- `test/features/feature_tour/domain/tour_scope_test.dart`
- `test/features/navigation/drawer_catalog_test.dart`

**Modify — tour core**
- `lib/features/feature_tour/domain/tour_step_id.dart` — +29 ids
- `lib/features/feature_tour/domain/tour_definitions.dart` — switch on `TourScope`
- `lib/features/feature_tour/domain/tour_steps.dart` — `TourSteps(TourScope)`
- `lib/features/feature_tour/widgets/tour_showcase.dart` — `scope` field
- `lib/features/feature_tour/widgets/feature_tour_host.dart` — `scope` field
- `lib/features/feature_tour/widgets/tour_step_text.dart` — +29 cases
- `lib/features/feature_tour/application/tour_seen_store.dart` — `Set<TourScope>`

**Modify — drawer**
- `lib/features/navigation/domain/drawer_catalog.dart` — `drawerRowIcon`
- `lib/features/navigation/widgets/app_nav_drawer.dart` — tinted chip

**Modify — screens (call-site migration + new steps)**
- `lib/features/calendar/screens/main_calendar_screen.dart`
- `lib/features/clients/screens/clients_screen.dart`
- `lib/features/employees/screens/employees_screen.dart`
- `lib/features/clients/screens/history_screen.dart`
- `lib/features/presence/screens/live_map_screen.dart`
- `lib/features/settings/screens/settings_screen.dart`
- `lib/features/dashboard/screens/dashboard_screen.dart` — new host
- `lib/features/calendar/screens/day_route_screen.dart` — new host

**Modify — sheets (new hosts)**
- `lib/features/calendar/widgets/sheets/add_appointment_sheet.dart`
- `lib/features/clients/widgets/sheets/add_client_sheet.dart`
- `lib/features/employees/widgets/sheets/invite_person_sheet.dart`

**Modify — supporting widgets that must accept a tour wrap**
- `lib/features/clients/widgets/views/clients_list_view.dart`
- `lib/features/clients/widgets/views/appointment_history_view.dart`
- `lib/features/employees/widgets/views/*` (roster row wrap)
- `lib/features/calendar/widgets/sections/appointment_form_fields.dart`

**Modify — l10n**
- `lib/l10n/app_en.arb`, `lib/l10n/app_fr.arb` — 58 keys each

**Modify — tests**
- `test/features/feature_tour/domain/tour_definitions_test.dart`
- `test/features/feature_tour/application/tour_seen_store_test.dart`
- `test/features/feature_tour/widgets/feature_tour_host_test.dart`

---

## Task 1: `TourScope`

**Files:** Create `lib/features/feature_tour/domain/tour_scope.dart`,
`test/features/feature_tour/domain/tour_scope_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/core/navigation/app_destination.dart';
import 'package:scheduling/features/feature_tour/domain/tour_scope.dart';

void main() {
  test('a destination scope key is the bare destination name', () {
    // Load-bearing: existing devices persisted these names under
    // tour_seen_tabs, so changing the key would replay every tour.
    expect(const DestinationTour(HubTab.calendar).storageKey, 'calendar');
  });

  test('a form scope key is namespaced so it cannot collide', () {
    expect(
      const FormTour(TourForm.addAppointment).storageKey,
      'sheet_addAppointment',
    );
  });

  test('tourScopeByKey round-trips every scope', () {
    for (final scope in allTourScopes) {
      expect(tourScopeByKey(scope.storageKey), scope);
    }
    expect(tourScopeByKey('nope'), isNull);
  });

  test('scopes with the same key are equal and share a hash', () {
    expect(
      const DestinationTour(HubTab.calendar),
      const DestinationTour(HubTab.calendar),
    );
    expect({
      const DestinationTour(HubTab.calendar),
      const DestinationTour(HubTab.calendar),
    }, hasLength(1));
  });

  test('every scope key is unique', () {
    final keys = [for (final s in allTourScopes) s.storageKey];
    expect(keys.toSet().length, keys.length);
  });
}
```

- [ ] **Step 2: Run it and confirm it fails**

`flutter test test/features/feature_tour/domain/tour_scope_test.dart`
Expected: compile failure — `tour_scope.dart` does not exist.

- [ ] **Step 3: Implement**

```dart
import 'package:scheduling/core/navigation/app_destination.dart';

/// Anything that can own a feature tour. Sealed so [tourStepsFor] stays
/// exhaustive — a new scope is a compile error, not a silently tour-less
/// surface.
sealed class TourScope {
  const TourScope();

  /// The persisted SharedPreferences entry AND the showcaseview scope name.
  /// Load-bearing: a destination's key is its bare `.name`, which is what
  /// devices already have under `tour_seen_tabs`.
  String get storageKey;

  @override
  bool operator ==(Object other) =>
      other is TourScope && other.storageKey == storageKey;

  @override
  int get hashCode => storageKey.hashCode;
}

/// A whole screen — a hub tab or a pushed route.
class DestinationTour extends TourScope {
  const DestinationTour(this.destination);
  final AppDestination destination;

  @override
  String get storageKey => destination.name;
}

/// A create-flow modal sheet. `sheet_` namespaces it away from destinations.
class FormTour extends TourScope {
  const FormTour(this.form);
  final TourForm form;

  @override
  String get storageKey => 'sheet_${form.name}';
}

/// The create flows that carry a walkthrough. `.name` is persisted — renaming
/// a member replays or orphans that tour.
enum TourForm { addAppointment, addClient, invitePerson }

const List<TourScope> allTourScopes = [
  for (final d in allDestinations) DestinationTour(d),
  for (final f in TourForm.values) FormTour(f),
];

/// Resolves a persisted key, or null for one that no longer exists — so a
/// retired tour cannot resurrect itself.
TourScope? tourScopeByKey(String key) {
  for (final scope in allTourScopes) {
    if (scope.storageKey == key) return scope;
  }
  return null;
}
```

Note: `allTourScopes` uses collection-for over `allDestinations`, which is
`const`, so the list itself can stay `const`.

- [ ] **Step 4: Run the test — expect PASS.**
- [ ] **Step 5: Commit** — `feat(tour): add the sealed TourScope key type`

---

## Task 2: Migrate the seen store to `TourScope`

**Files:** Modify `lib/features/feature_tour/application/tour_seen_store.dart`,
`test/features/feature_tour/application/tour_seen_store_test.dart`

- [ ] **Step 1: Update the existing test** — replace `HubTab.calendar` with
  `const DestinationTour(HubTab.calendar)` throughout, and add:

```dart
test('a persisted destination name still loads after the scope change', () {
  SharedPreferences.setMockInitialValues({
    'tour_seen_tabs': ['calendar', 'settings'],
  });
  // ...container setup as in the sibling tests...
  await container.read(tourSeenProvider.notifier).ready;
  expect(container.read(tourSeenProvider), {
    const DestinationTour(HubTab.calendar),
    const DestinationTour(PushedDestination.settings),
  });
});

test('a form tour persists under its namespaced key', () async {
  final notifier = container.read(tourSeenProvider.notifier);
  await notifier.markSeen(const FormTour(TourForm.addAppointment));
  final prefs = await SharedPreferences.getInstance();
  expect(prefs.getStringList('tour_seen_tabs'), ['sheet_addAppointment']);
});
```

- [ ] **Step 2: Run — expect FAIL** (type mismatch).

- [ ] **Step 3: Implement.** In `tour_seen_store.dart`:
  - `Notifier<Set<AppDestination>>` -> `Notifier<Set<TourScope>>`
  - `_load`: `state = {for (final key in keys) ?tourScopeByKey(key)};`
  - `_save`: `[for (final scope in state) scope.storageKey]`
  - `markSeen(TourScope scope)`
  - drop the `app_destination.dart` import, add `tour_scope.dart`

  Keep the `_keyTourSeenTabs` constant name and value — the entry is unchanged.

- [ ] **Step 4: Run — expect PASS.**
- [ ] **Step 5: Commit** — `refactor(tour): key the seen store on TourScope`

---

## Task 3: Migrate the tour core + the six existing screens

Mechanical, one commit, because the type change does not compile until every
call site moves.

**Files:** `tour_definitions.dart`, `tour_steps.dart`, `tour_showcase.dart`,
`feature_tour_host.dart`, the six screens, `tour_definitions_test.dart`,
`feature_tour_host_test.dart`

- [ ] **Step 1: `tour_definitions.dart`** — delete `tourScopeName` (the
  `'tour_'` prefix is redundant now the key is already unique), and switch on
  the scope:

```dart
List<TourStepId> tourStepsFor(TourScope scope, {required bool isAdmin}) =>
    switch (scope) {
      DestinationTour(:final destination) =>
        _destinationSteps(destination, isAdmin: isAdmin),
      FormTour(:final form) => _formSteps(form, isAdmin: isAdmin),
    };
```

  `_destinationSteps` is the existing switch body verbatim; `_formSteps`
  returns `const []` for now (Tasks 9–11 fill it).

- [ ] **Step 2: `tour_steps.dart`** — `TourSteps(this.scope, {required bool isAdmin})`,
  field `final TourScope scope;`, and `step()` passes `scope:` to `TourShowcase`.

- [ ] **Step 3: `tour_showcase.dart`** — both `TourShowcase` and
  `TourShowcaseBar` swap `final AppDestination destination` for
  `final TourScope scope`, and `Showcase(scope: scope.storageKey, ...)`.

- [ ] **Step 4: `feature_tour_host.dart`** —
  - field `final TourScope scope;` replaces `destination`
  - `String get _scope => widget.scope.storageKey;`
  - `_markSeen()` passes `widget.scope`
  - `seen.contains(widget.scope)`
  - `_isVisible` and the `stillVisible` recheck both become:

```dart
bool _isVisible(BuildContext context) {
  switch (widget.scope) {
    case DestinationTour(destination: final HubTab tab):
      return HubShellScope.currentOf(context) == tab;
    case DestinationTour() || FormTour():
      // A pushed route and a modal sheet are both ModalRoutes — one branch.
      final route = ModalRoute.of(context);
      _route = route;
      return route?.isCurrent ?? false;
  }
}
```

- [ ] **Step 5: Migrate the six screens.** Each is one or two lines:
  `TourSteps(HubTab.calendar, ...)` -> `TourSteps(const DestinationTour(HubTab.calendar), ...)`,
  `FeatureTourHost(destination: ..., ...)` -> `scope: _tour.scope`,
  and any `TourShowcaseBar(destination: ...)` -> `scope: _tour.scope`.

- [ ] **Step 6: Update the two tour tests** to construct `DestinationTour(...)`.

- [ ] **Step 7: Verify**

```
flutter analyze
flutter test test/features/feature_tour/
```
Expected: `No issues found!` and all tour tests pass.

- [ ] **Step 8: Commit** — `refactor(tour): thread TourScope through host, steps and screens`

---

## Task 4: Drawer icons

**Files:** `drawer_catalog.dart`, `app_nav_drawer.dart`,
Create `test/features/navigation/drawer_catalog_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/core/navigation/app_destination.dart';
import 'package:scheduling/features/navigation/domain/drawer_catalog.dart';

void main() {
  test('every destination has an icon and a colour', () {
    for (final destination in allDestinations) {
      expect(drawerRowIcon(destination), isA<IconData>());
      expect(drawerDotColor(destination), isA<Color>());
    }
  });

  test('no two destinations share an icon', () {
    final icons = [for (final d in allDestinations) drawerRowIcon(d)];
    expect(icons.toSet().length, icons.length);
  });
}
```

- [ ] **Step 2: Run — expect FAIL** (`drawerRowIcon` undefined).

- [ ] **Step 3: Add `drawerRowIcon` to `drawer_catalog.dart`** exactly as in
  spec §1.1. The file currently imports `dart:ui show Color`; change to
  `package:flutter/widgets.dart` for `IconData` + `Icons` (`Icons` lives in
  `material.dart`, so import that).

- [ ] **Step 4: Run — expect PASS.**

- [ ] **Step 5: Swap the square for the chip** in `_NavRow.build`. Replace the
  existing `Container(width: 18, height: 18, ...)` with:

```dart
Builder(
  builder: (context) {
    final tint = crewColorOf(theme, drawerDotColor(destination).toARGB32());
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: tint.withValues(alpha: theme.cardStyle.iconChipAlpha),
        borderRadius: BorderRadius.circular(AppRadius.r8),
      ),
      child: Icon(drawerRowIcon(destination), size: 16, color: tint),
    );
  },
),
```

  (If a local is simpler than a `Builder` at that point in the tree, hoist
  `tint` to the top of `build` instead — `theme` is already in scope there.
  Prefer the local; the `Builder` above is only to show the two reads.)

- [ ] **Step 6: Scale sweep.** The row grew from 18px to 28px of leading chrome
  inside a 284px drawer, so run the drawer's existing widget test plus a
  260x640 / textScaler 2.0 pump and assert `tester.takeException()` is null.

```
flutter test test/features/navigation/
```

- [ ] **Step 7: Commit** — `feat(nav): restore drawer row icons as tinted chips`

---

## Task 5: The 29 new step ids and their text

Doing all the ids + ARB in one pass keeps EN and FR in lockstep and means every
later task only has to wire widgets.

**Files:** `tour_step_id.dart`, `tour_step_text.dart`, `app_en.arb`, `app_fr.arb`

- [ ] **Step 1: Add the ids** to `TourStepId`, grouped by scope in this order:

```
// dashboard
dashboardHero, dashboardUpcoming, dashboardWorkload, dashboardAttention,
// day route
dayRouteDaySwitcher, dayRouteEmployee, dayRouteStops, dayRouteNavigate,
// add appointment
apptTemplates, apptClient, apptCrew, apptSchedule, apptDetails, apptSave,
// add client
clientWho, clientReach, clientSite, clientSave,
// invite person
personDetails, personJobTitle, personColour, personAccess, personCreate,
// gap-fills
calendarCollapse, clientsFilter, clientsRow, employeesRow,
historyFilter, historyRow,
```

- [ ] **Step 2: Add 58 keys to `app_en.arb`**, each `tour_<id>Title` /
  `tour_<id>Desc` with a `@key` description block (`required-resource-attributes`
  fails the build on a bare key). Match the shipped voice: second person,
  one sentence, no trailing "!". Content requirements that are load-bearing
  rather than cosmetic:
  - `apptCrew` must say the assignees are **who can see the job**.
  - `apptSchedule` must say a multi-day job's times are a **daily window**,
    not one unbroken stretch.
  - `personJobTitle` must say the job title **grants no access**.
  - `personAccess` must name admin vs employee as the real permission switch.
  - `personCreate` must say the admin **hands the credentials over themselves**.

- [ ] **Step 3: Add the same 58 keys to `app_fr.arb`** with real French (no
  `@key` blocks — FR is not the template). Quebec French, `vous` form, matching
  the shipped tour strings' register.

- [ ] **Step 4: Add 29 cases to `tourStepText`.**

- [ ] **Step 5: Regenerate and verify no drift**

```
flutter gen-l10n
```
Then confirm `lib/l10n/.gen/untranslated.json` lists none of the new keys.
(A repo hook may already run `gen-l10n` on ARB edits — do not double-run.)

- [ ] **Step 6: Verify** — `flutter analyze` -> `No issues found!`
      (`tourStepText`'s switch is exhaustive, so a missed id fails to compile.)

- [ ] **Step 7: Commit** — `feat(tour): add 29 step ids with EN/FR text`

---

## Task 6: Dashboard tour

**Files:** `tour_definitions.dart`, `dashboard_screen.dart`,
`tour_definitions_test.dart`

- [ ] **Step 1: Catalog test first**

```dart
test('dashboard has an admin tour and none for employees', () {
  const scope = DestinationTour(PushedDestination.dashboard);
  expect(tourStepsFor(scope, isAdmin: true), hasLength(4));
  expect(tourStepsFor(scope, isAdmin: false), isEmpty);
});
```

- [ ] **Step 2: Run — expect FAIL** (currently `const []`).

- [ ] **Step 3: Fill the catalog** in `_destinationSteps`:

```dart
PushedDestination.dashboard => [
  if (isAdmin) ...[
    TourStepId.dashboardHero,
    TourStepId.dashboardUpcoming,
    TourStepId.dashboardWorkload,
    TourStepId.dashboardAttention,
  ],
],
```

- [ ] **Step 4: Run — expect PASS.**

- [ ] **Step 5: Wire the screen.** In `_DashboardScreenState`:
  - `late final _tour = TourSteps(const DestinationTour(PushedDestination.dashboard), isAdmin: widget.isAdmin);`
  - wrap the `Scaffold` in `FeatureTourHost(scope: _tour.scope, isAdmin: widget.isAdmin, stepKeys: _tour.keys, ready: stats is AsyncData, autoScroll: true, child: ...)`.
    `ready:` is load-bearing — an ungated start against `_LoadingList` finds
    zero targets and permanently marks the screen seen.
  - in `_StatsList`, wrap each of the four sections in `_tour.step(...)`,
    guarded by `_tour.has(id)`. `_StatsList` is a separate widget, so pass the
    `TourSteps` down as a field rather than reaching for an inherited widget.

- [ ] **Step 6: Verify** — `flutter analyze` and `flutter test test/features/feature_tour/`

- [ ] **Step 7: Commit** — `feat(tour): add the dashboard tour`

---

## Task 7: Day route tour

**Files:** `tour_definitions.dart`, `day_route_screen.dart`, `tour_definitions_test.dart`

- [ ] **Step 1: Catalog test**

```dart
test('day route tours both roles, with the picker admin-only', () {
  const scope = DestinationTour(PushedDestination.dayRoute);
  expect(tourStepsFor(scope, isAdmin: true), hasLength(4));
  final employee = tourStepsFor(scope, isAdmin: false);
  expect(employee, hasLength(3));
  expect(employee, isNot(contains(TourStepId.dayRouteEmployee)));
});
```

- [ ] **Step 2: Run — expect FAIL.**

- [ ] **Step 3: Fill the catalog**

```dart
PushedDestination.dayRoute => [
  TourStepId.dayRouteDaySwitcher,
  if (isAdmin) TourStepId.dayRouteEmployee,
  TourStepId.dayRouteStops,
  TourStepId.dayRouteNavigate,
],
```

- [ ] **Step 4: Run — expect PASS.**

- [ ] **Step 5: Wire the screen.** `_DayRouteScreenState` gets the `TourSteps`
  field and the host wraps the `Scaffold`, `ready: async is AsyncData`. Wrap
  `_daySwitcher()`, `_employeePicker(...)`, the `_timeline(...)` result and the
  `_routeButton(...)` result, each guarded by `_tour.has(id)`.

  The employee picker is already conditional on
  `widget.isAdmin && data.assigneeEntries.isNotEmpty`, so on a day with no
  assignees the target is absent and `isTargetRendered` skips that step. That
  is the intended behaviour — no extra guard.

- [ ] **Step 6: Verify** — `flutter analyze`, `flutter test test/features/feature_tour/`
- [ ] **Step 7: Commit** — `feat(tour): add the day route tour`

---

## Task 8: Gap-fill steps on the four existing screens

**Files:** `tour_definitions.dart`, `main_calendar_screen.dart`,
`clients_screen.dart`, `clients_list_view.dart`, `employees_screen.dart`,
`history_screen.dart`, `appointment_history_view.dart`, `tour_definitions_test.dart`

- [ ] **Step 1: Catalog test**

```dart
test('gap-filled catalogs grew to their new lengths', () {
  int len(AppDestination d) =>
      tourStepsFor(DestinationTour(d), isAdmin: true).length;
  expect(len(HubTab.calendar), 5);
  expect(len(HubTab.clients), 4);
  expect(len(HubTab.employees), 3);
  expect(len(PushedDestination.history), 3);
});
```

- [ ] **Step 2: Run — expect FAIL.**

- [ ] **Step 3: Extend the catalogs**
  - calendar: append `TourStepId.calendarCollapse` after `calendarDayList`
  - clients: `clientsSearch, clientsFilter, clientsAdd, clientsRow`
  - employees: `employeesSearch, employeesAdd, employeesRow`
  - history: `historySearch, historyFilter, historyRow`

- [ ] **Step 4: Run — expect PASS.**

- [ ] **Step 5: Wire the targets.**
  - `calendarCollapse` -> `_CollapseHandle` in `main_calendar_screen.dart`.
    Portrait only — `_splitCalendar` short-circuits the handle in landscape, so
    the step self-skips there via `isTargetRendered`.
  - `clientsFilter` -> `ClientTypeChips`.
  - `clientsRow` -> the **first** item in `ClientsListView`'s item builder
    (`if (index == 0 && wrap != null) wrap(tile)`). Pass an optional
    `Widget Function(Widget)? firstRowTourWrap` down from the screen, matching
    the `rosterTourWrap` pattern `live_map_screen.dart` already uses. Never
    wrap every row — the `GlobalKey` must be unique.
  - `employeesRow` -> first `EmployeeCard`, same first-index wrap.
  - `historyFilter` -> `HistoryFilterBar`; `historyRow` -> first result row,
    same first-index wrap.

- [ ] **Step 6: Verify** — `flutter analyze`, then the four screens' widget tests.
- [ ] **Step 7: Commit** — `feat(tour): fill the gaps on calendar, clients, team and history`

---

## Task 9: Add-appointment sheet tour

**Files:** `tour_definitions.dart`, `add_appointment_sheet.dart`,
`appointment_form_fields.dart`, `tour_definitions_test.dart`

- [ ] **Step 1: Catalog test**

```dart
test('the appointment form walkthrough is admin-only and 6 steps', () {
  const scope = FormTour(TourForm.addAppointment);
  expect(tourStepsFor(scope, isAdmin: true), [
    TourStepId.apptTemplates,
    TourStepId.apptClient,
    TourStepId.apptCrew,
    TourStepId.apptSchedule,
    TourStepId.apptDetails,
    TourStepId.apptSave,
  ]);
  expect(tourStepsFor(scope, isAdmin: false), isEmpty);
});
```

- [ ] **Step 2: Run — expect FAIL** (`_formSteps` returns `const []`).

- [ ] **Step 3: Fill `_formSteps`** for `TourForm.addAppointment`.

- [ ] **Step 4: Run — expect PASS.**

- [ ] **Step 5: Wire the sheet.**
  - `_AddEventSheetState` gets
    `late final _tour = TourSteps(const FormTour(TourForm.addAppointment), isAdmin: true);`
    (the sheet is only reachable from admin surfaces).
  - `build` returns
    `FeatureTourHost(scope: _tour.scope, isAdmin: true, stepKeys: _tour.keys, autoScroll: true, child: FormSheetFrame(...))`.
  - `AppointmentFormFields` gains an optional
    `Widget Function(TourStepId, Widget)? tourWrap` and applies it to the
    templates `Wrap`, the `ClientSearchField`, the `EmployeePicker`, the
    schedule `SheetPanel` and the details section. Null on the edit flow, which
    has no tour.
  - `apptSave` targets `FormSheetFrame`'s primary verb. `FormSheetFrame` gains
    an optional `Widget Function(Widget)? primaryTourWrap` for this.

- [ ] **Step 6: Unfocus before the tour starts.** In `FeatureTourHost._start`,
  immediately before `startShowCase`, add:

```dart
FocusManager.instance.primaryFocus?.unfocus();
```

  Without it an autofocused field's keyboard covers the lower half of every
  target. This is safe for the screen tours too — none of them autofocus.

- [ ] **Step 7: Verify** — `flutter analyze`, `flutter test test/features/feature_tour/`
- [ ] **Step 8: Commit** — `feat(tour): walk through creating an appointment`

---

## Task 10: Add-client sheet tour

**Files:** `tour_definitions.dart`, `add_client_sheet.dart`, `tour_definitions_test.dart`

- [ ] **Step 1: Catalog test**

```dart
test('the client form walkthrough is 4 steps', () {
  const scope = FormTour(TourForm.addClient);
  expect(tourStepsFor(scope, isAdmin: true), [
    TourStepId.clientWho,
    TourStepId.clientReach,
    TourStepId.clientSite,
    TourStepId.clientSave,
  ]);
});
```

- [ ] **Step 2: Run — expect FAIL.**
- [ ] **Step 3: Fill `_formSteps` for `TourForm.addClient`.**
- [ ] **Step 4: Run — expect PASS.**
- [ ] **Step 5: Wire the sheet** — host wraps `FormSheetFrame`,
      `autoScroll: true`; the three `MonoSectionLabel` sections and the primary
      verb each get a `_tour.step(...)` wrap.
- [ ] **Step 6: Verify** — `flutter analyze`, tour tests.
- [ ] **Step 7: Commit** — `feat(tour): walk through creating a client`

---

## Task 11: Invite-person sheet tour

**Files:** `tour_definitions.dart`, `invite_person_sheet.dart`, `tour_definitions_test.dart`

- [ ] **Step 1: Catalog test**

```dart
test('the invite walkthrough is 5 steps and separates title from access', () {
  const scope = FormTour(TourForm.invitePerson);
  final steps = tourStepsFor(scope, isAdmin: true);
  expect(steps, hasLength(5));
  // The two must be distinct steps: conflating job title with the access
  // role is the footgun this tour exists to prevent.
  expect(
    steps.indexOf(TourStepId.personJobTitle),
    lessThan(steps.indexOf(TourStepId.personAccess)),
  );
});
```

- [ ] **Step 2: Run — expect FAIL.**
- [ ] **Step 3: Fill `_formSteps` for `TourForm.invitePerson`.**
- [ ] **Step 4: Run — expect PASS.**
- [ ] **Step 5: Wire the sheet** — host wraps `FormSheetFrame`,
      `autoScroll: true`; wrap the four `MonoSectionLabel` sections
      (details / role / colour / access) and the primary verb.
- [ ] **Step 6: Verify** — `flutter analyze`, tour tests.
- [ ] **Step 7: Commit** — `feat(tour): walk through inviting a team member`

---

## Task 12: Final verification

- [ ] **Step 1:** `flutter analyze` -> `No issues found!`
- [ ] **Step 2:** `flutter test` -> full suite green (baseline 1547 passing).
- [ ] **Step 3:** Confirm `lib/l10n/.gen/untranslated.json` has no `tour_` keys.
- [ ] **Step 4:** BOM scan on every touched `.dart` file.
- [ ] **Step 5:** Update `docs/plans/2026-08-04-drawer-icons-and-tour-expansion.md`
      status to implemented, and add the tour/drawer notes to `CLAUDE.md`:
      the `TourScope` storage-key invariant (destination keys stay bare `.name`;
      renaming an enum member replays or orphans a tour) and the drawer's
      icon+colour pairing.
- [ ] **Step 6: Commit.**

---

## Self-review notes

- **Spec coverage:** §1 -> Task 4. §2.2/2.3 -> Tasks 1–2. §2.4/2.5.1 -> Task 3.
  §2.5.2 (keyboard) -> Task 9 Step 6. §2.5.3 is accepted behaviour, no task.
  §2.6 -> Tasks 9–11. §3.1 -> Tasks 6–7. §3.2 -> Tasks 9–11. §3.3 -> Task 8.
  §4 -> Task 5. §5 -> Tasks 1, 2, 4 and each catalog task, closed by Task 12.
- **Naming consistency:** `storageKey`, `tourScopeByKey`, `allTourScopes`,
  `TourSteps.scope`, `FeatureTourHost.scope` are used identically throughout.
- **Device-only:** none of this touches a method-channel plugin, so the harness
  covers it; the drawer chip still deserves an eyeball on device.

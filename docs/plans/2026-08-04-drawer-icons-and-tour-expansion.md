# Drawer icons + tour expansion

**Date:** 2026-08-04
**Branch:** `redesgin`
**Status:** approved design, not yet implemented

Two related pieces of navigation/onboarding work:

1. Put icons back on the nav drawer rows (P1 replaced the pre-redesign icons
   with bare colour squares).
2. Expand the feature tour from 14 screen-level steps to 43, covering the two
   untoured screens and — the point of the exercise — the three **create
   flows**, which live in modal sheets the tour system cannot currently reach.

---

## 1. Drawer icons

### 1.1 The catalog

`lib/features/navigation/domain/drawer_catalog.dart` gains one function beside
the existing `drawerDotColor`, with the same discipline: an exhaustive switch
over the sealed `AppDestination`, so a new destination is a compile error
rather than a silently icon-less row.

```dart
IconData drawerRowIcon(AppDestination destination) => switch (destination) {
  HubTab.calendar               => Icons.calendar_today_rounded,
  PushedDestination.dayRoute    => Icons.route_rounded,
  HubTab.liveMap                => Icons.map_rounded,
  HubTab.employees              => Icons.badge_rounded,
  HubTab.clients                => Icons.people_rounded,
  PushedDestination.dashboard   => Icons.insights_rounded,
  PushedDestination.history     => Icons.history_rounded,
  PushedDestination.settings    => Icons.settings_rounded,
};
```

Seven of the eight are the icons the deleted `settings_drawer.dart` used
(commit `3c9a3fb7^`), so this is a genuine re-add rather than a new vocabulary.
`dayRoute` is the exception — it had no row in the old drawer — and takes
`route_rounded`.

### 1.2 The row

`_NavRow` in `app_nav_drawer.dart` currently paints an 18x18 solid square. It
becomes a **28x28 tinted icon chip**:

- fill: the row colour at `theme.cardStyle.iconChipAlpha`
- radius: `AppRadius.r8`
- icon: 16px, in the row colour at full strength

The colour still resolves through `crewColorOf(theme, drawerDotColor(d).toARGB32())`
— that call is unchanged and stays the only place the stored hue is lifted for
dark. `drawerDotColor` keeps its name and its comment; only its consumer changes.

This is the tinted-icon-chip idiom `InfoCardRow` already ships (34x34 / `r8` /
18px icon / `iconChipAlpha`). It is deliberately reused rather than
re-derived — 28x28 rather than 34x34 because the drawer is 284px wide and the
row has a 48px minimum height to respect.

An active row keeps its `primaryContainer` background; the chip sits on top of
it unchanged.

### 1.3 Why this and not a plain coloured icon

The frontend rule says colour must never be the sole indicator of state. Today
the drawer's only per-row cue *is* colour. Adding the icon fixes that; keeping
the tint means the colour coding that the redesign introduced is not thrown
away.

---

## 2. Reaching a modal sheet with the tour

### 2.1 The blocker

`FeatureTourHost`, `tourScopeName`, `tourStepsFor` and `TourSeenController` are
all keyed on `AppDestination`. A create flow is a `showModalBottomSheet`, not a
destination, so "how do I create an appointment" is unreachable — which is why
every existing step is a *pointer* ("here is the + button") rather than a
*walkthrough*.

### 2.2 `TourScope`

Introduce a sealed key type in `lib/features/feature_tour/domain/tour_scope.dart`:

```dart
sealed class TourScope {
  const TourScope();
  /// The persisted SharedPreferences entry AND the showcaseview scope name.
  String get storageKey;
}

class DestinationTour extends TourScope {
  const DestinationTour(this.destination);
  final AppDestination destination;
  @override String get storageKey => destination.name;   // unchanged on purpose
}

class FormTour extends TourScope {
  const FormTour(this.form);
  final TourForm form;
  @override String get storageKey => 'sheet_${form.name}';
}

enum TourForm { addAppointment, addClient, invitePerson }
```

Both need value equality (`==`/`hashCode` on `storageKey`) because they are
stored in a `Set` and compared against `widget.scope`.

**No migration.** A destination's key stays the bare `.name` already written to
`tour_seen_tabs`, so every device keeps the tours it has already seen. `sheet_`
is a fresh namespace that cannot collide with a destination name. The
`.name` values remain load-bearing exactly as CLAUDE.md records — renaming an
enum member still replays or orphans a tour.

`tourScopeName(destination)` is replaced by `scope.storageKey`; the
`'tour_${...}'` prefix it added is dropped since the key is already unique, and
the scope name is not persisted anywhere.

### 2.3 Store changes

`TourSeenController` becomes `Notifier<Set<TourScope>>`:

- `_load` maps persisted strings through a new `tourScopeByKey(String)`, which
  returns null for an unknown key — the same drop-unknown-names behaviour
  `destinationByName` has today, so a retired tour cannot resurrect itself.
- `_save` writes `scope.storageKey`.
- `markSeen(TourScope)` / `resetAll()` are otherwise unchanged. Settings'
  **Replay app tour** already calls `resetAll`, so it re-arms the sheet tours
  with no new control.

### 2.4 Host changes

`FeatureTourHost` takes `required TourScope scope` in place of
`destination`, and `_isVisible` switches on it:

- `DestinationTour(HubTab)` -> `HubShellScope.currentOf(context) == tab`
- `DestinationTour(PushedDestination)` -> `ModalRoute.of(context)?.isCurrent`
- `FormTour` -> `ModalRoute.of(context)?.isCurrent`

A `ModalBottomSheetRoute` **is** a `ModalRoute`, so the sheet case reuses the
existing route branch verbatim — no third visibility mode, and
`_routeTransitionSettled()` already waits out the sheet's slide-in before
showcase measures anything.

`TourShowcase` / `TourShowcaseBar` swap their `destination` field for `scope`
and read `scope.storageKey`. `TourSteps` likewise.

### 2.5 Three mechanics the sheet hosts must get right

1. **Below-fold targets.** `FormSheetFrame` is a fixed-height sheet with a
   scrolling body, so the three form hosts pass `autoScroll: true` and inflate
   the scroll cache extent. This is the Settings precedent: a lazy list will not
   build off-screen rows, and `isTargetRendered` then silently drops those
   steps.
2. **The keyboard.** The host unfocuses (`FocusManager.instance.primaryFocus
   ?.unfocus()`) before `startShowCase`, or an autofocused field's keyboard
   covers the lower half of every target.
3. **Nested routes dismiss the tour.** Opening a date picker, an action sheet
   or the inline add-client sheet makes the form route non-current, and the
   host's existing dismiss-on-hidden path fires — which **marks the tour seen**
   (`onDismiss` -> `_onTourEnd` -> `_markSeen`). This is the same semantic a
   mid-tour tab switch already has, and it is deliberate: it means an
   interrupted tour does not nag on every subsequent open. Replay is the
   escape hatch. Accepted, not fixed.

### 2.6 Where each form host mounts

The host wraps the `FormSheetFrame` inside each sheet's `build`, so it is
within the sheet's own route:

| Form | File | Gate |
|---|---|---|
| `addAppointment` | `calendar/widgets/sheets/add_appointment_sheet.dart` | admin-only surface already |
| `addClient` | `clients/widgets/sheets/add_client_sheet.dart` | admin-only surface already |
| `invitePerson` | `employees/widgets/sheets/invite_person_sheet.dart` | admin-only surface already |

All three are reached only from admin surfaces, so their employee catalogs are
empty and the existing catalog-membership guard pattern applies unchanged.

---

## 3. Step catalog

14 steps today -> **43**. New ids are added to `TourStepId`, their text to
`tourStepText`, and their ordering to `tourStepsFor` (which now switches on
`TourScope`).

### 3.1 New tours — the two untoured screens

**Dashboard** (`PushedDestination.dashboard`, admin) — 4 steps:

| Step | Target |
|---|---|
| `dashboardHero` | `DashboardHero` — today at a glance |
| `dashboardUpcoming` | `UpcomingTodaySection` |
| `dashboardWorkload` | `EmployeeWorkloadSection` |
| `dashboardAttention` | `AttentionFlagsSection` — what needs a decision |

**Day route** (`PushedDestination.dayRoute`) — 4 steps:

| Step | Target |
|---|---|
| `dayRouteDaySwitcher` | `_daySwitcher` row |
| `dayRouteEmployee` | `_employeePicker` — admin-only, absent for employees and skipped by `isTargetRendered` |
| `dayRouteStops` | the stop timeline |
| `dayRouteNavigate` | the Navigate button in `bottomNavigationBar` |

Both screens need a `PrimaryScrollScope`-compatible host wrap and gate `ready:`
on their async data (`AsyncData`), per the LiveMap precedent — an ungated start
finds zero targets against a loading placeholder and permanently marks the
screen seen.

### 3.2 New tours — the three create flows

**Add appointment** (`TourForm.addAppointment`) — 6 steps, the actual answer to
"how do I create an appointment":

| Step | Target | Teaches |
|---|---|---|
| `apptTemplates` | the job-template chip row | one tap fills the title and duration |
| `apptClient` | `ClientSearchField` | who it is for; a client can be added inline |
| `apptCrew` | `EmployeePicker` | who does it **and who can see it** |
| `apptSchedule` | the schedule `SheetPanel` | all-day, dates, times, and that a multi-day job's times are a **daily window**, plus repeat |
| `apptDetails` | the details section | address, notes, materials, photos |
| `apptSave` | `FormSheetFrame`'s primary verb | |

**Add client** (`TourForm.addClient`) — 4 steps: `clientWho` /
`clientReach` / `clientSite` / `clientSave`, targeting the sheet's three
`MonoSectionLabel` sections and the frame's primary verb.

**Invite person** (`TourForm.invitePerson`) — 5 steps:

| Step | Target | Teaches |
|---|---|---|
| `personDetails` | details section | name, email (their sign-in identity), phone |
| `personJobTitle` | `JobTitleChips` | job title is what they do on site and **grants nothing** |
| `personColour` | colour section | this is the hue on their cards and calendar dots |
| `personAccess` | access section | admin vs employee is the real permission switch |
| `personCreate` | the primary verb | an account is created on the shared starting password and **you hand the credentials over yourself** |

The `jobTitle` vs `role` step is deliberate: CLAUDE.md flags conflating them as
a live footgun (picking "Dispatcher" must not read as granting admin), and the
form is the only place anyone meets both.

### 3.3 Gap-fills on existing screens — 6 steps

| Screen | New step | Target |
|---|---|---|
| Calendar | `calendarCollapse` | `_CollapseHandle` — portrait only; landscape has no handle, and `isTargetRendered` skips it |
| Clients | `clientsFilter` | `ClientTypeChips` |
| Clients | `clientsRow` | first `ClientTile` — tap for history, swipe to archive |
| Employees | `employeesRow` | first `EmployeeCard` — the jobs-today count |
| History | `historyFilter` | `HistoryFilterBar` |
| History | `historyRow` | first result row |

Every row-targeting step relies on `isTargetRendered` to skip itself on an
empty list. That is existing, tested behaviour (zero survivors -> mark seen,
never crash).

### 3.4 Resulting per-scope counts

| Scope | Before | After |
|---|---|---|
| Calendar | 4 | 5 |
| Clients | 2 | 4 |
| Employees | 2 | 3 |
| History | 1 | 3 |
| Live map | 2 | 2 |
| Settings | 3 | 3 |
| Dashboard | 0 | 4 |
| Day route | 0 | 4 |
| Add appointment | — | 6 |
| Add client | — | 4 |
| Invite person | — | 5 |
| **Total** | **14** | **43** |

---

## 4. Localization

29 new steps x 2 keys = **58 new keys**, added to `app_en.arb` and `app_fr.arb`
in lockstep, each with a `@key` metadata block in EN (`required-resource-attributes`
fails the build on a bare key). Naming follows the shipped `tour_` bucket:
`tour_<stepId>Title` / `tour_<stepId>Desc`.

French is written as part of this work, not deferred — the app is bilingual for
a Quebec business and EN text in `app_fr.arb` is a visible regression.
`flutter gen-l10n` regenerates; `lib/l10n/.gen/untranslated.json` must come
back empty for these keys.

---

## 5. Tests

- `test/features/feature_tour/domain/tour_definitions_test.dart` — extend to
  the new scopes; assert every `TourStepId` resolves text in EN and FR, and
  that no catalog contains a duplicate id.
- New: `TourScope` round-trip — `tourScopeByKey(scope.storageKey) == scope` for
  every scope, and that a destination's key is still its bare `.name` (the
  no-migration guarantee).
- `test/features/feature_tour/widgets/feature_tour_host_test.dart` — add the
  `FormTour` case: visible when its route is current, dismissed and marked seen
  when a route pushes above it.
- New: `drawer_catalog_test` — every destination in `allDestinations` resolves
  an icon and a colour (the sealed switch makes this a compile-time guarantee;
  the test guards against a future non-exhaustive refactor).
- Scale sweep at 260x640 / textScaler 2.0 on the drawer, per the harness rule —
  the row grew from 18px to 28px of leading chrome inside a 284px drawer.

---

## 6. Out of scope

- No "?" replay button in the form sheets — auto-start once per device is the
  agreed trigger, matching the screen tours. Settings' Replay covers re-running.
- No help/getting-started screen.
- No tour for the *edit* sheets (`details_edit_sheet`, `edit_client_sheet`,
  `edit_person_sheet`) — the create flows teach the same fields, and doubling
  the catalog to re-teach them is not worth 40 more ARB keys.
- `drawerDotColor` keeps its name and its "no coupling to `AppColors.crewPalette`"
  comment; this work does not renumber or re-source the hues.

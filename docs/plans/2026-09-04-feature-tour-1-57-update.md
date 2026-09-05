# Feature tour update for the 1.56/1.57 features

Status: design approved 2026-09-04. Not yet implemented.

## Problem

Two releases added user-visible surfaces that no tour reaches, and the tour has
no way to show a new step to a device that has already toured that screen.

Untoured features:

- The calendar's day/week agenda toggle and the crew filter (1.56).
- The whole job-details sheet: Start job, the field record (crew notes and
  photos), Push back, Book again (1.56), and Undo on mark-complete (1.57).
- The location-sharing control, and notifications having become opt-in (1.57).

Stale copy: `tour_settingsNotificationsDesc` reads as though push is already
on; `tour_clientsSearchDesc` and `tour_historySearchDesc` describe a search that
now runs against the whole database rather than a cached window.

Delivery gap: `tour_seen_tabs` holds one flag per SCOPE, so a device that has
seen the Calendar tour will never be shown a step added to it. Only the
Settings "Replay app tour" row resets that, and it replays everything.

## Design

### 1. Seen flags move from scope to step

`TourSeenController` state becomes `Set<TourStepId>`, persisted under a NEW
SharedPreferences key `tour_seen_steps`. `tour_seen_tabs` is left in place and
is read exactly once, by the migration below.

- `FeatureTourHost._start` filters the scope's catalog to the UNSEEN ids first,
  then through `isTargetRendered` as it does today.
- `_onTourEnd` marks seen only the ids that actually RAN. It no longer marks a
  scope. This retires the partial-start bug recorded in
  `lib/features/feature_tour/CLAUDE.md`, where a tour that dropped steps for a
  not-yet-rendered target still marked the whole scope seen and lost them for
  good.
- Zero rendered targets marks NOTHING seen and returns, so the scope retries on
  a later visit. This is required by the job-details sheet, whose targets depend
  on job status and viewer role: a technician opening a closed job must not burn
  the Start-job step.
- A scope whose catalog is empty for the viewer's role stays a no-op.

Migration, once per device: if `tour_seen_steps` is ABSENT, seed it from
`tour_seen_tabs` through a `const kLegacyTourSteps` snapshot mapping each 1.57
scope key to the step ids that scope carried at 1.57, taking the union across
roles — a device that saw the scope saw whatever that scope could show it.
Absence of the key is the migration marker, so `resetAll` writing an empty list
cannot re-trigger it.

`resetAll` clears the step set. The Settings "Replay app tour" row behaves as
before from the user's side.

### 2. New steps

| Scope | Step id | Target | Role |
|---|---|---|---|
| `calendar` | `calendarWeekToggle` | agenda mode toggle (`AgendaHeader.trailing`) | both |
| `calendar` | `calendarCrewFilter` | `CrewFilterButton` in the header | admin |
| `settings` | `settingsLocationSharing` | the location row inside `NotificationsSettingsCard` | both |
| `sheet_jobDetails` | `jobPushBack` | Push back, in `_ClientSection` | admin |
| `sheet_jobDetails` | `jobFieldRecord` | `DetailsFieldRecordView` | technician |
| `sheet_jobDetails` | `jobStart` | Start button in `DetailsActionBar` | both |
| `sheet_jobDetails` | `jobMarkDone` | Mark-done button; copy names the Undo | both |
| `sheet_jobDetails` | `jobBookAgain` | Book again button | admin |

Step order within the job-details catalog follows the sheet's visual order:
push back, field record, start, mark done, book again.

### 3. The new scope

`TourForm.jobDetails`, storage key `sheet_jobDetails`. `EventDetailsView` is
only ever presented through `showEventDetails` as a modal bottom sheet, so it
rides the existing `FormTour` visibility gate (`ModalRoute.of(context)?.isCurrent`)
with no new branch in `_isVisible`.

`TourForm`'s doc comment widens from "the create flows" to the sheets that carry
a walkthrough. The sealed family is NOT renamed: `FormTour`/`TourForm` type
names are free to change but member names are persisted, and `sheet_jobDetails`
already reads correctly.

`_formSteps` currently returns `const []` for every non-admin. That early return
moves inside the switch, because `jobDetails` is the first form scope with a
technician catalog.

### 4. Targets inside reusable widgets

Three targets sit inside widgets used outside any tour. Each takes an optional
`Widget Function(Widget)?` wrap callback defaulting to null (identity), the
pattern `ClientsListView` already uses so it can double as the booking flow's
client picker:

- `DetailsActionBar`: `wrapStart`, `wrapMarkDone`, `wrapBookAgain`.
- `NotificationsSettingsCard`: `wrapLocationSharing`.

Wraps are applied with `TourSteps.stepIf`, never `step`, so an absent id cannot
force-unwrap.

The settings card stays wrapped by `settingsNotifications` as a whole; the
location row is a second, nested target. Two steps over nested targets is fine —
they run sequentially.

### 5. Reworded steps

- `tour_settingsNotificationsDesc` — notifications arrive only after they are
  turned on here.
- `tour_clientsSearchDesc` and `tour_historySearchDesc` — the search covers
  every record, not a recent window.

### 6. Localization

Eight new steps produce 16 keys (`tour_<id>Title` / `tour_<id>Desc`) plus an
`@key` block each in `app_en.arb`, mirrored in `app_fr.arb` in lockstep. The
repo's ARB hook regenerates `lib/l10n/.gen/`; do not run `flutter gen-l10n`
by hand.

### 7. Tests

- `tour_definitions_test.dart` — the new scope, the role splits, and the
  existing pin of the employee-reachable destination set against the drawer.
- `tour_seen_store_test.dart` — migration from `tour_seen_tabs` (present,
  absent, and already-migrated), per-step marking, `resetAll` not
  re-triggering the migration.
- `feature_tour_host_test.dart` — only unseen steps start; a run marks only
  the ids that ran; zero rendered targets marks nothing.
- `test/support/tour_test_support.dart` — `markFormToursSeen()` covers
  `sheet_jobDetails`, and any widget test pumping the details sheet calls it,
  or showcaseview's repeating tooltip animation times out `pumpAndSettle`.

## Out of scope

Invoicing, any new tour surface beyond the job-details sheet, and any change to
the "Replay app tour" row's placement or wording.

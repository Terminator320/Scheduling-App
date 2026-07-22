# Feature Tour (showcaseview) — Design

**Date:** 2026-07-22
**Status:** Approved design, pre-implementation
**Package:** [showcaseview](https://pub.dev/packages/showcaseview) (pure Dart — no native code, so no SPM/CocoaPods concern; pin latest stable at implementation time)

## Goal

Short, role-aware, per-tab guided tours that show new users how the app works:
each hub tab highlights its key widgets one at a time with localized
title + description overlays. Auto-runs once per tab per device; replayable
from Settings.

## Decisions (from brainstorm)

| Question | Decision |
|---|---|
| Scope | Per-tab tours (Calendar, Clients, Employees, History, Live Map, Settings) |
| Roles | Role-aware — admin gets full script, employee gets a shorter one limited to what they can actually do |
| Trigger | Auto-start on first *visible* visit of each tab + a Settings "Replay app tour" row that resets all seen-flags |
| Persistence | SharedPreferences, one key per tab (`tour_seen_<tab>`), device-local; sign-out does NOT reset |
| Skip semantics | Finishing or skipping both mark the tab seen ("leave me alone") |

## UX behavior

- 3–6 steps per tab. Tap advances; Skip/dismiss ends the tour and marks seen.
- A tour only auto-starts when: the tab is the hub's **current** destination,
  its seen-flag is unset, and the tab's first data frame has settled (never
  showcase over a `SkeletonLoader`).
- Settings → "Replay app tour": resets all flags, pushes a success notice via
  `noticeServiceProvider`; each tab's tour then plays again on its next visit.

## Architecture

New feature folder `lib/features/feature_tour/`:

- **`domain/tour_definitions.dart`** — pure step catalogs:
  `tourStepsFor(tab, isAdmin)` returns an ordered list of step ids, each
  mapping to a target key id and ARB string keys. Plain-`test()`-testable, no
  Flutter/Firebase deps.
- **`application/tour_controller.dart`** — Riverpod layer owning:
  - seen-flags in SharedPreferences (await the prefs `ready` future before
    acting — mirror `liveActivityEnabledProvider`; an optimistic default must
    never auto-start a tour that was already seen);
  - the auto-start decision (visible + unseen + data settled);
  - `resetAll()` for the Settings replay row.
- **Per-tab wiring** — each tab screen wraps its body in `ShowCaseWidget` and
  attaches `Showcase(key:)` wrappers to its highlighted widgets. `GlobalKey`s
  live in the screen's State. Auto-start fires post-frame when the tab
  *becomes visible* (via `HubShellScope` current destination), not when built
  — hidden `IndexedStack` tabs must never start a tour.
- **Layout resilience** — before starting, drop any step whose target key has
  no mounted context (drawer hamburger vs. nav rail in split layout, FABs
  absent for employees). Never crash on a missing target; a tour with zero
  surviving steps just marks itself seen.

Rejected alternatives: one global `ShowCaseWidget` above `HubShell` (all tabs
stay mounted in the `IndexedStack`, so hidden tabs' targets pollute the scope
and offstage auto-start is a real failure mode); hand-rolled overlay (needless
rebuild of what the package does).

## Draft step catalogs (finalize wording at implementation)

- **Calendar** — admin: add-appointment FAB, today FAB, an appointment card
  (tap for details), view switching, nav (drawer/rail). Employee: your
  assigned jobs, appointment card → details + Mark as complete, today FAB.
- **Clients** — admin: search bar, add-client FAB, client card (details + job
  history). Employee: search, view-only card.
- **Employees** — admin: invite/add FAB, employee card, status chips.
  Employee: colleague contact info.
- **History** — search + how past visits are listed. (Both roles.)
- **Live Map** — admin only: staff markers, roster sheet, day-route entry.
- **Settings** — theme/text size, notifications row, app lock, and the
  "Replay app tour" row itself.

Steps only ever anchor to real widgets; no free-floating "did you know" steps.

## Localization & accessibility

- All step text via `gen_l10n`: new `tour_` key bucket, EN + FR in lockstep,
  `@key` metadata required (the ARB edit hook regenerates — don't run
  `flutter gen-l10n` manually).
- Animations collapse to instant when `MediaQuery.disableAnimationsOf(context)`
  is true (package duration knobs set to zero).
- Overlay text respects user text scale; no scale clamping.

## Testing

- Pure `test()`: step catalogs per (tab, role) — admin-only steps absent for
  employees; every step id maps to real ARB keys.
- Controller tests: fresh flag → auto-start eligible exactly once; skip marks
  seen; `resetAll()` re-enables; prefs `ready` awaited before any decision.
- Widget tests: replay row resets flags and pushes the notice
  (`SettingsScreen` harness: mock SharedPreferences + secure storage +
  `PackageInfo` + l10n delegates per testing rules).
- Overlay rendering + step targeting: device verification via `flutter run`.

## Out of scope

- No server/Firestore state — tours are purely device-local.
- No cross-tab "cinematic" tour, no analytics on tour completion.
- No changes to the existing pre-login `OnboardingGate` flow.

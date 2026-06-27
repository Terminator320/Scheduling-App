# Codebase Audit — 2026-06-27

Scope: whole repo (`lib/`, `functions/`, `firestore.rules`, `storage.rules`,
`test/`). Baseline: working tree on branch `moblie` (clean before this pass).

> **Follow-up implemented (same pass, after review):** S1 fixed, and all blue
> items I1–I4 done — see **"Follow-up: red + blue implemented"** below.
> Per user decision, **S2** (App Check) and **S3** (peer-PII) are kept as-is.
> Verification after follow-up: `flutter analyze` clean · `flutter test`
> **599/599** · functions lint clean.

## Summary
- Static layer was already clean: `flutter analyze` → **No issues found**,
  Functions ESLint clean, no unused files, no genuinely-unused dependencies
  (the 4 flagged deps — `freezed`, `build_runner`, `flutter_launcher_icons`,
  `firebase_performance` — are all codegen/native-init false positives).
- Five parallel deep-review angles (security, bugs, dead-code/conventions,
  performance, maintainability) found **no critical/high** security or bug
  issues — this is a heavily-hardened, multiply-audited codebase.
- Applied (in the diff, all behaviour-verified, **590/590 tests green**): **8**
  changes — 1 latent-bug fix, 1 logging-convention alignment across 4 classes,
  2 perf wins, 1 reuse cleanup, 2 new test files.
- Reported for your decision: **12** (⚠️ 1 pre-ship · 🔴 4 security · 🔵 5
  improvements · 🟡 2 convention + 1 l10n batch).
- Verification: `flutter analyze` **pass (No issues)** · `flutter test`
  **590/590** · functions untouched (ESLint already clean).

## Applied cleanups (review the diff — `git diff HEAD`)

| File | Change | Why |
|---|---|---|
| `details_view_body.dart` | `dart fix` removed redundant `destructive: true` | `showConfirmDialog`'s `destructive` defaults to `true` (`confirm_dialog.dart:12`) — **behaviour unchanged**, dialog stays destructive |
| `event_details_controller.dart` | `await _seedFuture` before save-validation + extracted `_resolveActiveEmployees()` | Fixes a seed race (below) and de-dups the two documented-coupled active-employee reads into one method |
| `image_storage_service.dart`, `appointment_image_upload_service.dart`, `firebase_clients_repository.dart`, `firebase_appointments_repository.dart` | `debugPrint` in catch blocks → injected `AppLogger.warn` (tags `IMG-UPLOAD`/`IMG-DEL`/`CLI-SEARCH`/`HIST-SEARCH`) | Per `.claude/rules/error-handling.md`: swallowed image/search errors now reach Crashlytics in release (they were invisible). Matches the `auth_service`/`wave_service` inject pattern. Dropped the now-unused `foundation` imports + a stray success-trace |
| `appointment_history_view.dart` | Day-header format via shared `DateUtilsHelper.formatDayHeader` (new); loaded-page fallback computed lazily | Stops re-parsing a `DateFormat` every keystroke **and** removes the threaded `dayFormat` param from 4 methods; the steady-state search `data` branch no longer runs a discarded `_applyFilters` pass |
| `clients_screen.dart`, `employees_screen.dart` | `ListenableBuilder(_searchController)` scoped to wrap only the `master` list | In split layout, typing no longer rebuilds the search-independent detail pane (~60–120 widgets) every keystroke |
| `maps_error_mapper_test.dart` (new) | 8 cases covering every code→failure mapping + cause passthrough | `MapsErrorMapper` was the only error-mapper with no test (auth/wave both have one) |
| `event_details_controller_test.dart` | +1 regression test for the seed race | Without the fix it returns `EventDetailsInvalid`; with it the active assignee is retained |

> The seed-race fix and the logging change alter behaviour; they were applied
> under your explicit "if you need a refactor you can do it" authorization, each
> with test coverage. Everything else is mechanical/behaviour-preserving.

### The seed race that was fixed (was bug B1)
`event_details_controller.dart` seeds `selectedEmployees` from an **async**
employee read started in `build()`. `save()` validated/resolved against that
selection. If a save fired before the seed settled (cold cache / authUid lag),
the selection was empty — and because `AppointmentFormValidator` *always*
requires ≥1 employee, the user got a spurious "employees required" error (and,
if they'd toggled the picker during the seed window, original active assignees
could be dropped — visibility keys on `employeeIds`). Fix: `await _seedFuture`
at the top of `save()` (near-free on the warm path).
**Residual (low):** the toggle-during-seed-window sub-case is still possible
because `_seedSelectedEmployees` only seeds when the selection is empty; a
complete fix would gate the picker on seed completion. Narrow enough to defer —
flagging for awareness.

## Follow-up: red + blue implemented

After the report, the actionable security finding and all the improvement items
were implemented (behaviour-verified, 599/599 tests green):

| Item | What was done |
|---|---|
| **S1** | `resolveMyInvite` now returns `{found: false}` for an unverified caller (`functions/account.js`) — closes the invite-metadata leak. `tryActivateInvitedEmployee` forces `getIdToken(true)` so the legitimate post-verification flow keeps working; +1 test. |
| **I1** | `main_calendar_screen.dart` build() (~205 lines) → extracted `_CalendarMonthBar` + `_TodayFab` widgets and hoisted the stream-listener / role-upgrade / month-picker closures into named methods. |
| **I2** | `event_details_controller.dart` (630 lines) → moved the series rewrite + apply-to-all mechanics into a new `AppointmentSeriesEditor` (`appointment_series_editor.dart`); the controller keeps orchestration. |
| **I3** | `details_view_body.dart` build() (~156 lines) → lifted the mark-done / cancel async handlers into `_onMarkDone` / `_onCancel`. |
| **I4** | Added tests: `photo_upload_notifier_test.dart` (4) and `app_lock_provider_test.dart` (4). |

**Kept as-is by decision:** S2 (App Check stays deferred to launch), S3 (peer-PII
read is intentional). **S4** remains a GCP billing-alert config task (durable
rate-limiting the hot autocomplete path would add cost per keystroke). **I5**
deliberately deferred (only 2 instances; forcing a shared base would over-abstract).

## ⚠️ Pre-ship checklist (act before release)
- [ ] **App Check is disabled on 5 callables** — `deleteAccount`
  (`functions/account.js:42`), `resolveMyInvite` (`account.js:151`),
  `waveBootstrap` (`wave/callables.js:100`), `waveGetConnection` (`:181`),
  `waveImportCustomers` (`:206`) all set `enforceAppCheck: false`. Each is still
  gated (`assertAdmin` / self-only re-auth / own-email) and durably
  rate-limited, so blast radius is bounded — but device attestation is off.
  Flip back to `enforceAppCheck: true` at store launch (Play Integrity). Tracked
  in memory; restated here so it isn't missed.

## 🔴 Security findings (review required)
### S1 — `resolveMyInvite` returns invite metadata without `email_verified` · low · high
- **Where:** `functions/account.js:157-181`
- **Risk:** The callable authorizes off `req.auth.token.email` but never checks
  `email_verified`. Firebase Auth lets anyone register with an arbitrary
  (unverified) email, so an attacker who guesses an invited employee's email can
  confirm the invite exists and read its `name`/`colorValue`/`role`. They
  **cannot** claim it — the Firestore self-activation rule (`firestore.rules:123`)
  gates on `email_verified == true` — so this is metadata disclosure only, and
  the app calls this pre-verification by design.
- **Fix:** Gate the *returned fields* (not the lookup) on
  `req.auth.token.email_verified`, or strip `name`/`colorValue` until verified.
  If the pre-verify call flow must stay, document as an accepted risk.

### S2 — App Check off on 5 callables · medium · high
See the Pre-ship checklist above. Reported here for completeness.

### S3 — Any signed-in user can read any active user's email/phone · low · high
- **Where:** `firestore.rules:82` (`isSignedIn() && resource.data.status == 'active'`)
- **Risk:** An employee can enumerate every active colleague's full `users`
  doc, including `email`/`phone`. The employee picker only needs name/color.
- **Note:** Flagged **intentional** in project memory ("employees seeing peers'
  email/phone is intentional, don't re-fix") — this is the open "S1 users-rule
  PII" decision. Surfaced per policy, not re-litigated.

### S4 — Places autocomplete rate limit is per-instance, not a hard cap · low · med
- **Where:** `functions/places.js:28-67` (in-memory `RATE_LIMIT_MAX = 20`/min,
  `maxInstances: 10` → ~200 billable calls/min/uid, resets on cold start)
- **Risk:** A looping authenticated client could exceed the intended per-user
  Maps-Platform spend. Code comment already calls for a GCP billing alert (the
  deferred "GCP budget" item). Cost-DoS consideration, not data exposure.

## 🔵 Areas to improve (review required — report-only, reshape code)
### I1 — `main_calendar_screen.dart` `build()` is ~205 lines · medium · high
- **Where:** `lib/features/calendar/screens/main_calendar_screen.dart:163-368`
- **Opportunity:** One `build()` mixes listener-wiring closures, the `AppBar.bottom`
  month/job-count row (~45 lines), and the body Stack + animated today-FAB
  (~50 lines). Most over-budget `build()` in the repo (>3× the ~60-line guide).
- **Suggested:** Extract `_CalendarMonthBar` and `_TodayFab` as private widgets;
  hoist the `onAsyncChange`/`upgradeIfAdmin` wiring into named methods (mirrors
  how `settings_screen.dart` decomposes its master).

### I2 — `event_details_controller.dart` is a 630-line god controller · medium · med
- **Where:** the whole file (largest hand-written file)
- **Opportunity:** One `Notifier` owns client loading, employee seeding, search,
  images, status, save, **series rewrite** (`_rewriteSeries` ~40 lines), **series
  propagation** (`_propagateToSeries` ~40 lines), delete, and orphan cleanup.
- **Suggested:** Move the two series operations into `event_series_helpers.dart`
  (or a small `AppointmentSeriesEditor`); the controller keeps orchestration.

### I3 — `details_view_body.dart` `build()` is ~156 lines · low-med · med
- **Where:** `lib/features/calendar/widgets/views/details_view_body.dart:40-196`
- **Opportunity:** The mark-done / cancel async callbacks (~30 lines) are inlined
  in an otherwise declarative tree.
- **Suggested:** Lift them into named `_onMarkDone`/`_onCancel` methods.

### I4 — Test-coverage gaps in two pure-Dart state holders · low · med
- **Where:** `photo_upload_notifier.dart` (the `reportFailure` no-op guard),
  `app_lock_provider.dart` (`AppLockController` swallows keystore errors → stays
  disabled). Both are Firebase-free and cheap to cover with plain `test()`.

### I5 — Add/Edit appointment controllers share ~6 near-identical methods · low · med
- **Where:** `add_event_controller.dart` ↔ `event_details_controller.dart`
  (`searchClients`/`toggleEmployee` byte-identical; others differ by 1–2 fields)
- **Note:** This is the known "dedup the appointment form" follow-up. Only **2**
  instances and the two states differ — per the project anti-defaults, do **not**
  force a shared base. If touched, the cheapest safe win is a shared free
  function for the identical `searchClients` body. Deliberately deferred.

## 🟡 Code-quality suggestions (optional — judgment calls, not auto-applied)
- **Off-token `BorderRadius`** with no clean `AppRadius` target (r4/r8/r12/r16/rFull):
  `circular(10)` in `address_autocomplete_field.dart:208`,
  `client_search_field.dart:83`, `photo_picker_section.dart:242,247,279`;
  `Radius.circular(20)` sheet-tops in `sheet_helpers.dart:18,35`,
  `cupertino_time_picker.dart:25`, `month_year_picker.dart:23`; `circular(24)`
  in `settings_drawer.dart:71`; `circular(6)` in `settings_tiles.dart:244`;
  `circular(14)` in `additional_contacts_section.dart:163`. Each needs a
  decision (add a token vs nearest-snap, which shifts visuals) — left as-is.
- **Off-token `EdgeInsets.all(14)`** in `additional_contacts_section.dart:57`
  and `text_size_view.dart:153` (14 is off the 4/8/12/16/24/32 scale). Low
  confidence — may be deliberate.

## 🟧 Orphaned-looking l10n keys (defer to a deliberate l10n pass — do NOT delete in a code sweep)
16 keys in `lib/l10n/app_en.arb` with zero `context.l10n.<key>` call sites
(verified per-key; gen_l10n has no dynamic key access, so these are reachable
only if added back). The `error_couldNot*` / `error_somethingWentWrong*` family
was superseded by the `composeErrorNotice(intro:, tag:, error:)` system.

| ARB line | key |
|---|---|
| 159 | `calendar_today` |
| 305 | `error_couldNotDeleteClientTryAgain` |
| 309 | `error_couldNotSaveChangesTryAgain` |
| 313 | `error_couldNotAddClientTryAgain` |
| 521 | `error_somethingWentWrongCreatingTheAppointment` |
| 525 | `error_somethingWentWrongSavingChanges` |
| 553 | `calendar_noNumber` |
| 561 | `calendar_noNotes` |
| 565 | `calendar_noMaterials` |
| 661 | `calendar_selectAnAppointmentToViewDetails` |
| 737 | `error_couldNotCreateEmployee` |
| 885 | `error_couldNotLoadAppointments` |
| 1001 | `common_searchAddress` |
| 1005 | `common_typeToSearchAnAddress` |
| 1009 | `common_street` |
| 1347 | `error_couldNotDeleteAccount` |

> **Stale doc note:** `CLAUDE.md` still tells contributors to reuse
> `couldNotAddClientTryAgain` / `couldNotSaveChangesTryAgain` before adding new
> failure strings — but those keys are now orphaned (the project moved to
> `composeErrorNotice`). Update that guidance when these keys are pruned in
> lockstep across both ARBs (then `flutter gen-l10n`).

## Notes / uncertainties
- Generated files (`*.g.dart`, `*.freezed.dart`, `lib/l10n/.gen/**`) excluded.
- The `_allowedStatuses` allowlist duplicated in repo + `firestore.rules`, the
  `businessName` back-compat reads, and the `.where()` clauses mirroring rule
  constraints are **intentional load-bearing invariants** — left untouched.
- `/simplify` ran over the applied diff (4 cleanup angles). One reuse finding was
  actioned (the `DateUtilsHelper` consolidation above); one micro-opt skipped
  (memoizing the resolved-employee future to avoid a rare cold-path double read —
  it would subtly stale the active set vs. re-reading at save time).

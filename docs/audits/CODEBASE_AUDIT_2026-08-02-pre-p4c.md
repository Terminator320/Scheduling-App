# Codebase Audit — 2026-08-02

Scope: whole repo (`lib/`, `functions/`, `firestore.rules`, `storage.rules`,
`test/`). Baseline: working tree on `redesgin` at the 1.39.0+64 release cut
(uncommitted — the release edits and the emergency-contact move share the tree,
so `git diff` mixes them; this audit's own changes are itemized below).

Deep-reviewed by 5 parallel agents: security, bugs, dead-code/convention,
performance, maintainability.

## Summary
- Scanned: ~530 Dart files, 30 `functions/` modules, both rules files.
- **Auto-fixed (safe, in the diff): 3** — deleted one confirmed orphan file,
  swapped the last raw `CircularProgressIndicator` for `AdaptiveProgressIndicator`,
  shape-locked the new `private/emergency` rule.
- **Fixed beyond auto-fix: 3 defects** the audit found in code written the same
  day (the emergency-contact move). Not "safe mechanical" fixes, but regressions
  in unshipped work — repaired rather than filed.
- **Reported for your decision: 22** (⚠️ 1 pre-ship · 🔴 2 security · 🟠 0 bugs ·
  🔵 19 improvements)
- Verification: `flutter analyze` **0 issues** · `flutter test` **1493 passed** ·
  `functions` eslint **clean** · jest **715 passed** · `firestore.rules`
  validates (only the 3 documented `isAvailabilityOnlyChange` warnings).

## Auto-applied cleanups (review the diff)

| File | Change | Why |
|---|---|---|
| `lib/features/clients/widgets/sections/client_personal_fields_section.dart` | Deleted (121 lines) | Confirmed orphan — zero inbound imports, zero references to `ClientPersonalFieldsSection`. Its doc comment claims both client sheets use it; P3 rebuilt both and left it behind. |
| `lib/features/settings/screens/my_details_screen.dart:142,167` | `CircularProgressIndicator` → `AdaptiveProgressIndicator` | The only raw spinner left in `lib/`; `frontend.md` names `AdaptiveProgressIndicator` as the single busy-spinner seam. Rendered Material on iOS where every sibling renders Cupertino. |
| `firestore.rules` (`match /private/emergency`) | Doc id pinned + `hasOnly` key set + type/length caps | See S1 — the rule as first written was unshaped. |

### Defects fixed (same-day regressions, not auto-fix)

| File | Defect | Fix |
|---|---|---|
| `lib/features/employees/widgets/sheets/edit_person_sheet.dart` | **Data loss.** The emergency fields seed asynchronously from `users/{id}/private/emergency`, but `_save` always wrote them. Saving before the read landed merged two empty strings over a stored contact and destroyed it. Reachable on a phone: `employees_screen` awaits the detail sheet to close before opening Edit, so the autoDispose provider is disposed and the edit sheet always subscribes cold. | Write the emergency doc only once a snapshot has arrived (`emergency: null` otherwise); let a fresher snapshot re-seed until the admin types; show a `WarningNote` on read failure instead of blank editable fields. Two regression tests added. |
| same | A still-loading read and a failed read both rendered as "none on file" — the exact rendering the invariant forbids, and what made the above invisible to the admin. | Fields `readOnly` until loaded; failure shows `employees_emergencyLoadFailed`. |
| `lib/features/settings/screens/my_details_screen.dart` | `activeUserIdentityProvider` awaits a `retryAsync`'d read (500 ms + 1500 ms) and `build` read `.value`, so the loading window rendered a full-screen "Something went wrong" and built the drawer with the employee nav for an admin. | Switch on the `AsyncValue`; reserve the error text for a settled null identity. |

Also added: a `saveEmergencyContact` repository test pinning the
`users/{id}/private/emergency` path and its exact 3-key payload shape.

> Everything below this line was **not** changed.

## ⚠️ Pre-ship checklist (act before release)

- [ ] **`firestore.rules` `allow delete` on `/clients` is LIVE in production.**
  `kShowTestingDeleteClient` (`lib/core/testing_flags.dart`) is `kDebugMode`, but
  rules are not build-aware, so the rule is open regardless of build. Any
  authenticated admin session can delete a client doc, which detaches that
  client's whole appointment history (`clientId` gone, denormalized `clientName`
  kept). Remove the flag AND the rule together — checklist in
  `docs/plans/redesign-subdocs/2026-08-01-p3-HANDOFF.md` §5b (grep `#pre-ship`).
  Requires a rules deploy.

## 🔴 Security findings

### S1 — `users/{id}/private/{doc}` write was completely unshaped · high · high — **FIXED**
- **Where:** `firestore.rules`, the `match /private/...` block added today.
- **Risk:** As first written the rule pinned nothing — not the doc id, not the
  key set, not types or lengths. Any active employee could write unlimited
  arbitrary documents under `users/{ownDocId}/private/*`, ~1 MiB each: an
  authenticated storage/billing abuse vector, plus attacker-controlled content
  that an admin's `EmergencyContact.fromMap` renders back. Every sibling
  self-writable subcollection (`fcmTokens`, `liveActivityTokens`, `presence`)
  already uses `hasOnly([...])` + type caps; this one didn't.
- **Fix:** Applied — doc id pinned to `emergency`,
  `hasOnly(['contact','phone','updatedAt'])`, 200/40-char caps mirroring
  `isValidUserData`. **Needs a rules deploy to take effect.**

### S2 — the emergency-contact move leaves pre-move values peer-readable · medium · high — **OPEN by your decision**
- **Where:** `firestore.rules:196-199` (caps still permit the keys) +
  `firestore.rules:115` (read clause 2) +
  `lib/features/employees/data/firebase_employees_repository.dart:237-238`.
- **Risk:** You chose scrub-on-save over a backfill, which is sound given P4 was
  never deployed. But the scrub is *opportunistic*: it fires only when an admin
  opens that specific person's sheet and saves. `deactivateEmployee` /
  `reactivateEmployee` do partial updates that leave the fields, and
  `redeemSignupCode`'s activation patch never touches them. Any doc written by a
  pre-move build keeps broadcasting a third party's name and phone to every
  active employee until someone re-saves that person.
- **Fix when you want it closed:** a one-off Admin-SDK pass copying the pair into
  the subcollection and `FieldValue.delete()`-ing it from the parent, then
  tighten the rule to reject the keys outright. **Order matters** — denying the
  keys *first* would make `deactivateEmployee` fail `permission-denied` on any
  doc still carrying them, because a partial update still presents them in
  `request.resource.data`.
- **Realistically:** if no TestFlight tester ever entered an emergency contact
  there is nothing to scrub and this is already closed. One console query on
  `users` settles it.

### S3 — `/appointments` has no data-shape validation · medium · medium-high
- **Where:** `firestore.rules:357-378`, versus `isValidClientData` and
  `isValidUserData`, which both cap types and lengths.
- **Risk:** Appointment create/update validate only `status`. `employeeIds`,
  `clientId`, `seriesId`, `title` and `address` are unconstrained. A compromised
  admin session writing `employeeIds: ["a/b"]` makes `sendToEmployee`'s
  `db.collection("users").doc(id)` throw **synchronously**
  (`functions/notification_utils.js:340`), and the poisoned doc persists after
  the session is revoked, breaking that sweep path. Same class the new
  `clientIdOf` slash-guard in `client_job_count.js` defends against — but only
  that one call site was hardened.
- **Fix:** add `isValidAppointmentData()` mirroring `isValidClientData` —
  `employeeIds is list && size() <= 30`, `clientId`/`seriesId` string ≤128 with
  no `/`, plus length caps on `title`/`address`/`notes`/`clientName`. Requires a
  rules deploy.

## 🟠 Bug findings

**None open.** The three defects the bug review found were all in the same-day
emergency-contact work and are fixed above. Everything else flagged as
suspicious turned out to be documented and deliberate.

Two doc-vs-code drifts worth reconciling (not defects):
- `lib/features/employees/widgets/views/employee_details_view.dart:50` — the
  comment says a read error "renders the same as none on file", the direct
  opposite of the CLAUDE.md invariant. Harmless today (Team is admin-only and
  admins always pass the rule) but it will mislead anyone reusing this view.
- `lib/features/calendar/application/event_details_controller.dart:128` uses a
  bare `watchEmployees().first`, while CLAUDE.md specifies "cached
  `employeesStreamProvider` value, falling back to a fresh
  `watchEmployees().first`". No reachable failure found (an empty first snapshot
  needs the offline path, and `save()` fails fast offline). Reconcile code or
  doc in one direction.

## 🔵 Areas to improve

### I1 — `DateFormat` constructed per calendar day cell · high · high
`calendar_month_grid.dart:263` builds a fresh `DateFormat.yMMMMEEEEd(locale)`
**per in-month cell** (28–31 per grid) just for a semantics label.
`CalendarMonthPager` keeps cached neighbours, so 1–3 grids' worth per rebuild —
and `MainCalendar` rebuilds on every day tap, appointments emission, collapse
flip and month swipe. Roughly 30–90 locale-verification + pattern-parse cycles on
exactly the frames already doing 42-cell layout. Same bug in
`calendar_week_strip.dart:116` (7×) and `:61`; and `month_grid.dart:67` rebuilds
a `DateFormat` just to read its symbols — three lines below a comment explaining
that its sibling is memoized *for that reason*.
**Fix:** per-locale `static final Map<String, DateFormat>`, the pattern already
used in `date_utils_helper.dart` and `_weekStartCache`. **Do this one first.**

### I2 — Team tab holds two concurrent `users` listeners · medium · high
`employees_screen.dart:199` watches `employeesStreamProvider` **only** to choose
the skeleton/error branch, while every row comes from `allUsersStreamProvider`
via `filteredEmployeesProvider`. Both are non-autoDispose, so opening Team pins a
second live `users` query for the session. Also a correctness smell: the spinner
is gated on a query that isn't supplying the data, and `watchEmployees()`
excludes the invited/disabled rows the list actually shows.
**Fix:** gate loading/error on `allUsersStreamProvider`; drop the other watch.

### I3 — feature-tour scaffolding copy-pasted into 6 screens · high · high
`_tourSteps` + `_tourKeys` + `_tourStep` appear verbatim in
`main_calendar_screen` (67–73, 275–287), `clients_screen` (45–64),
`employees_screen` (52–72), `live_map_screen` (103–123), `settings_screen`
(85–100), `history_screen` (36–42). ~110 duplicated lines that **must** stay in
sync: `_tourKeys[id]!` force-unwraps and `index: _tourSteps.indexOf(id)` feeds
the "step N of M" chrome. Settings has already drifted (drops
`targetBorderRadius`). Adding a step for a screen whose copy diverged crashes on
the `!`.
**Fix:** one `TourSteps(destination, isAdmin:)` value class exposing `keys`,
`ids`, `step(...)`. Six copies → one, no new layer.

### I4 — the edit save path's all-day span is unpinned · high · high
`appointmentSpan` / `allDaySpan` (`appointment_form_validator.dart:101,112`) have
no direct unit test, and only the **add** path is covered end-to-end
(`add_event_controller_test.dart:304`). `event_details_controller_test.dart:244`
asserts only the `isAllDay` state flag, never the saved record's instants. The
whole point of the invariant is that the two save paths agree — only one is
pinned, so an edit-path regression ships silently.
**Fix:** a direct unit test plus one assertion that an all-day edit writes
midnight → 23:59.

### I5 — offline fail-fast block copy-pasted 6 times · medium · high
Identical ~12-line block in `pending_invite_tile.dart:73,121`,
`edit_person_sheet.dart:218`, `invite_person_sheet.dart:116`,
`my_details_screen.dart:77`, `settings_screen.dart:415` — differing only in
`intro`/`tag`. This is the widget half of a documented invariant, and the tag
must match the `logger.warn` label at the same site.
**Fix:** `bool guardedOffline(context, ref, {required intro, required tag})`
beside `composeErrorNotice`. (The two `accept_invite_*` screens use a different
banner shape and should stay out.)

### I6 — `ClientFormController` write paths have no reentrancy guard · medium · medium-high
`client_form_controller.dart:55,80` set `state = true` before the first await
(invariant satisfied) but lack the `if (state) return;` bail that
`AddEventController.submit` and `EventDetailsController.save` both carry. The
button only disables on the next frame, and `add_client_sheet` has **two** entry
points into the same unguarded write (the frame primary and "Add and book a
job") — a double-hit before rebuild creates two client docs.
`EmployeeFormController._save` has the same shape; `pending_invite_tile`
compensates at the call site, the two person sheets don't.
**Fix:** one line at the top of each.

### I7 — appointments range streams have no `.limit()` · medium (scaling) · high
`firebase_appointments_repository.dart:274,394`. All three `users` streams are
bounded at 500 explicitly so "a runaway collection can't stream an unbounded
snapshot"; the appointments collection — the one that actually grows without
limit — has no ceiling. `forCalendar` spans ~58 days; at 15 jobs/day that is
~870 docs per month paged, with a fresh listener on every month change outside
the 3-min grace.
**Fix:** a `.limit()` matching the `_historySearchScanLimit` convention **plus a
visible signal when it is hit** — a design change, not a drop-in, since a silent
cap would show a prefix of the month's jobs.

### I8 — sequential per-employee awaits in two sweeps · medium · high
`functions/notification_utils.js:894-916` (`runDailyDigest`) and `:846-868`
(overdue) do ~3 sequential round-trips per employee inside a serial loop.
`travel_utils.js:541` already batches the equivalent with `Promise.all`. At 30
employees that is ~7.5 s of billed wall-clock vs ~0.5 s; the real risk is the
60 s timeout as headcount grows.
**Fix:** `Promise.all` over the grouped keys; the shared `cache` Map is safe
under concurrency (single-threaded; worst case a duplicated read).

### I9 — `buildWaveIdIndex` reads full client docs for two fields · low · high
`functions/wave/customers.js:619` — `db.collection("clients").get()` transfers
and parses every client's full payload to read `waveCustomerId` + `createdAt`.
Billed reads are unchanged (Firestore bills per doc), but at ~650 clients that is
a few MB and a few hundred ms per import that could be a few hundred KB.
**Fix:** `.select("waveCustomerId", "createdAt")` — one line, same Map shape.

### I10 — long `build()` methods over the ~60-line guideline · medium · high
Each has its extraction seam already named by a `MonoSectionLabel` or an existing
branch, so these are mechanical:
`edit_client_sheet.dart:230` (188 lines) · `edit_person_sheet.dart:330` (186) ·
`accept_invite_details_screen.dart:269` (138) · `employee_details_view.dart:43`
(139 of a 199-line file) · `add_client_sheet.dart:182` (152) ·
`main_calendar_screen.dart:535` `_content` (117, splits at `if (_splitCalendar)`) ·
`settings_screen.dart:173` `_buildMaster` (92) · plus `client_view_body.dart:33`
(127), `weekly_bar_chart.dart:38` (124), `client_search_field.dart:40` (123),
`pending_invite_tile.dart:195` (78).

### I11 — `main.dart` (571 lines) carries untestable teardown glue · medium · high
`_handleAccountDisabled` + its three `ref.listen` wirings (lines 392–503, ~112
lines) is ordered de-registration (push → presence → live-activity → signOut →
post-frame nav) with a subtle `_isHandlingAccountExit` guard and a `finally`
reset — and no test, because it is a private `State` method on the app root.
`DeepLinkDispatcher` and `AppSyncListeners` are the established precedent for
pulling this out.
**Fix:** move it beside `AppSyncListeners`, taking the navigator key and a
`signOut` callback. Leave the tap-routing block where it is.

### I12 — repository query constraints unpinned · medium · high
`watchEmployees` / `watchAssignableUsers`
(`firebase_employees_repository.dart:45-77`) carry `where` + `limit(500)`
constraints that only the **retry** behaviour is tested for. Per the project's
own "query rules vs get rules" invariant, dropping a `status` constraint doesn't
return extra rows — Firestore rejects the whole query, surfacing as an empty
employee picker.
**Fix:** three short `verify(() => collection.where('status', isEqualTo: 'active'))`
assertions against the mocks already in that file.

### I13 — six `functions/` modules export names nobody imports · low · high
`travel_utils.js:673-678` (6 constants), `live_activity_utils.js:258-260`
(`toMillis` re-export duplicating `time_utils`, documented as the single owner of
instant handling), `notification_utils.js:923,936,937,939`,
`apns_client.js:377-383`, `bridge.js:247-248`, `client_propagation.js:217`.
Two notes: `sendToEmployee`'s comment says it is exported "so it's unit-testable"
but no test imports it; and `scripts/backfill.js:28` defines its own private copy
of `shouldHaveBridge` rather than importing the export — a real duplication risk.
**Fix:** either add the promised tests or drop the export entries.

### I14 — 21 orphaned l10n ARB keys · low · high — **report-only**
No `l10n.<key>` reference anywhere. Mostly the pre-P4 employee edit/detail
vocabulary (11 `employees_*` keys) orphaned when P4 split the invite and edit
sheets, plus `calendar_saveAppointment`/`clients_saveClient` displaced by
`FormSheetFrame`'s verb bar. **`nav_myDetails` is live scaffolding, not dead** —
`drawer_catalog.dart:36` reserves it for P5 and the screen now exists. Per
`project-map.md`, defer to a deliberate l10n pass; each key has a `@key` block
and an `app_fr.arb` twin to remove in lockstep.

### I15 — raw spacing literals off the `AppSpacing` scale · low · medium
13/15/18/25 px recur consistently across the P1/P2 redesign widgets
(`app_nav_drawer.dart:68,73,130,234,322`, `agenda_sliver_list.dart:109`,
`calendar_header_block.dart:73`, `calendar_month_grid.dart:18`,
`key_value_panel.dart:82`, `sheet_field_row.dart:51`, `app_header_pair.dart:54`,
`appointment_form_fields.dart:472`). These read as real design-spec values, not
accidents — `sheet_field_row` and `key_value_panel` sharing `15/13` is evidence a
token is warranted. Not auto-fixable: none maps cleanly to an existing token.
**Fix:** either add the redesign's real scale to `AppSpacing`, or round and
accept a 1–2 px shift.

### I16 — `drawer_catalog.dart:56-67` comment contradicts its code · low · medium
Eight hardcoded `Color(0xFF..)` sit under a doc comment instructing callers to
resolve them through `crewColorOf`. The values aren't in `AppColors.crewPalette`,
so a caller obeying the comment gets the generic HSL lift rather than the tuned
per-theme map. Either the comment is stale or the hues belong in the palette.

### I17 — `dashboard_hero.dart:24` hardcoded overdue hue · low · medium
`_overdueSegment = Color(0xFFF54A00)` while its four neighbours read
`statusColors`/`scheme` tokens, so only overdue doesn't shift in dark mode. The
comment acknowledges this and leans on the legend text (which does satisfy
"colour is never the sole indicator").
**Fix:** add an `overdue` field to `AppStatusColors`, or accept as documented.

### I18 — `_validate(String composedName)` ignores its parameter · low · high
`edit_person_sheet.dart:154` — dead parameter left behind when validation moved
to first/last names.

### I19 — `notifications.js` / `maintenance.js` have no direct tests · low · high
181 and 158 lines, but both are pure `onSchedule`/`onDocumentWritten` trigger
wiring whose logic is already extracted and tested elsewhere. Listed for
completeness; low payoff.

## Verified clean (recorded so a future pass doesn't re-litigate)

- **App Check** activated in `main()` with PlayIntegrity/AppAttest in release,
  Debug providers only under `kDebugMode`. All 11 callables set
  `enforceAppCheck: true`, including the unauthenticated `previewInvite`.
- **Callable guard order** correct on every callable: auth → `assertAdmin` →
  payload validation → rate limit → work.
- **Signup code as credential**: never logged, persisted, or interpolated into a
  notice; the clipboard copy is the only egress; server stores sha256 only.
- **Role never cached** — `AuthCache` holds uid/docId/colour/name only, and the
  warm-cache splash path hardcodes `isAdmin: false` (fails closed).
- **No UTF-8 BOMs** anywhere in `lib/`, `test/`, `functions/`.
- **Every raw `Stream.listen()` passes `onError`** (8 sites, all with a tagged
  `logger.warn`).
- **`ScaffoldMessenger.showSnackBar`**: exactly the 3 sanctioned sites, all built
  through `errorSnackBar(...)`.
- **No `FirebaseFirestore.instance` in UI**; no `throw Exception(...)`; no catch
  block that surfaces a notice without logging.
- **No `isDark`/brightness branching for styling** — the 5 hits are the
  sanctioned effective-brightness resolver, mode-selection UI, and the
  `AnnotatedRegion` surface-colour read.
- **No disposal leaks** — every `Debouncer`, `Timer`, `StreamSubscription` and
  `ScrollController` in `lib/` has a matching teardown.
- **All 96 Riverpod providers have a real watcher**; no dead route names; no
  genuinely unused pubspec dependency (`google_maps_flutter_ios_sdk9` is the
  SPM-only native map pin — removing it breaks the iOS map build;
  `build_runner`/`freezed` are live codegen; `flutter_launcher_icons` has an
  active config block).
- **All 5 FAB hero tags unique.**
- **`functions/` test coverage is strong** — 30 test files against 30 modules.

---

## Implementation status — "Do all" (same session)

Implemented **everything except the pre-ship item**. Final state:
`flutter analyze` **0 issues** · `flutter test` **1493** · jest **715** ·
eslint clean · rules validate.

| Item | Outcome |
|---|---|
| S2 | `functions/scripts/backfill-emergency.js` added (idempotent, `--dry-run`). The keys are now denied on `/users` **create**; the **update** denial waits for the backfill, since a partial update presents untouched fields and would break `deactivateEmployee`. |
| S3 | `isValidAppointmentData()` + `isValidDocIdField()` added; wired into create and the ADMIN update branch only, so an employee's status flip still works on a legacy doc. `isBoundedString` hoisted to the top level to be shared. |
| I1 | `DateFormat` memoized per locale (`longDateFormatFor`, `weekdayAbbrevFormatFor`, `_symbolsFormat`); 3 call sites routed through it. |
| I2 | Team tab gates on `allUsersStreamProvider` — the second `users` listener is gone. |
| I3 | `TourSteps` value class; 6 copies → 1. |
| I4 | 4 span unit tests + the missing edit-path assertion (all-day edit writes midnight → 23:59). |
| I5 | `guardedOffline` helper; 6 sites routed through it. |
| I6 | Reentrancy guards on `ClientFormController.addClient`/`updateClient` and `EmployeeFormController._save`. |
| I7 | `_rangeStreamLimit` (1000) on both range streams, with a warn when a snapshot hits the cap. |
| I8 | Both sweeps now `Promise.all` per employee/pair. |
| I9 | `.select("waveCustomerId","createdAt")`. |
| I10 | `build()` extracted in 6 files: edit_client 188→17, edit_person 186→20, add_client 152→17, settings `_buildMaster` 92→25, main_calendar `_content` split at the layout branch, employee_details + client_view_body partly reduced. |
| I11 | `AccountExitListeners` extracted; `main.dart` 571→467. |
| I12 | 3 query-constraint tests (where + limit) for the three `users` streams. |
| I13 | Unused exports dropped from 6 modules. |
| I14 | 22 orphaned ARB keys removed in EN/FR lockstep. `nav_myDetails` **kept** — documented P5 scaffolding. |
| I19 | `notifications.test.js` added, pinning the APNs secret-binding split. `maintenance.js` **cannot** be required in jest (verified: "Missing bucket name"), and its logic is already covered via `image_magic.js`. |

**Not implemented, with reasons:**
- **I15 (raw spacing)** — needs a design decision. The 13/15/18/25 values recur
  consistently and read as real spec values; rounding them to existing tokens
  would shift the shipped design 1–2px without sign-off, and inventing
  `sp13`/`sp15`/`sp18` just relocates the magic numbers. Owner call.
- **I16 (drawer dot colours)** — **false positive.** All eight values ARE in
  `AppColors.crewPalette` and the one call site does wrap in `crewColorOf`. The
  comment is accurate; nothing to fix.
- **I10 tail** — `weekly_bar_chart` (123) and `client_search_field` (122) still
  exceed the guideline, as do `employee_details_view` (114) and
  `client_view_body` (100) after partial extraction. Lowest-value tail.
- **Pre-ship** — untouched by design. The client-delete removal is a launch-time
  switch, and removing it now would take away the test-data cleanup you are
  presumably still using.

**Regression caught during implementation:** the first pass at I13 removed
`MAX_LEAD_MINUTES` from inside `Math.min(...)` rather than from `module.exports`,
silently disabling the 90-minute travel-lead cap. `travel_utils.test.js` caught
it. Restored and re-verified.

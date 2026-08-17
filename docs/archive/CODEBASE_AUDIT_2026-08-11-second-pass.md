# Codebase Audit — 2026-08-11 (second pass)

> **STATUS: implemented same day**, on the owner's "do all findings" instruction.
> Verification after the pass: `flutter analyze` → No issues found ·
> `flutter test` **1906 passing** · `functions npm run lint` clean ·
> `jest` **901 passing** (up from 1897 / 882).
>
> **UPDATE 2026-08-11 (later the same day): everything deferred here has now
> been closed except I10, which stays declined.** S2 (the deploy) RAN, so S1's
> DST fix is live. The remaining 6 test gaps (C3, C4, C6, C8, C9, C10) are
> written, and all three I6 refactors are done. Only S3 (**false finding**,
> verified no change needed) and I10 (the fix is worse than the finding) were
> never actioned. Details in "What was not done" at the bottom, which now
> records what changed.

Scope: whole repo (`lib/`, `functions/`, `firestore.rules`, `storage.rules`,
`firestore.indexes.json`, `lib/l10n/*.arb`, `pubspec.yaml`, `functions/package.json`).
Baseline: working tree at `55ea3cb3` on `redesgin`, tree clean at start.

This is the second pass of the day. The first pass (archived as
`docs/archive/CODEBASE_AUDIT_2026-08-11-first-pass.md`, baseline `8bf07c6e`) was implemented
in `a90474cc`; two commits have landed since — `84a1bf6f` (P7 dashboard +
History restyle + the rules span bound) and `55ea3cb3` (personal jobs keep an
address). Both are unreviewed, and most of what follows is in them.

## Summary

- Scanned: 366 `lib/` Dart files, 34 `functions/` modules, both rules files,
  706×2 ARB keys, 12 indexes + 12 field overrides.
- **Auto-fixed (safe, in the diff): 2** — two comments left factually false by
  the last two commits. Nothing else at the static level was fixable: the
  analyzer is `No issues found!`, `dart fix` has nothing, functions ESLint is
  clean, there are no orphaned files, and all four unused-dependency hits are
  verified false positives.
- **Reported for your decision: 31** (⚠️ 1 pre-deploy · 🔴 5 security ·
  🟠 13 bugs · 🔵 12 improvements) + 6 optional code-quality notes.
- Verification: `flutter analyze` → **No issues found!** (unchanged from
  baseline) · targeted tests green · functions ESLint clean.

## Auto-applied cleanups (review the diff)

| File:line | Change | Why |
|---|---|---|
| `lib/features/calendar/domain/policies/appointment_form_validator.dart:49` | `isAllDay` doc: "Only reachable on a personal job" → offered on every job, defaulted on for an untimed personal block | Stale since the 2026-08-03 owner call that put all-day on every job. In a repo where comments carry the spec, a false one is a trap |
| `lib/features/calendar/widgets/views/details_edit_body.dart:110` | Dropped "and address" from the mid-life-conversion comment | `55ea3cb3` stopped wiping the address; the comment still claimed it did |

> Full detail is in `git diff`. Nothing below this line was auto-changed.
> `docs/audits/CODEBASE_AUDIT.md` was moved to
> `CODEBASE_AUDIT_2026-08-11-first-pass.md` to keep the earlier pass — which
> the 2026-08-11 docs sweep then filed under `docs/archive/` with the rest of
> the superseded snapshots.

## ⚠️ Pre-deploy checklist

There are **zero** `TODO(pre-ship)` markers left anywhere in `lib/` or
`functions/` — verified, along with zero `TODO`/`FIXME`/`HACK`/`XXX`/`TEMP`.
No destructive testing scaffolding survives. One release-gating item remains:

- [x] **The backend is still not deployed, and it now carries three passes of
  security work.** `a90474cc` (S1 `assertFreshReauth` on `changeEmployeeEmail`'s
  SELF branch, budget 20/h → 5/h; B4 multi-day Live Activity skip; B5 crew
  colour) and `84a1bf6f` (the `isValidAppointmentSpan` rules bound) are both
  local-only. Until they deploy, a self sign-in-email change is protected **only**
  by `SelfEmailService`'s client-side re-auth ordering — a direct callable
  invocation with a valid ID token bypasses it, which is the account-takeover
  primitive that gate was written for. **Fix S1 below before deploying**, since
  the same deploy ships the flawed span bound. Runbook: `docs/DEPLOYMENT.md`.

## 🔴 Security findings (review required)

### S1 — the new span bound is an absolute duration, but the app's cap is wall-clock calendar days · severity: medium · confidence: high
- **Where:** `firestore.rules:468` (`isValidAppointmentSpan`)
- **Risk:** Not an exploit — a **denial of a legitimate write**, in the pending
  deploy. The rule bounds `d.endTime - d.startTime <= duration.value(14, 'd')`
  (exactly 1 209 600 s), while the client cap is a calendar-day count and the
  instants are composed from **local wall clock** (`combineDateAndTime` →
  `DateTime(y, m, d, h, m)`). I traced the widest saveable run: with equal
  start/end times `isOvernightWindow` is true, so `appointmentSpan` rolls the end
  onto the next day, storing **exactly 14 days**. Any such run whose window
  contains the November DST fall-back gains an hour → `14d 1h` → `allow create`
  denies it. A 14-day **all-day** block goes `13d 23h 59m` → `14d 0h 59m` and is
  denied too. The form has already validated, so the admin gets an opaque
  `permission-denied` on a booking the product explicitly allows, for roughly a
  two-week window each autumn. `appointmentSpanNotWidened()` does not help on
  create.
- **Fix:** bound at `duration.value(14, 'd') + duration.value(2, 'h')` (one DST
  hour plus the all-day minute of headroom) and correct both the rules comment
  and the matching CLAUDE.md line, which currently state the arithmetic that is
  wrong. `_clampedDayCount` remains the real enforcement. Do this **before** the
  deploy above.
- **Note:** two reviewers disagreed here — the bug reviewer concluded the bound
  "cannot reject a legal save". That holds only in the absence of a DST
  transition; I verified the arithmetic directly.

### S2 — production is running without the newest server-side controls · severity: medium · confidence: high on code, medium on prod state
- **Where:** `functions/employee_accounts.js:434-442`, `firestore.rules`
- **Risk:** see the pre-deploy item above. Cannot inspect prod from here.
- **Fix:** `firebase deploy --only functions,firestore:rules` (never `--force`).

### S3 — `waveBootstrap` is the only admin callable making an external credentialed call with no rate limit · severity: low · confidence: high
- **Where:** `functions/wave/callables.js:127-136`
- **Risk:** auth, `assertAdmin`, App Check and `assertPayloadShape` are all
  present, and the already-connected path short-circuits — but a compromised
  admin session can loop `listBusinesses` against Wave unbounded with the
  Secret-Manager token. Every sibling callable is capped.
- **Fix:** `enforceDurableRateLimit` (e.g. 10/h per uid) after payload validation.

### S4 — employees' personal-appointment addresses now reach the admin's App Group snapshot · severity: low · confidence: medium (privacy-scope owner call)
- **Where:** `lib/features/siri/domain/schedule_snapshot.dart:43`
- **Risk:** `55ea3cb3` changed personal jobs from `address: ''` to a real
  address. The Siri snapshot is business-wide for admins and the App Group
  payload stays readable **while the device is locked** — which is exactly why
  `functions/CLAUDE.md` deliberately excludes notes, phone and pictures from it.
  An admin's locked phone now holds the location of every employee's private
  appointment (clinic, school). Not a rules hole; an admin can already read the
  doc in-app.
- **Fix:** either omit `address` for `isPersonal` records in
  `buildScheduleSnapshot`, or record the accepted residual in the Siri bullet.

### S5 — fail-open `isAdmin` default on the dashboard route · severity: low · confidence: high
- **Where:** `lib/routes/app_routes.dart:64` — `isAdmin: args?.isAdmin ?? true`
- **Risk:** unreachable today (every caller passes `DashboardArgs`), but this
  flag flows into the dashboard cards' `showActions`, the one gate CLAUDE.md says
  must never regain a `true` default — a default of `true` previously showed
  employees Edit/Cancel/Delete affordances the rules then rejected. A bare
  `pushNamed(dashboard)` would re-open it.
- **Fix:** `?? false`, and drop the comment defending the direction.

## 🟠 Bug findings (review required)

### B1 — flipping Personal ON carries the selected client's street address onto the block, from off-screen · severity: medium-high · confidence: high
- **Where:** `lib/features/calendar/widgets/sections/appointment_form_fields.dart:199` (`_setPersonal`)
- **Problem:** `55ea3cb3` removed `controllers.address.clear()` from
  `_setPersonal`, on the stated grounds that the field "stays on screen … so
  whatever it holds is visible and editable rather than stale". That is not true
  in the add flow: the switch is at `:275` (first row of WHO) and the address
  field at `:493` (DETAILS), with the whole SCHEDULE section between them — I
  verified the ordering. Meanwhile `_selectClient:181` has already written the
  client's address into that controller, and `setPersonal` nulls
  `selectedClient`, so nothing on screen links the two any more.
  Repro: pick client "Marchetti" (address auto-fills) → realise it's a dentist
  appointment → flip Personal ON → Save. Stored: `isPersonal: true,
  clientId: '', address: "<Marchetti's street>"`. That address is **not
  cosmetic** — a timed personal job is a travel candidate by design, so the crew
  is pushed a `leaveNow` with a drive time to the wrong place, the Live Activity
  Directions button opens it, and the job joins the day-route stop list.
- **Fix:** clear the address in `_setPersonal(true)` **only when
  `selectedClient != null`** — i.e. when the text came from `_selectClient` /
  `_useClientAddress` — leaving a hand-typed address alone. That keeps the new
  invariant without restoring the blanket clear.

### B2 — a Firestore error blanks the home widget and makes Siri say "no appointments" · severity: medium-high · confidence: high
- **Where:** `lib/core/app/app_sync_listeners.dart:76-84` and `:96-101`; feeders
  `lib/features/siri/application/schedule_snapshot_provider.dart:14-18`,
  `lib/features/home_widget/application/widget_sync_service.dart:208-214`
- **Problem:** both listeners branch on `next.value == null` alone. An
  `AsyncError` has `value == null`, and so does `AsyncLoading` — so a failed read
  is indistinguishable from **signed out**, and the listener calls `clear()` /
  `clearSnapshot()`. The providers make it worse: they test `isLoading` then
  `value == null`, so an identity read error returns settled `AsyncData(null)`.
  `appts.whenData(...)` correctly preserves the error, but the listener discards
  the distinction. Result: three Firestore failures past `retryAsync` wipe the
  Home-screen widget and have Siri answer "no appointments" for someone who has
  jobs — on two off-screen surfaces, with nothing reporting it.
- **Fix:** gate both listeners with `if (next.isLoading || next.hasError) return;`
  (one file, covers both), and propagate `hasError` as `AsyncValue.error` in the
  two providers rather than collapsing it to `AsyncData(null)`.

### B3 — three action-sheet pickers invoke their callback with no `context.mounted` guard · severity: medium · confidence: high
- **Where:** `lib/features/settings/widgets/sections/my_scheduling_section.dart:77`,
  `lib/features/clients/widgets/sections/history_filter_bar.dart:174`,
  `lib/features/calendar/widgets/fields/repeat_interval_picker.dart:44`
- **Problem:** all three are `StatelessWidget`s that `await
  showAdaptiveActionSheet(...)` then call the parent callback checking only for
  null. The guard was skipped exactly where `mounted` isn't in scope — every
  Stateful caller does guard (`day_route_screen.dart:340`,
  `edit_person_sheet.dart:227`, `wave_settings_section.dart:131`), as do
  `email_compose_launcher` and `address_map_launcher`. Traced the worst path:
  `my_scheduling_section._pick` → `_saveMaxJobs` (`my_details_screen.dart:275`),
  which immediately reads `context.l10n`, calls `guardedOffline(context, …)` and
  `setState`. Popping the screen with the sheet open is setState-after-dispose →
  `FlutterError.onError` → recorded as a **FATAL** by this app's handler.
- **Fix:** `if (picked == null || !context.mounted) return;` at all three.

### B4 — the terminal-status vocabulary is spelled 4× in `functions/`, and two copies have drifted · severity: low · confidence: high
- **Where:** `functions/travel_utils.js:149` and
  `functions/widget_payload_utils.js:28` (both correct, 3 values) vs
  `functions/maintenance_policy.js:28` (`["done","cancelled"]`) and
  `functions/notification_utils.js:237` (`statusOf(after) === "done"`)
- **Problem:** the two divergent copies both omit the legacy `completed` alias.
  Consequences, and note these are **milder than they first look** — I checked
  the reachability: the app cannot write `completed` (`storedRaw` maps it to the
  4-value allowlist and the rules reject it), so only a console or Admin-SDK
  write reaches these paths. Given such a doc: (a) `endCardOnTerminal` never
  ends the Live Activity card on a flip to `completed`; (b) a `completed` doc
  older than the 2-year retention is **never purged** — a retention gap, not
  data loss, and its images are still referenced by the surviving doc, so
  nothing orphans. Dart fixed this exact drift on 2026-08-08 with
  `terminalStatusRawValues`; JS never got an owner.
- **Fix:** put `TERMINAL_STATUSES` in `functions/time_utils.js` (the existing
  shared-constant home, already the mirror anchor for
  `MAX_APPOINTMENT_SPAN_DAYS`) and derive all four sites from it.

### B5 — `on AuthFailure catch` during account deletion logs nothing at all · severity: medium (observability) · confidence: high
- **Where:** `lib/features/settings/screens/settings_screen.dart:445`
- **Problem:** the typed branch does `setState` + `notices.error(...)` + `return`
  with no `logger.warn`, no `logger.authFailure`, no stack trace — while the
  generic `catch` two lines below correctly logs `ACCT-DEL`. It is one of only
  two unlogged catch blocks among 136 in `lib/` (the other is the sanctioned
  `writeWidgetPayloadJson`). It also catches `AuthFailurePermissionDenied` and
  `AuthFailureUnknown`, which `isExpected` buckets **false** — precisely the ones
  meant to file a record. And it fires *after* push, presence and Live Activity
  have already been de-registered (`:439-443`), so a half-torn-down account
  leaves no trace. `logger` is already in scope at `:435`.
- **Fix:** `on AuthFailure catch (e, st)` +
  `logger.authFailure('ACCT-DEL settings.delete_account', e, e, st)` before the
  `mounted` guard. Also update `.claude/rules/error-handling.md`, which still
  says there are **four** auth catch sites — this is the fifth.

### B6 — three providers mask stream errors as "no work" · severity: medium · confidence: high
- **Where:** `lib/features/employees/application/employee_schedule_providers.dart:34`
  and `:98`; `lib/features/settings/application/my_details_providers.dart:100`
- **Problem:** `.value ?? const []` on the appointments range stream makes an
  error indistinguishable from an empty day, unlogged. The roster reads "0 jobs
  today", the employee TODAY panel reads empty, and the availability-conflict
  warning never fires. `emergencyContactProvider`, 20 lines below in the same
  file, does it correctly and its doc comment names the rule being broken here.
  The first pass fixed the role-branch on these providers but left the mask.
- **Fix:** copy the `emergencyContactProvider` pattern — log once in the
  provider, propagate the error.

### B7 — `functions/bridge.js` role validation short-circuits on a missing role · severity: low-medium · confidence: medium-high
- **Where:** `functions/bridge.js:147` — `if (after && after.role && !VALID_ROLES.has(after.role))`
- **Problem:** `after.role &&` means a doc with **no** `role` skips validation and
  reaches `bridgeBody` (`:30-36`), which writes `role: data.role`
  unconditionally. `initializeApp()` sets no `ignoreUndefinedProperties`
  (`index.js:6`), so admin Firestore throws — uncaught, inside a `retry: true`
  trigger. The `usersByUid` bridge is then never written, and **every rules gate
  that resolves through it fails for that person**. Needs a console/Admin-SDK
  write to reach. This is `.claude/rules/security.md`'s own fail-closed rule,
  broken by the one guard that doesn't follow it.
- **Fix:** drop `after.role &&`; add `VALID_ROLES.has(data.role)` to
  `shouldHaveBridge`.

### B8 — raw `'cancelled'` comparisons bypass the owner that lowercases · severity: low · confidence: high
- **Where:** `lib/features/employees/application/employee_schedule_providers.dart:37` and `:101`
- **Problem:** the only raw `'cancelled'` comparisons left in `lib/`, against
  P7's `isCancelledStatusRaw` — whose own file header says a second literal "is
  the exact drift this module exists to end". The owner lowercases; these don't.
  A console-written `'Cancelled'` counts as live load on the Team roster and
  lists in the TODAY panel while History's tally excludes it: two surfaces
  disagreeing with no error. (`firebase_appointments_repository.dart:277` is a
  legitimate exact-match write-path variant — leave it.)
- **Fix:** route both through `isCancelledStatusRaw`.

### B9 — `fetchClientsCreatedSince` truncates from the wrong end · severity: low · confidence: high on code, low on reachability
- **Where:** `lib/features/clients/data/firebase_clients_repository.dart:141`
- **Problem:** `orderBy('createdAt')` is **ascending** under `limit(1000)`, so
  past 1000 clients created inside the dashboard's 49-day window the query keeps
  the *oldest* 1000 and drops the newest — while `newClientsProvider` sorts
  descending and the section renders "newest first" plus a total. Same silent-
  prefix failure that got the Year period dropped, but nothing warns here.
  Unreachable at today's client count.
- **Fix:** `orderBy('createdAt', descending: true)` — the same single-field index
  serves both directions.

### B10 — `_when` is the one day-scoping consumer that doesn't clamp to the 14-day cap · severity: low · confidence: high
- **Where:** `functions/notification_messages.js:102-109`
- **Problem:** uses `lastWorkDayMs(c)` raw where every other answer routes
  through a clamp. A doc written past the cap by the console or Admin SDK (both
  bypass the new `isValidAppointmentSpan`) renders a push reading
  "Wed, Aug 1, 9:00 a.m. – Sun, Mar 12 2028" while the widget counter, Siri
  snapshot and card all say "Day n of 14".
- **Fix:** clamp the range tail to `MAX_APPOINTMENT_SPAN_DAYS`, mirroring
  `sliceForDay`.

### B11 — `AppointmentRecord` silently fabricates missing times, and Save persists them · severity: low-medium · confidence: high
- **Where:** `lib/features/calendar/domain/models/appointment_record.dart:50-51`
- **Problem:** `?? DateTime.now()` for `startTime`/`endTime`. Two paths reach a
  doc that could lack them: `getAppointmentById` (deep-link / push tap) and
  `fetchClientHistory`, whose query filters `clientId` alone with **no
  `orderBy('startTime')`** — so unlike the range streams it does not exclude
  field-less docs. The fabricated instant seeds the edit sheet
  (`event_details_controller.dart:88-91`) and a Save writes it.
- **Fix:** at minimum log when the fallback fires, so a legacy/console doc is
  visible rather than silently rewritten.

### B12 — `wave/worker.js` documents a cap warning that does not exist · severity: low likelihood / medium-high if reached · confidence: high
- **Where:** `functions/wave/worker.js:89-92`, `listOutstandingClientIds` at `:904`
- **Problem:** the comment asserts `OUTSTANDING_MAX` is "why the callable logs
  when the set comes back at the cap". There is no such log: the constant isn't
  exported, the function returns a bare `Set`, and neither caller checks its
  size. Past 2000 outstanding jobs the import protects a prefix, clobbers the
  rest **and stamps `wave.lastSyncedHash` from Wave's values** — the queued job
  then hashes the clobbered doc, matches, returns `noop`, and an accepted edit is
  gone with the badge reading "Synced with Wave". Same shape as the multi-day
  Live Activity skip that CLAUDE.md documented before it existed.
- **Fix:** return `{ids, atCap}` and `logger.error` at both call sites.

### B13 — two CLAUDE.md claims contradict the code · severity: low · confidence: high
- **Where:** CLAUDE.md, dashboard `displayStatusAt` bullet and the push section
- **Problem:** (a) "personal jobs have no mark-done flow" — `DetailsActionBar`
  (`details_action_bar.dart:47`) gates Mark-as-complete on
  `hasStarted && !isDone && !isCancelled` with **no** `isPersonal` branch, so a
  started personal block does offer it. The behaviour looks right; the written
  justification for the Attention-list carve-out is wrong. (b) the overdue sweep
  "queries `startTime` over 48h" — it is now
  `OVERDUE_LOOKBACK_MS + MAX_APPOINTMENT_SPAN_MS` ≈ 15 days
  (`functions/notification_policy.js:39`).
- **Fix:** decide which side is authoritative for (a) — correcting the sentence
  is the cheap answer, adding an `isPersonal` branch is the other — and correct
  (b) outright.

## 🔵 Areas to improve (review required)

### I1 — the Attention section eagerly builds an unbounded list of appointment cards · impact: high · confidence: high
- **Where:** `lib/features/dashboard/widgets/sections/attention_flags_section.dart:230`
- **Opportunity:** `_FlagGroup` spreads one `AppointmentCard` per record with no
  cap, inside a plain `Column`, inside `ListView(children: [...])` — so nothing
  is lazy: every card is built *and laid out* on the first frame. Its source is
  `flags.overdueOpen`, explicitly "the ONE reducer here with no range predicate",
  scanning ~10 weeks business-wide. Each card carries `IntrinsicHeight` (an extra
  layout pass over the whole subtree), an avatar stack and a `StatusChip`, and
  the cost is re-paid on every live snapshot and every period-control tap. Every
  sibling section caps at 5 (`upcomingLimit`, `NewClientsSection.rowLimit`); this
  is the only outlier. At 60 stale-open jobs — plausible, since the doc's own
  rationale is that a job overdue nine weeks ago still needs closing — that is 60
  `IntrinsicHeight` subtrees per frame.
- **Suggested improvement:** keep the reducer unbounded (the header *count* is
  the point) and cap the render: `take(_rowLimit)` plus an "N more" row, matching
  `NewClientsSection`. Or emit slivers so the enclosing scroll view builds lazily.

### I2 — the dashboard re-pays ~2000 document reads on every re-entry · impact: medium-high · confidence: high
- **Where:** `lib/features/dashboard/application/dashboard_providers.dart:47`
  (`dashboardHistoryProvider`) and `:67` (`newClientsProvider`)
- **Opportunity:** both are bare `FutureProvider.autoDispose`. The live half has
  `_keepWarmWithGrace` (3-minute grace,
  `calendar/application/appointments_providers.dart:19`) so it survives a
  leave-and-return with zero re-read — but the history `.get()` and
  `fetchClientsCreatedSince` are torn down and re-issued in full, up to 1000 docs
  each. Drilling into a job from the Attention list and coming back is exactly
  that round trip, and `_StatsList` waits on both, so the skeleton reappears.
- **Suggested improvement:** reuse the existing `_keepWarmWithGrace(ref)` in both.

### I3 — test-coverage gaps, all verified by grepping behaviours not filenames · impact: high · confidence: high
Verified individually — this repo's coverage often lives under the *caller's*
file name, so each was checked by symbol and by behaviour. The ones that
survived that check:
- **`functions/travel_utils.js:482`** — the multi-day Live Activity skip
  (`dayCountOf(c) > 1`), built three days ago as the first pass's B4. Zero test
  references. A regression parks a 5-day countdown on the Lock Screen and
  nothing errors.
- **`functions/live_activity_utils.js:93`** — `liveActivityCtx`, the documented
  single owner of the card context: **zero** test references against four call
  sites. `buildContentState` field-picks its ctx and `_stateFor` re-lists the
  fields a second time, so a dropped key silently falls back to "Client" — the
  exact failure the helper was created to end.
- **`lib/features/clients/widgets/views/appointment_history_view.dart:405,423`**
  — **no test loads a second page.** All four `fetchHistoryPage` stubs return the
  same list regardless of `after`, so the prefetch threshold, the
  `hasNextPage`/`isLoading`/`error` bail and the post-frame deferral are
  unexercised. These are the two bugs the commit message says were found while
  building it; a regression means History silently stops at page 1 or spins.
- **`dashboard_providers.dart:221`** — `availabilityConflictsProvider` entirely
  untested (the policy below it *is* tested; the wiring above is the gap). Wrong-
  person or empty flags render as "All clear".
- **`attention_flags_section.dart:127` + `daily_load_chart.dart:67`** — the
  Sunday-indexed *unrotated* weekday labelling in two brand-new widgets. Both
  carry a comment saying a display-ordered list "silently names the wrong day";
  neither is tested.
- **`functions/notification_policy.js:362`** — `contextFor`, the push/digest ctx
  builder (`isAllDay`, the personal-job `title` fallback, per-kind shape): no
  test file references it.
- **`functions/maintenance.js:33-45`** — `validateUploadedImage`: a **read**
  failure on `createReadStream` deletes the user's just-uploaded photo. Untested,
  and the module can't be `require`d because it resolves a Storage bucket at
  load — which is the repo's own stated reason such decisions belong in a pure
  `*_policy.js` sibling.
- **`dashboard_providers.dart:71-95`** — the P7 `archived` exclusion and the
  `createdAt`-null ordering in `newClientDatesProvider`/`recentNewClientsProvider`.
- **`event_details_save_pipeline.dart`** — the personal↔client **conversion**
  directions after `55ea3cb3`. Existing tests pin that a personal job *may* save
  an address, not what conversion keeps or clears. This is B1's blast radius.

### I4 — the load-bearing de-registration order is hand-written at 3 sites, and only 1 is tested · impact: medium-high · confidence: high
- **Where:** `lib/core/app/account_exit_listeners.dart:88-91`,
  `lib/features/settings/screens/settings_screen.dart:381-385` and `:439-443`
- **Opportunity:** push → presence → Live Activity, all before the credential is
  revoked. CLAUDE.md states this "lives in `AccountExitListeners`" — that is
  wrong for two of the three exits, and `AccountDeletionService` doesn't own it
  either. Only the `core/app/` copy has a test
  (`grep -rln unregisterCurrentDevice test/` returns that one file). Adding a
  fourth token store means three edits with no compile error; an ordering
  regression means de-registration hits a revoked credential and a stale FCM
  token keeps pushing to a signed-out device.
- **Suggested improvement:** extract `deregisterThisDevice(ref)` into
  `core/app/` and call it from all three — this fixes a duplication *and* a
  documentation inaccuracy at once.

### I5 — give the `functions/` cancelled/terminal vocabulary one owner · impact: medium · confidence: high
- **Where:** B4's four sites, plus `String(x.status || "").toLowerCase() ===
  "cancelled"` spelled **5×**: `notification_policy.js:170` and `:269`,
  `travel_utils.js:213`, `widget_payload_utils.js:121`,
  `notification_utils.js:239` (already the odd one out, testing `!== "cancelled"`
  on a raw `statusOf`).
- **Suggested improvement:** one `isCancelledStatus(status)` beside B4's shared
  set. This is the same module family that already drifted twice.

### I6 — complexity hotspots · impact: medium · confidence: high
- `lib/features/clients/widgets/views/appointment_history_view.dart` — **750
  lines**, with `_AppointmentHistoryViewState` at **642** holding four concerns
  (pagination driving, search indexing + filtering, sliver rendering, error/empty
  states). P7 phase D moved ISP's job into this class. Extract `:529-693` as a
  `HistorySliverList` StatelessWidget — it needs only
  `rows/colorMap/currentYear/inSearch/footer/…`, and
  `calendar/widgets/views/agenda_sliver_list.dart` is the precedent.
- `lib/features/calendar/screens/main_calendar_screen.dart` — **819 lines**,
  State **639**. Two concerns aren't calendar: the app-wide photo-upload-failure
  SnackBar and role-upgrade routing. `lib/core/app/` exists for exactly this
  (`AppSyncListeners`, `AccountExitListeners`). Caveat: the photo SnackBar is one
  of the three sanctioned SnackBar sites, so `.claude/rules/frontend.md`'s file
  reference moves with it.
- `lib/features/calendar/widgets/sections/appointment_form_fields.dart` — 602
  lines, **35 constructor params** across 2 call sites. Honest caveat: all are
  `required`, so a miss *is* a compile error — this is readability cost, not the
  silent `createAccount` trap. Grouping the 10 `onPick*`/`onSelect*` callbacks
  into one class beside `AppointmentFormControllers` would be proportionate.
- The large `functions/` modules (`wave/worker.js` 925, `wave/customers.js` 832,
  `travel_utils.js` 819) decompose into small named functions already — **leave
  them alone.**

### I7 — two dashboard reducers do avoidable work per snapshot · impact: low-medium · confidence: high
- `dashboard_aggregator.dart:229` `computeDailyLoad` makes **7 full passes** over
  the merged list, each `runsOn` → `sliceFor` **allocating an
  `AppointmentDaySlice`** just to discard it as a bool (~5,600 throwaway objects
  at n≈800, re-run on every live snapshot and every `employeesStreamProvider`
  emission). One outer pass incrementing a `Map<DateTime,int>` — or reusing
  `expandToDays`, which already buckets in one pass — fixes it.
- `dashboard_providers.dart:236-243` `availabilityConflictsProvider` builds a
  fresh filtered copy of the entire merged list **per employee** (O(E·n)).
  Group by assignee id once instead. Milliseconds each, but they land on the same
  frame as I1.

### I8 — two more 3+-site duplications worth an owner · impact: medium-low · confidence: high
- `firebase_appointments_repository.dart:318`, `:336`, `:470` — the
  `fetchStart`/`end`/`orderBy`/`limit` range-query head, verbatim 3×. The
  dashboard's live/history split depends on both halves reaching the **same**
  `fetchStart`; a one-sided edit silently changes the overlap `mergeById`
  assumes. One private `_rangeQuery(range)` the three chain from.
- `my_details_screen.dart:114`, `:190`, `settings_screen.dart:240` —
  `updateSelfDetails`'s 7 named args re-spelled 3×, because the rules' `hasOnly`
  forces the patch to name every allowlisted key. Adding a key to
  `kSelfServiceUserFields` needs three edits and a miss is a silent
  `permission-denied` on an ordinary save.

### I9 — the travel sweep reads each candidate's `users` doc twice · impact: low · confidence: high
- **Where:** `functions/travel_utils.js:681` (`loadTravelPrefsByEmployee`) vs
  `functions/notification_utils.js:86-93` (`sendToEmployee`'s cache-miss path)
- **Opportunity:** the prefs pass reads `users/{id}` per candidate and never
  lands the result in the `cache` Map `sendToEmployee` later consults, so the
  same doc is read twice per sweep × 288 sweeps/day. One-line fix; tiny cost.

### I10 — the Team tab pins a third session-long appointments listener · impact: low · confidence: medium
- **Where:** `employee_schedule_providers.dart:32`, watched per row from
  `employee_card.dart:33`, kept mounted by `hub_shell.dart:57`
- **Opportunity:** the provider is `autoDispose` *specifically* so the range
  stream's eviction grace can fire — but `HubShell`'s `IndexedStack` never
  unmounts a visited tab, so the row watchers never leave and the grace can never
  run. Gate the row's watch on tab visibility (`HubShellScope.currentOf`), as the
  tours already do. Verify against the drawer badge, which shares
  `todayRangeProvider` and must keep the range value identical or it forks a
  second query.

### I11 — 15 `logger.warn` labels carry no tag prefix · impact: low · confidence: high
- **Where:** `google_places_repository.dart:37,49,68,117,137,148`;
  `splash_controller.dart:57,60`; `splash_screen.dart:124`;
  `event_details_controller.dart:130,168`;
  `appointment_form_concerns.dart:104`; `employees_screen.dart:277`;
  `auth_service.dart:215`
- **Opportunity:** the tag is now *the only place the tag lives* (notices no
  longer carry one), so a Crashlytics search for the operation misses these
  entirely. The Places repo is tagless while its own consumers use
  `ADDR-AUTO`/`ADDR-DETAILS`. Prefix each and add the new tags to
  `.claude/rules/error-handling.md`. The `login.*` family is a separate
  self-consistent convention — normalize it deliberately or leave it.

### I12 — six `functions/` exports nothing reads · impact: low · confidence: high
- `notification_policy.js:385,389,390,392` (`OVERDUE_LOOKBACK_MS`,
  `LEDGER_TTL_MS`, `OPEN_LIKE`, `KIND_PRIORITY`), `travel_utils.js:811`
  (`canDeferRoutes`), `wave/import_schedule.js:120` (`DELTA_OVERLAP_MS`),
  `employee_accounts.js:769` (`notifyAdminsOfSelfEmailChange`) — each used only
  inside its own file, read by no module and no test. The constants themselves
  are live; only the export surface is dead. May be a deliberate test seam;
  drop the export lines only if you confirm that.

## 🟡 Code-quality suggestions (optional)

- `appointment_history_view.dart:457` — `CircularProgressIndicator.adaptive()`
  where `AdaptiveProgressIndicator` is the one seam (9 other sites use it).
  `.adaptive` branches on `defaultTargetPlatform`, so a test forcing the look via
  `ThemeData(platform:)` — the documented mechanism — cannot reach it. **Not
  auto-applied** because the seam defaults to 20px against
  `CircularProgressIndicator`'s 36px, so the swap is visible; pass an explicit
  size if you want the current look.
- `.claude/rules/error-handling.md` — the `guardedOffline` carve-out still names
  "the two `accept_invite_*` screens", both deleted in P4c. The live carve-out is
  `account_setup_screen.dart:298`, which surfaces offline through its own banner.
  As written, the rule points at deleted files and the next reviewer flags a
  correct site.
- `lib/features/wave/widgets/wave_settings_section.dart:52` `_blockedOffline()` —
  a hand-written widget-layer offline guard where `guardedOffline` is used at 13
  other sites. Arguably a legitimate variant, since it surfaces the typed
  `WaveNetwork` message `guardedOffline` cannot. Owner call: route it through, or
  add the carve-out to the rule so it stops reading as drift.
- `dashboard_hero.dart:79`, `text_size_view.dart:306` — `FontWeight.w800` with no
  800 face bundled (Instrument Sans ships 400/500/600/700), so it renders as 700.
  Cosmetic; the code claims a weight it cannot produce.
- `lib/core/images/image_storage_service.dart:67` — `deleteImage` is public with
  exactly one caller two lines below it (`deleteImages`); could be `_deleteImage`.
- `functions/scripts/audit-client-phone-backfill-damage.js` — one-off forensic
  script for the completed 2026-08-08 incident, `require`d by nothing. Keep as a
  record or move under `docs/`; owner call.

## Notes / uncertainties

- **Verified clean, so explicitly not reported as findings:** zero orphaned ARB
  keys of 706 (EN↔FR in exact lockstep, every key has its `@meta` block — I
  checked this independently); zero unreferenced files; zero surviving fragments
  of the retired flows (signup codes, the `#compat-1.37.1` shim,
  `kShowTestingDeleteClient`, `table_calendar`, `AdaptiveShell`, …); 25 function
  definitions == 25 `index.js` exports; no duplicate or stale index entries and
  all 6 TTL policies still declared; zero UTF-8 BOMs; zero unused dependencies;
  every `dispose()` present; 9/9 raw `Stream.listen` sites pass `onError`;
  exactly the 3 sanctioned SnackBar sites; no `FirebaseFirestore.instance` in
  UI; no `throw Exception(...)` in `lib/`; all 13 callables set
  `enforceAppCheck: true` with the documented guard order; every documented
  Dart↔JS mirror pair agrees; `displayStatusAt` has exactly one owner; every
  `appointmentsInRangeProvider` consumer re-scopes through `runsOn` and
  role-branches correctly; all four save controllers set their in-flight flag
  before the first await.
- **Two reviewers disagreed on S1** (whether the rules bound can reject a legal
  save). I traced the wall-clock arithmetic myself and the DST case is real; see
  the note under S1.
- **I corrected two overstated impacts** from the reviewers before recording
  them: B4's purge gap does **not** orphan Storage bytes (an unpurged doc still
  references its images) and is reachable only by a console/Admin-SDK write, and
  B4 as a whole is low rather than high severity for the same reason.
- Cannot verify what production actually runs from here — S2's prod state is
  inferred from the commit messages and `docs/DEPLOYMENT.md`.
- Device-only surfaces (biometric app-lock, camera capture, the photo upload
  method channels, Live Activities, the home widget and Siri extension) are
  outside the harness; B2's blanking behaviour in particular wants a device check.
- The two auto-fixes are comment-only, so no test could have covered them;
  `flutter analyze` and the three touched-area suites were run anyway.

## What was not done, and why

**Superseded 2026-08-11 — all but I10 and the false finding are now closed.**
Each entry below keeps its original reasoning and records what actually
happened.

- **S2 — the deploy: DONE.** Ran `firebase deploy --only
  functions,firestore:rules,storage` (no `--force`), 25 → 25 with no export
  change and therefore no deletion prompt. `firestore:indexes` was deliberately
  omitted — the file was unchanged, and omitting it leaves the surviving
  `signupCodes` TTL policy alone. **S1's DST fix is live**, so the autumn
  rejection window is closed. Deploy-log row in `docs/DEPLOYMENT.md`.
- **S3 — `waveBootstrap` rate limit: FALSE FINDING, no change made.** The
  callable *is* rate-limited (`wave/callables.js:162`, `wave-bootstrap`,
  `WAVE_BOOTSTRAP_RATE_MAX`), placed deliberately on the not-yet-connected path
  only and before any Wave network call. The reviewer read the decorator and
  stopped. Guard order is correct as it stands.
- **I10 — the Team tab's session-long listener: STILL DECLINED.** The proposed fix
  gates each roster row's watch on `HubShellScope.currentOf`, which makes every
  row rebuild on every tab switch and read `0 jobs` whenever Team is not the
  current tab. That trades one extra listener over a single day's documents —
  the finding's own impact rating was low — for churn on a hot path and a
  visible wrong count. Revisit only with a cheaper signal than per-row
  visibility.
- **I6 — the three structural refactors: ALL THREE DONE** (2026-08-11, as their
  own pass rather than folded into the 59-file audit diff, which was the
  original objection).
  - `HistorySliverList` extracted to
    `clients/widgets/lists/history_sliver_list.dart`, taking `rows/colorMap/
    currentYear/inSearch/footer/onRowBuilt/firstRowTourWrap/isAdmin`.
    Deliberately sequenced AFTER C6, so the new pagination tests were in place
    to catch a behaviour change in the extraction.
  - The two non-calendar listeners moved to `core/app/` as widget wrappers:
    `PhotoUploadFailureListener` and `RoleUpgradeListener`. Wrappers rather
    than a `ref`-taking class like `AppSyncListeners`, because both need
    `BuildContext` and one needs an `initState`/`dispose` subscription.
    **`.claude/rules/frontend.md`'s sanctioned-SnackBar reference moved with
    it**, as this finding required.
  - `AppointmentFormCallbacks` groups the 10 required pickers beside
    `AppointmentFormControllers`; the four OPTIONAL callbacks stay on the
    widget, since their nullability is what distinguishes the two flows and is
    worth seeing at the call site. There were **three** call sites, not two —
    the widget test harness is the third, and the compiler found it.
- **I3 — 4 of 10 test gaps closed.** Done: the multi-day Live Activity skip
  (C1, in `travel_utils.test.js` — the existing harness had to be reused, and
  `live_activity_dispatch` is now mocked file-wide so the card is observable),
  `liveActivityCtx` and `contextFor` (C2, C5, new `live_activity_ctx.test.js`),
  plus new coverage for this pass's own fixes: the shared status vocabulary
  (`status_vocabulary.test.js`), the DST headroom in the rules bound, the Siri
  address scoping, and B1's personal-address guard in **both** directions.
  **The remaining six were closed 2026-08-11 — I3 is now 10 of 10.**
  - **C3** `availability_conflicts_provider_test.dart` (8): the wiring, not the
    policy — right assignee, every assignee of a shared job, a clear person
    OMITTED rather than listed empty, a multi-day run counting the day it
    works, and — the one that matters — a failed read surfacing as an error
    instead of as "All clear".
  - **C4** `weekday_labelling_test.dart` (5): every bar labelled with its own
    weekday across a whole week, so any rotation moves at least one label onto
    the wrong date, plus `joinWeekdayNames` ordering by stored index.
  - **C6** `appointment_history_pagination_test.dart` (9): needed a
    **cursor-aware** fake repo — every previous stub returned the same list
    whatever `after` held, which is exactly why no test had ever loaded page
    two. Covers the prefetch, the cursor's identity, the short-page stop, the
    `refresh()`-does-not-fetch trap on both pull-to-refresh and Retry, and a
    failed second page not spinning.
  - **C8** required the extraction this finding predicted:
    `runImageValidation` now lives in `maintenance_policy.js` with `readHeader`/
    `deleteFile`/`logger` injected, and `maintenance.js` resolves its file
    handle **lazily** so a non-appointment path still never touches Storage.
    `image_validation_policy.test.js` (19) pins the read-failure branch —
    which DELETES the user's photo, deliberately failing closed — including
    that it never falls through to the magic-byte check and survives a delete
    that also fails.
  - **C9** `new_clients_provider_test.dart` (6): the `archived` and null-
    `createdAt` exclusions are one guard, since `newClientDatesProvider`
    force-unwraps `createdAt`.
  - **C10** `event_details_personal_conversion_test.dart` (11): both conversion
    directions — client fields cleared to empty strings even with a client
    still selected in the form, the address KEPT and trimmed, and `isAllDay`
    surviving both ways.
- **B13(a) resolved as a doc fix, not a code change.** `DetailsActionBar` does
  offer Mark-as-complete on a started personal block; the CLAUDE.md sentence
  claiming otherwise was corrected rather than the behaviour changed. If the
  intent was actually to withhold that button, that is a separate decision.

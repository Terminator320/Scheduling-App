# Codebase Audit — 2026-08-04 (second pass)

Scope: whole repo (`lib/`, `functions/`, `firestore.rules`, `storage.rules`,
`firestore.indexes.json`, `test/`, `ios/`, `android/`).
Baseline: `a8cf8d3` on `redesgin` (v1.41.0+66), clean working tree.

Method: deterministic static scan, then five parallel deep reviewers
(security · bugs · dead-code/conventions · performance · maintainability).
Every finding below was re-verified against source by the coordinator before
being written down; the ones that did not survive that check were dropped.

> Supersedes `CODEBASE_AUDIT_2026-08-04-first-pass.md` (preserved alongside).
> That pass ran the same day against `7166d03` and closed 21 findings. This one
> is a fresh sweep over the shipped result — it is **not** a re-run of the same
> checks, and it found a distinct set.

## Summary

- **Scanned:** 337 Dart files in `lib/`, 72 JS files in `functions/`, 213 Dart
  test files, both rules files.
- **Statics clean:** `flutter analyze` → no errors or warnings; `dart fix
  --dry-run` → nothing to fix; `functions` ESLint → clean. Zero `TODO(pre-ship)`,
  `FIXME(`, `HACK(` or `kShowTesting*` markers anywhere.
- **Auto-fixed during the audit: 1** — one design-token swap.
- **Findings: 30**
  (⚠️ 2 deploy-gated · 🔴 4 security · 🟠 8 bugs · 🔵 10 improvements · 🟡 6 quality)
- **Implemented after the report ("do all"): 27 of 30.** The exceptions are the
  `#compat-1.37.1` shim (blocked until 1.37.1+64 leaves the App Store), plus I9
  and I10 — see the table.
- **Verification (final, observed):** `flutter analyze` clean ·
  `flutter test` **1608 passed** (was 1588) · `functions` ESLint clean ·
  jest **785 passed / 36 suites** (was 753 / 33) · `firestore.rules` compiles
  with only the 3 known `isAvailabilityOnlyChange` warnings.

### What changed, by finding

| Finding | Outcome |
|---|---|
| B1 propagate drops `isAllDay`/`isPersonal` | fixed + test |
| B2 client edits skip a mid-run job | fixed + 4 tests (`propagateClientChange` now exported) |
| B3 "0 upcoming jobs" for an on-site tech | fixed (moved off the `count()` aggregate, which cannot filter `endTime`) |
| B4 detail sheet hides a multi-day span | fixed via `formatWhenLine(lastDay:)` + 3 tests |
| B5 TODAY panel ordered by stored instant | fixed + test |
| B6 week strip hides the selected day's dot | fixed; 2 tests that pinned the drift updated |
| B7 `computeAttentionFlags` unbounded | **kept, now documented** — clipping would drop the oldest overdue work from the one list whose job is to surface it |
| B8 `visibleMonth` DST drift | fixed (calendar arithmetic) |
| S1 app-lock fails open for the session | fixed: tri-state flag, retries on resume, + 5 tests |
| S2 emergency fields on the peer-readable doc | **fixed** — `emergencyFieldNotSet` guard + 4 tests; no migration needed (see the checklist) |
| S3 locked UI still in the semantics tree | fixed (`ExcludeSemantics` + `ExcludeFocus`) |
| S4 clipboard sensitivity marking | not actionable from Dart; Android-only, and Android does not ship |
| S5 `npm audit` transitive | unchanged, deliberately |
| I1 day route forks a listener per tap | fixed via `AppointmentDateRange.forWeekBucketOf` + 4 tests |
| I2 rate limiter untested | 8 tests added |
| I3 account-callable ordering untested | 9 tests added |
| I4 `deleteAccount` untested | extracted `account_policy.js` + 11 tests |
| I5 upload-queue concurrency untested | 1 test — the one that fails without `_serialized` |
| I6 stale signup-code copy | reworded, EN + FR; one test updated |
| I7 travel sweep serial | flattened to `Promise.all` |
| I8 `CLAUDE.md` drift on assignee resolution | corrected + test pinning the empty-active case |
| I9 god modules / `dispatchQueuedJobs` | **not done** — pure structural churn with no correctness gain; this report's own advice is to do it when next touching those files |
| I10 dashboard 10-week listener | **not done** — the fix is a live/cached split that changes dashboard data flow; wants its own change |
| 🟡 `isFirstDay` | deleted (zero references anywhere, including tests) |
| 🟡 `web_url_launcher` silent failure | breadcrumb added |
| 🟡 `LocationPermissionResult` collapsed | reason now logged; the silent-to-user behaviour is deliberate and kept |
| 🟡 rules-doc errors | both corrected, plus the `firebaseReadyProvider` sanctioned-swallow entry |
| 🟡 `isDeletingAccount`, `exitEditing` | **left in place**, `CLAUDE.md` corrected instead — both are flagged in this report as owner calls, not audit calls |
| 🟡 `calendar_date`, unused assets, `EdgeInsets` legs, dark hex consts | left for a deliberate pass — see the section below |

### The headline finding

**`appointment_series_editor.dart:79` — `propagate()` drops `isAllDay` and
`isPersonal`.** Editing a repeating job and choosing "this and all future
visits" writes each sibling the *instants* derived from the edited flag
(midnight → 23:59) while leaving the sibling's own flag `false`. That
manufactures a record that is all-day in every respect except the one field
every off-screen mirror keys on — which re-arms the exact phantom "time to
leave" push at ~23:30 that the `isAllDay` skip in `selectTravelCandidates` was
added to prevent. The sibling path in `rewrite()` is correct (it copies from
`updated.copyWith(...)`, carrying every field); only `propagate` enumerates
fields by hand, and it enumerates 13 of 15.

### Second theme: `startTime >= now` is still the wrong floor in two places

The first pass widened the notification and travel sweeps by
`MAX_APPOINTMENT_SPAN_MS`. Two more queries with the same floor were missed, and
both are user-facing rather than backend-internal: `propagateClientEdits`
(a client's corrected phone/address never reaches a crew mid-run) and
`countFutureAssignments` (the **Disable account** caption reads "0 upcoming
jobs" for a tech who is on day 3 of a 10-day job).

---

## ⚠️ Deploy-gated checklist

No `TODO(pre-ship)` scaffolding remains. **One** item is gated on an action
outside the code.

- [x] ~~**`scripts/backfill-emergency.js` has no recorded prod run.**~~
  **CLOSED 2026-08-04, no migration needed.** Owner confirmed nobody has ever
  entered an emergency contact, so there is no data on the parent doc to move
  and the feature is treated as clean-slate. The fix does not rest on that
  being exactly true: `allow update` now routes both fields through
  **`emergencyFieldNotSet(f)`**, which permits a write leaving the field ABSENT
  and refuses one leaving a value. A plain denylist entry (the originally
  proposed fix) would have rejected the `FieldValue.delete()` scrub and left any
  straggler doc permanently un-updatable; this form cannot brick a doc, needs no
  backfill, and lets the existing client scrub heal anything unexpected. The
  script is deleted. Pinned by
  `test/core/security/emergency_contact_rules_test.dart`. **Still needs a rules
  deploy to take effect.**
- [ ] **`#compat-1.37.1` shim** — unchanged, deliberate, owner-signed-off,
  retired as ONE unit (`grep -rn "#compat-1.37.1"`) once 1.37.1+64 is off the
  App Store. Full 9-item inventory is in the first-pass report and still
  accurate. The `/clients` `allow delete` grant remains the highest-value one to
  withdraw — while it stands, a 1.37.1 admin can still orphan a client's job
  history, which is precisely what `deleteClient`'s live `count()` gate exists
  to prevent.

---

## Auto-applied cleanups (review the diff)

| File:line | Change | Why |
|---|---|---|
| `lib/features/clients/widgets/views/clients_list_view.dart:159` | `Colors.white` → `Theme.of(context).palette.onDangerFill` | The token exists in both themes for exactly this pairing with `palette.dangerFill` on the line above. Both themes currently resolve to `0xFFFFFFFF`, so this is pixel-identical today and routes future changes through the token. |

> Nothing else was auto-changed. Five `EdgeInsets.fromLTRB` legs that map to
> `AppSpacing` tokens were **deliberately not** swapped — each sits in a tuple
> whose neighbours (`14`, `20`, `25`, `18`, `11`, `13`) are documented
> intentional sub-token nudges, so swapping one leg mid-tuple is a judgment
> call, not a mechanical one. They are in 🟡 below.

---

## 🔴 Security findings

No critical or high findings. The rules, callable guard order, App Check
enforcement, credential handling, PII-in-logs and image pipeline all came back
clean — see "Clean results" for the full verified list.

### S1 — The biometric app-lock fails open and never retries for the session · medium · confidence high
- **Where:** `lib/core/security/app_lock.dart:39-58` and
  `lib/features/settings/application/app_lock_provider.dart:13-27`
- **Risk:** Both the widget's `_lockOnStartIfEnabled()` and the provider's
  `_load()` catch a secure-storage read failure, log, and leave the lock
  **off** — the widget `return`s without locking, the provider leaves
  `state = false`. `didChangeAppLifecycleState` then short-circuits on
  `if (!ref.read(appLockEnabledProvider)) return;`, so once that first read has
  failed, **no later `resumed` ever re-evaluates**. One transient keychain error
  at launch disables the app-lock for the whole session, silently: the app opens
  straight into a signed-in session holding client PII with no biometric prompt
  and no indication the lock is off. `isKeychainLockedError` (-25308) is still
  reachable in the pre-first-unlock-since-boot window that
  `first_unlock_this_device` does not cover, and any keystore/channel error hits
  the same path. `CLAUDE.md` records this exact symptom ("the biometric app-lock
  silently not engaging that session") — the accessibility change narrowed the
  trigger window but left the never-retry structure intact, and
  `.claude/rules/error-handling.md` warns about precisely this
  `catch → return false` shape.
- **Fix:** make the flag tri-state (`bool? _enabled`) and re-read on
  `AppLifecycleState.resumed` whenever it has never resolved successfully, so
  the lock engages as soon as the keychain becomes readable. Keep fail-open only
  for a *resolved* `false`.

### S2 — `emergencyContact`/`emergencyPhone` still writable on the peer-readable `/users` doc · medium · confidence medium
- **Where:** `firestore.rules:165-172` (create denylist), `:230-233`
  (`isValidUserData` still accepts them on update)
- **Risk:** `/users` read clause 2 (`isActiveUser() && resource.data.status ==
  'active'`) hands every active employee's device the full doc of every active
  peer. Rules are document-level — a field cannot be hidden from a document
  reader — so any doc still carrying these ships a **third party's** name and
  phone to the whole crew. That person is not an app user and never consented,
  which is why P4b moved the pair to `users/{id}/private/emergency`.
  `updateEmployee`'s `FieldValue.delete()` scrub only heals docs an admin
  happens to re-save. Confidence is medium only because the prod data state is
  not verifiable from here; the code path is certain.
- **Fixed 2026-08-04, and NOT the way this finding first proposed.** The
  original fix (run the backfill, then add both keys to the `allow update`
  denylist beside `uid`) turned out to be the worse of two options, because the
  denylist form rejects any write that *touches* the key — including the
  `FieldValue.delete()` scrub — so a doc that still carried the pair would have
  gone from "leaky" to "permanently un-updatable, including by
  `deactivateEmployee`". That is a harder failure than the one being fixed, and
  it is why the rules comment had deferred the change in the first place.
  Instead `allow update` now calls **`emergencyFieldNotSet(f)`** per field:
  a write that leaves the field ABSENT passes, a write that leaves a VALUE
  fails, and a write that never touches it passes (so a legacy value flows
  through untouched and the doc stays updatable while the client scrub heals it
  on the next save). Net effect: a value can never land on the parent doc, no
  doc can be bricked, and **no backfill or migration is required** — which also
  means the owner's "nobody has entered one" is a convenience here, not a
  load-bearing assumption. `functions/scripts/backfill-emergency.js` is deleted.
  The length caps in `isValidUserData` stay, and are now *not* dead: they are
  what validates a pass-through legacy value.
  Guarded by `test/core/security/emergency_contact_rules_test.dart` (4 cases,
  reading `firestore.rules` back — the same mechanism `text_limits_test.dart`
  uses, since rules need the emulator to test properly).
  **Needs a `firestore:rules` deploy to take effect.**

### S3 — The app-lock overlay does not remove the covered UI from the semantics tree · low · confidence medium
- **Where:** `lib/core/security/app_lock.dart:86-94`
- **Risk:** the overlay is a `Stack` sibling painted over `widget.child`; the
  child subtree stays mounted and stays in the semantics tree. Touch input is
  correctly absorbed (`ColoredBox` → `HitTestBehavior.opaque`), but
  VoiceOver/TalkBack can still traverse and read client names, addresses and
  phone numbers while the app is locked.
- **Fix:** wrap the child in `ExcludeSemantics(excluding: _locked, child:
  ExcludeFocus(excluding: _locked, child: widget.child))`.

### S4 — A copied starting password is not marked sensitive and does not expire · low · confidence medium
- **Where:** `lib/features/employees/widgets/fields/credential_line.dart:52-57`
- **Risk:** the egress itself is sanctioned by `CLAUDE.md` ("the ONE sanctioned
  egress — it is the feature"); this is only about how it is marked. Flutter's
  `Clipboard.setData` cannot set Android's `ClipDescription`
  `IS_SENSITIVE`, so on Android 12L+ the password appears in the clipboard
  preview toast, and on both platforms it persists indefinitely. Low practical
  impact on an App-Store-only iOS build, where pasteboard reads have prompted
  since iOS 16.
- **Fix:** note the residue in the onboarding instructions; add a platform
  channel to set the sensitive flag only if Android ever ships.

### S5 — `npm audit`: 1 critical, 9 moderate, 1 low — all transitive · low · confidence high · **carried forward (was R7)**
- **Where:** `functions/package.json`
- **Risk:** unchanged from the first pass. The critical (`websocket-driver`) is
  reached only via `@firebase/database-compat`, and this project uses no
  Realtime Database, so that require chain never executes in any deployed
  function.
- **Fix:** leave as-is; re-check when `firebase-admin` bumps
  `@firebase/database-compat`. Never `npm audit fix --force`.

---

## 🟠 Bug findings

### B1 — `propagate()` drops `isAllDay` and `isPersonal` onto every future sibling · high · confidence high
- **Where:** `lib/features/calendar/application/appointment_series_editor.dart:79-101`
- **Problem:** `propagate` hand-enumerates 13 fields onto each future sibling
  (title, client trio, address, crew, notes, materials, repeat, start/end,
  status) and omits `isAllDay` and `isPersonal`. The sibling therefore receives
  the new *instants* derived from the edited flag while keeping its own stale
  flag.
  Concretely: a repeating job (every 4 months, 9:00–17:00); the admin opens
  occurrence 1, turns **All day** on, saves, picks "this and all future visits".
  Occurrence 1 is correct (`isAllDay: true`, 00:00→23:59, renders "All day",
  skipped by `selectTravelCandidates`). Every sibling gets `startTime` = its day
  at 00:00 and `endTime` = its day at 23:59 but `isAllDay: false` — so the card
  reads `12:00 AM – 11:59 PM`, `functions/travel_utils.js:242` no longer skips
  it and fires a "time to leave" push at ~23:30 the night before for a block
  with no departure time, and the widget's `stillAhead` drops it from "today"
  from midnight. The same omission converts a personal block back into a client
  visit with empty client fields.
  Note the asymmetry: `rewrite()` (line 40) builds its copies from
  `withSeries = updated.copyWith(...)` and therefore carries both flags
  correctly. Only `propagate` is wrong.
- **Fix:** add `isAllDay: updated.isAllDay, isPersonal: updated.isPersonal,` to
  the `copyWith`. Better, invert the method to copy *from* `updated` and
  override only the per-sibling fields (`startTime`, `endTime`, `status`, `id`),
  the way `rewrite` does — the enumerate-by-hand shape is what allowed a
  two-field gap to open silently, and it will reopen the next time a field is
  added to `AppointmentRecord`.

### B2 — Client edits never reach a job that is mid-run · medium · confidence high
- **Where:** `functions/client_propagation.js:163`
- **Problem:** the propagation query filters `where("startTime", ">=", now)`,
  selecting only jobs that have not *started*. Under the daily-window model a
  run started up to 14 days ago is still live work. A 5-day job Mon–Fri; on
  Wednesday the admin corrects the client's phone number or suite number; the
  query excludes the running job because its `startTime` is Monday, so on
  Thursday and Friday the crew's card, detail sheet and push text still carry
  the old value. Nothing back-fills it afterwards — once the client doc is
  edited, the denormalized copy is never revisited.
  This is the same class `CLAUDE.md` warns about ("Every backend sweep that
  filters on `startTime` must reach at least that far back"); the digest and
  overdue sweeps were widened by `MAX_APPOINTMENT_SPAN_MS`, this one was not.
- **Fix:** floor at `new Date(now.getTime() - MAX_APPOINTMENT_SPAN_MS)`, then
  drop genuinely-finished records in code with an `endTime >= now` test
  (mirroring `stillAhead`). The `(clientId, startTime)` index already serves it.

### B3 — "Disable account" reports 0 upcoming jobs for a tech who is on site · medium · confidence high
- **Where:** `lib/features/calendar/data/firebase_appointments_repository.dart:86-94`
- **Problem:** `countFutureAssignments` uses the same `startTime >= now` floor.
  It backs `futureAssignmentCountProvider`, which renders the "N upcoming jobs"
  caption under **Disable account** (`edit_person_sheet.dart:676`). A tech on
  day 3 of a 10-day job with nothing else booked shows **"0 upcoming jobs"** —
  the admin disables them believing nothing is affected, and `syncUsersByUid`
  immediately disables the Auth account, revokes refresh tokens and purges
  presence/FCM, cutting them off a job they are physically on site for.
- **Fix:** widen the floor to `now - maxAppointmentSpanDays` and count with an
  `endTime >= now` test in Dart. The existing
  `(employeeIds CONTAINS, startTime ASC)` index still serves it.

### B4 — The appointment detail sheet never shows a multi-day run's span · medium · confidence high
- **Where:** `lib/features/calendar/widgets/views/details_view_leaf_widgets.dart:103-112`
- **Problem:** `DetailsHeader` renders exactly one when-line via
  `formatWhenLine(appointment.startTime, appointment.endTime, allDayLabel:)`.
  The read-only body has no end-date row, no `Day N of M`, and no
  `lastWorkDayOf` — that helper appears only in the *edit* controllers. So a
  5-day job Aug 4–8 shows `9:00 AM – 5:00 PM · Day 3 of 5` on the card, and
  tapping it opens a sheet reading `TUE 4 AUG · 9:00 AM – 5:00 PM`: the wrong
  date (day 1) with no hint the job runs four more days. Worse for an overnight
  run (Aug 4 22:00 → Aug 9 06:00), where the header is indistinguishable from a
  single one-night shift.
- **Fix:** pass the day slice (or at minimum `lastWorkDayOf`) into
  `DetailsHeader` and render the span the way `AppointmentCard._timeLabel`
  already does.

### B5 — The employee TODAY panel is ordered by absolute instant, not clock time · medium · confidence high
- **Where:** `lib/features/employees/application/employee_schedule_providers.dart:73-85`
- **Problem:** the docstring says "in start order" but the provider never sorts,
  and neither does its consumer (`employee_today_section.dart:46`) — the list
  arrives in the stream's `orderBy('startTime')` order, which is the *absolute*
  instant. An employee with a 5-day run booked Aug 1 (daily window 17:00–19:00)
  plus a one-off today at 08:00 sees the **17:00 run listed first** on Aug 4,
  because its stored `startTime` is Aug 1.
  This is the identical defect the backend already fixed and documented —
  `functions/notification_policy.js:285-295` sorts by
  `businessMinutesOfDay(startTime)` precisely because "ordering on the raw
  instant floated it to the front". The Dart mirror was not updated.
- **Fix:** sort by the slice's window start, or reuse `expandToDays`, which
  already sorts via `_byAllDayThenWindowStart`.

### B6 — The week strip hides the selected day's crew dot, contradicting the month grid · low · confidence high
- **Where:** `lib/features/calendar/widgets/views/calendar_week_strip.dart:170`
- **Problem:** the guard is `dotColors.isEmpty || isSelected ? null : …`, with
  the comment *"same rule as the month grid's cells"*. The month grid does the
  **opposite** and says so explicitly (`calendar_month_grid.dart:229-234`:
  "Kept on the selected day too (owner call, 2026-07-31) … hiding them made the
  day you were looking at the one day whose crew you couldn't see"), and
  `CLAUDE.md` pins it: "Every cell that has crew shows it — off-month, selected,
  today, all of them. The week strip renders the same list capped at 1, for the
  same reason." So: collapse the calendar and tap a busy day, and that day is
  the only one in the row with no dot while the agenda below it lists jobs.
- **Fix:** drop `|| isSelected`. The comment is factually wrong either way and
  must change; if the owner did decide the strip differs, correct the comment
  and the `CLAUDE.md` sentence instead.

### B7 — `computeAttentionFlags` is the one dashboard reducer with no range predicate · low · confidence high
- **Where:** `lib/features/dashboard/domain/dashboard_aggregator.dart:190-206`
- **Problem:** `computeTodayOps` re-scopes via `runsOn`, `computeWorkload` via
  `runsInRange`, and `computeWeekBuckets`/`computeBusiestWeekday` clip via
  `_bucketIndex`. `computeAttentionFlags` iterates the raw list, which starts at
  `fetchStart` (= `range.start − 14 days`). The Attention list therefore draws
  from ~10 weeks where every other dashboard section uses 8, so items surface
  there that nothing else counts.
  Mild, and arguably desirable — a job that went overdue 9 weeks ago genuinely
  still needs attention. It is listed because it is literally "a reducer over
  `appointmentsInRangeProvider` without a day predicate", the shape `CLAUDE.md`
  calls a bug, so it should be an explicit decision rather than an accident.
- **Fix:** either clip with `runsInRange(a, range.start, range.end)`, or leave
  it and add a one-line comment saying the wider window is deliberate here.

### B8 — `visibleMonth` uses `Duration` arithmetic across DST · low · confidence high
- **Where:** `lib/features/calendar/domain/models/appointment_record.dart:136-138`
- **Problem:** `firstOfMonth.subtract(_gridOverscan)` /
  `firstOfNextMonth.add(_gridOverscan)` land at 01:00 or 23:00 on the two
  DST-shift months, unlike `forDay`, which `CLAUDE.md` requires to be calendar
  arithmetic. For October 2026, `end` = `Nov 1 00:00 + 14d` = **Nov 14 23:00**,
  so `expandToDays`'s `!day.isBefore(range.end)` clips Nov 15 out of the
  overscan; symmetrically the April grid loses Mar 18 at the low edge.
  Harmless today because ±14 is a deliberate superset of the ±6 the grid can
  show — but it is the one place the documented convention is not followed, and
  `fetchStart` inherits the hour of drift.
- **Fix:** `addCalendarDays(firstOfMonth, -14)` /
  `addCalendarDays(firstOfNextMonth, 14)`.

---

## 🔵 Areas to improve

### I1 — The day route forks a fresh 15-day Firestore query on every day tap · high · confidence high
- **Where:** `lib/features/calendar/screens/day_route_screen.dart:102`
- **Opportunity:** `fetchStart` widens every range query 14 days back — correct,
  and pinned. But for a *month* range that is 59→73 days (1.24×); for a
  **one-day** range it is 1→15 days (**15×**), and four surfaces use one-day
  ranges, each then discarding ~14/15 of the result via `runsOn`.
  The day route compounds it: `_day` is `State`, so every ◀/▶ tap mints a new
  `AppointmentDateRange` **value** → a new `appointmentsInRangeProvider` family
  instance → a **new Firestore query**, each pulling its own overlapping 15-day
  window. `_keepWarmWithGrace` holds each alive 3 minutes, so they stack rather
  than replace. At 10 jobs/day, arrowing through a week costs ~1,050 doc reads
  where the pre-multi-day behaviour was ~70.
- **Suggested improvement:** hold **one** wider range (the visible week or
  month) in state and re-scope per day in Dart with `runsOn`/`sliceFor` — the
  pattern `employeeJobsTodayProvider` already uses. One listener over 7 days
  replaces 7 listeners over 15 days each. Do **not** narrow `fetchStart` or
  widen at a call site; both are pinned. (A longer-term option — a second
  inequality on `endTime` with an `(endTime, startTime)` composite index — would
  remove the widening entirely but changes the required `orderBy` prefix and
  therefore the meaning of the `_rangeStreamLimit` prefix warning. Separate
  change.)

### I2 — `enforceDurableRateLimit` has zero tests · high · confidence high
- **Where:** `functions/security.js:143` (coverage 45.56% stmts; uncovered
  145–224, which is exactly this function plus `assertAdmin`)
- **Opportunity:** the app's only durable rate limiter guards `deleteAccount`,
  `completeEmployeeSetup`, `createEmployeeAccount`, `deleteEmployeeAccount` and
  `deleteClient`. `security.test.js` has 31 cases and stops at the payload
  helpers. Three load-bearing decisions are documented in comments and pinned by
  nothing: it tracks **per-attempt timestamps rather than a windowStart
  counter** (a counter lets a caller burst 2×max across the window boundary);
  **rejected attempts are deliberately not recorded** (or a hammering caller
  holds the window full forever); and the best-effort refund removes exactly its
  own timestamp. "Simplifying" the first into a counter doubles every limit in
  the app with no test failure anywhere.
- **Suggested improvement:** ~6 tests. `getFirestore()` resolves *inside* the
  function body, so the existing `jest.mock("firebase-admin/firestore")` pattern
  used by the other suites works directly — no refactor needed.

### I3 — The `employee_accounts.js` callables' ordering is untested · high · confidence high
- **Where:** `functions/employee_accounts.js:187-300` (`createEmployeeAccount`)
  and `:351-429` (`changeEmployeeEmail`)
- **Opportunity:** every *pure* piece is well covered — `provisionAuthAccount`
  (5 cases), `performCreateAccount` (7), `buildActivationPatch` (6),
  `performDeleteAccount` (3), `performChangeEmail` (6). The callables that
  *sequence* them have zero tests, and the sequencing is the entire security
  story — both halves were previously bugs and both are pinned only by comments:
  - `resetProvisionedPassword` must run **only after** `performCreateAccount`
    has transactionally claimed the person as still-`invited`.
  - the rollback `auth.deleteUser` must fire **only when we minted the account**
    (`if (!provisioned.reused)`); rolling back a *reused* account deletes a real
    employee's Auth record.
  - `changeEmployeeEmail` must update Auth **before** Firestore and **revert the
    Auth email** if the doc write fails — the revert is the whole point of the
    callable, and a failed revert must `logger.error` the uid + docId and
    **never the addresses** (PII). A refactor that drops the revert passes the
    entire suite today.
- **Suggested improvement:** ~7 `verifyInOrder`-style tests against the mocked
  auth/db scaffolding the pure-helper suites already set up.

### I4 — `deleteAccount` — the repo's other irreversible deletion — is untested · high · confidence high
- **Where:** `functions/account.js:42` (coverage 25% stmts / 11.11% branches;
  uncovered 45–143, i.e. the entire body). `account.test.js`'s 5 cases all test
  the pure `isReauthStale`.
- **Opportunity:** this is user-facing irreversible account deletion, and the
  remedy is already established precedent in this repo: `maintenance.js`
  resolved a Storage bucket at load and so could not be `require()`d in tests,
  which is why its decisions moved to `maintenance_policy.js` — now at **100%
  coverage** with 12 cases pinning the status gate, the images-before-doc
  ordering and loop termination. `account.js` is the same shape and never got
  the same treatment.
- **Suggested improvement:** extract the orchestration into `account_policy.js`
  taking `{db, auth, now}` injected, mirroring `maintenance_policy.js` exactly.
  Pin the re-auth staleness gate, the teardown ordering, and that a partial
  failure never leaves a half-deleted account.

### I5 — `PendingUploadStore._serialized` has no concurrency test · medium-high · confidence high
- **Where:** `lib/features/calendar/data/pending_upload_store.dart:86`;
  `test/.../pending_upload_store_test.dart` (7 tests, **every one drives a
  single mutation at a time**)
- **Opportunity:** `_serialized` guards a bug that **already destroyed data**.
  Per `CLAUDE.md`: `add`/`remove`/`prune` are each `load()` → mutate → `_save()`
  over one SharedPreferences key, so two overlapping mutations both read the
  same list and the second save erases the first's change — a save staging a
  batch while a drain removed a finished one wrote `[E1, E2]` then `[]`,
  "stranding E2's files with no queue entry and no failure notice." The current
  tests are exactly the shape that passed while that bug was live.
- **Suggested improvement:** **one test.** Fire `store.add(E2)` and
  `store.remove(E1)` without awaiting between them, `await Future.wait([...])`,
  assert `load()` returns exactly `[E2]`. It fails if `_serialized` is removed
  and passes with it — which is the entire point. Highest safety per line
  written in this report.

### I6 — Two tour/invite strings still teach the deleted signup-code workflow · medium · confidence high
- **Where:** `lib/l10n/app_en.arb:2113` + `app_fr.arb:471`
  (`tour_employeesAddDesc`); `app_en.arb:2423` + `app_fr.arb:543`
  (`employees_invitedNote`)
- **Opportunity:** both render on shipping screens. `tour_employeesAddDesc`
  ("Create an invite with a one-time signup code to share with your new team
  member") renders at `tour_step_text.dart:39`; `employees_invitedNote`
  ("They'll appear as Invited until they sign up with the code you share")
  renders in a `WarningNote` at `invite_person_sheet.dart:292` — directly under
  the invite form, i.e. the highest-traffic place an admin reads instructions.
  P4c deleted that flow entirely; the admin now hands over an email plus the
  shared starting password. These are user-facing *wrong instructions*, not
  cosmetic drift.
- **Suggested improvement:** reword all four ARB entries to describe the
  account + starting-password handover, then `flutter gen-l10n`. Owner wording
  call, which is why it was not auto-applied.

### I7 — The travel sweep resolves every (candidate × assignee) pair serially · medium · confidence high
- **Where:** `functions/travel_utils.js:604-629`
- **Opportunity:** the nested `for` `await`s `resolveReminderForAssignee` one
  pair at a time; each pair is an independent chain (a ledger `get()`, possibly
  a Routes API round-trip, then `deliverRecipientOnce`). Its two sibling
  sweeps were already fixed for this — `runOverduePromptSweep` and
  `runDailyDigest` both flatten to `Promise.all`, with an explicit comment that
  serialising them "only added wall-clock … the sweep runs against the timeout
  as headcount grows." The travel sweep was left serial and compensated with
  `timeoutSeconds: 120`. At ~40 pairs that is ~9 s; at ~200 pairs ~40–45 s, and
  a sweep that does blow the budget is killed under `maxInstances: 1`, slipping
  those reminders to the next run — a *late* "time to leave" push, the one
  failure mode this feature cannot absorb.
- **Suggested improvement:** flatten to a `deliveries` array and `Promise.all`
  it, mirroring `runOverduePromptSweep`. If Routes quota is a concern, use a
  small concurrency pool (8–16) rather than staying fully serial.
  (`runOnSiteFlipPass` has the same shape but is bounded by live-card count —
  leave it.) This is **distinct from** the first pass's R2, which is about the
  reads paid *before* the gates; both remain open and are complementary.

### I8 — `CLAUDE.md` describes an active-employee resolution the code no longer has · medium · confidence high
- **Where:** `lib/features/calendar/application/event_details_controller.dart:137`
- **Opportunity:** `CLAUDE.md` states the active set must be resolved "the way
  `_enrichSelectedEmployees` does (cached `employeesStreamProvider` value,
  falling back to a fresh `watchEmployees().first`) — never trust a cold/empty
  stream value at save time". The actual `_resolveActiveEmployees()` is a bare
  `ref.read(employeesRepositoryProvider).watchEmployees().first`, and
  `employeesStreamProvider` does not appear anywhere in the file. The code is
  structurally **safer** than the doc (`.first` waits for a real emission rather
  than reading a possibly-cold cached value), so the documentation is what needs
  correcting — but a load-bearing invariant that no longer describes its own
  code will mislead the next change.
  Related coverage gap: the *retain* half is well pinned
  (`event_details_controller_test.dart:467`, `:503`); the **inverse** is not —
  an empty active-employee emission must not retain every original and silently
  undo a real deselection, which also changes who can see the visit.
- **Suggested improvement:** correct the `CLAUDE.md` bullet to match the code,
  and add one test: repo emits `[]`, assert a deselection survives.

### I9 — Two backend god-modules and one high-branch function · medium · confidence high
- **Where:** `functions/notification_utils.js` (657 lines),
  `functions/travel_utils.js` (699), `functions/wave/worker.js:540`
  `dispatchQueuedJobs` (~204 lines, 28 branch tokens, 6 levels of real nesting)
- **Opportunity:** the 2026-08-02 `notification_policy.js` split correctly
  extracted the pure *rules* but left all orchestration behind, so
  `notification_utils.js` still mixes push transport, the write-diff trigger,
  two scheduled sweeps and the Live-Activity/widget glue — four unrelated
  reasons to edit one file. `travel_utils.js` mixes pure selection, a **Google
  Routes HTTP client**, and two sweeps. `dispatchQueuedJobs` owns claiming plus
  all four outcome paths (success / retryable / terminal / lost-claim), each
  repeating the same `commitOutcome(...)` shape, so changing one means reading
  past three others.
- **Suggested improvement:** all three are change-safety, not correctness —
  schedule opportunistically when next touching those files, not as standalone
  work. Cleanest seams: `runDailyDigest` + `runOverduePromptSweep` (~136 lines)
  → `notification_sweeps.js`; the Routes client + its TTL estimate cache
  (~150 lines, the only part with network I/O and no Firestore) →
  `travel_routes_client.js`; and extract `dispatchQueuedJobs`' per-job body as
  `processQueuedJob(ctx, doc)` so each outcome becomes independently testable.

### I10 — The dashboard opens a ~10-week business-wide listener sitting at the 1000-doc cap · low-medium · confidence high
- **Where:** `lib/features/dashboard/application/dashboard_providers.dart:16-18`
  → `DashboardAggregator.rangeAround`
- **Opportunity:** `rangeAround` spans 8 ISO weeks back through next Monday;
  `fetchStart` adds 14 more, so the live query covers ~70 days of *all*
  appointments — ~700–1,000 doc reads per dashboard open. `_rangeStreamLimit` is
  1000, so at ~15 jobs/day the dashboard is already at the cap and silently
  renders a prefix (it does warn, correctly). Only `computeWeekBuckets` /
  `computeBusiestWeekday` need the 8-week history, and they need only `status` +
  `startTime`.
- **Suggested improvement:** split into (a) a small live today/attention range
  and (b) a cached one-shot `get()` for the trend buckets, invalidated once per
  day. The trend chart does not need a live listener. Alternatively raise the
  limit for this one consumer and accept the cost knowingly.

**Smaller coverage gaps, worth doing opportunistically:**
`recountOne` (`functions/client_job_count.js:68`, uncovered — pins that it writes
via `update()` not `set({merge:true})` so a client deleted out-of-band is never
resurrected as a count-only stub, and that a swallowed `NOT_FOUND` must not
become a rethrow under `retry: true`); `lastWorkDayOf`
(`appointment_day_slice.dart:72`, no direct test — two cases, a day job and a
night shift); `functions/client_propagation.js` (50%, uncovered 150–194 — pairs
naturally with B2).

---

## 🟡 Code-quality suggestions

- **`AppointmentDaySlice.isFirstDay`** (`appointment_day_slice.dart:45`) —
  **zero references in `lib/` *and* `test/`**. Its three siblings are live
  (`isMultiDay` 14 refs, `isOvernight` 15, `isLastDay` test-only). The single
  clearest "just delete it" item in the pass — but the multi-day work is
  mid-flight (Plan 2 §8 mirrors still owed), so it may be pre-staged. Delete it,
  or add the test that pins it beside `isLastDay`'s. Owner call.
- **`EmployeeFormActivity.isDeletingAccount`**
  (`employee_form_controller.dart:110`) — zero `lib/` callers, 4 test refs.
  `CLAUDE.md` and the doc comment both say `isSaving`/`isDeletingAccount`
  "survive as `isNotEmpty` getters for the two person sheets"; `isSaving` really
  is used, `isDeletingAccount` never is (only `PendingInviteTile` deletes, and
  it correctly asks `isDeletingAccountId(id)`). Either delete it and amend the
  `CLAUDE.md` sentence to name `isSaving` alone, or leave it and note the
  asymmetry. **Do not touch the id-keyed pair** — that is the load-bearing half.
- **`EventDetailsController.exitEditing()`** (`event_details_controller.dart:176`)
  — carried forward (was R10). Still zero production callers; referenced only by
  its own test.
- **`calendar_date`** (`app_en.arb:559` / `app_fr.arb:124`) — carried forward
  (was R8). Still zero references; superseded by
  `calendar_startDate`/`calendar_endDate`/`calendar_selectDate`. Safe to prune in
  a deliberate l10n pass. `nav_myDetails` is also unreferenced but is
  **forward-provisioned for P5** — keep it.
- **`assets/images/paul2.png` (1.1 MB) and `logo_splash.png` (612 KB)** —
  carried forward (was R8). Still tracked, still declared in no pubspec
  `assets:` block, still ship in no binary. ~1.7 MB of repo weight.
- **Five `EdgeInsets.fromLTRB` legs** that map exactly to `AppSpacing` tokens —
  `app_nav_drawer.dart:68` and `:332`, `calendar_month_grid.dart:17`,
  `calendar_header_block.dart:73`, `app_header_pair.dart:54`. Deliberately not
  auto-applied: their tuple neighbours are documented intentional nudges.
- **15 raw hex literals in the dark `ColorScheme`** (`themes.dart:189, 235-263,
  280, 313, 317, 369, 386`) while the light theme maps every slot through
  `AppColors.*` — asymmetric authority for the same slots, and
  `Color(0x12FFFFFF)` recurs unnamed at 5 sites. Promote the recurring
  alpha-composited values to named consts.
- **`web_url_launcher.dart:16`** pushes `error_couldNotOpenLink` on a
  malformed-URI pre-flight guard with no log. Not strictly a rule violation (it
  is not a `catch`), but it is a user-visible failure with no Crashlytics trail;
  the `LAUNCH-URL` tag already exists. Add a `logger.breadcrumb`.
- **`LocationPermissionResult`** (`location_permission_service.dart:5-10`)
  computes 4 members with care, and its only consumer
  (`presence_sync_controller.dart:127`) collapses them to
  `!= granted → return`. Presence tracking silently never starts with no way for
  the user to learn why. Branch on `permanentlyDenied` ("open Settings") and
  `servicesDisabled` ("turn on Location Services").
- **Two corrections to `.claude/rules/frontend.md`:** line 211 places
  `address_map_launcher.dart` under `lib/core/launchers/` — it is at
  `lib/features/maps/address_map_launcher.dart`. Lines 190–193 list 3 hub
  `heroTag`s; there are **5** (add `liveMapRosterFab`, `liveMapRecenterFab`).
- **Add `firebaseReadyProvider.future.catchError((Object _) {})` to the
  sanctioned-swallow list in `.claude/rules/error-handling.md`.** It appears at
  4 gate points with no adjacent `logger.warn`, which reads as a rule violation
  but is correct — `splash_screen.dart` already logs that shared future's
  failure once, and Dart delivers the same settled error to every listener, so
  re-logging would file four non-fatals for one event.

---

## Clean results — recorded so the next audit can skip them

- **Security legs verified clean:** all 15 `onCall` exports set
  `enforceAppCheck: true` and follow auth → `assertAdmin` → `assertPayloadShape`/
  `requireString` → `enforceDurableRateLimit` → work; no `onRequest`/CORS/HTTP
  endpoints exist. No `if true` or bare `request.auth != null` grants. Field
  denylists present on **both** create and update for `/users` and `/clients`,
  and neither `toMap()` emits them. `liveActivityTokens`' client-written TTL is
  required and bounded (`< request.time + 31d`). Every rules cap sits at or
  above its `TextLimits` counterpart. Query-vs-get constraints correct on all
  three `users` streams. Disabled-employee revocation complete. Magic bytes
  validated client- **and** server-side. `enableIMEPersonalizedLearning: false`
  on all three credential fields. No secrets, PII, `print`/`debugPrint`, SQL or
  `eval` anywhere; no tracked `.env`/`google-services.json`/keystore/`.p8`.
  All six TTL policies declared.
- **Robustness: zero defects.** 40 flagged `mounted` candidates were all false
  positives (guarded, or the `context` use sat in an argument list evaluated
  before the await); the "second await after an earlier guard" case was checked
  specifically. All `late` fields assigned synchronously. No force-unwrap on a
  legitimately-null value. **Zero** `as Map<String, dynamic>` casts in `lib/` —
  the Android callable-cast hazard is fully respected. Three intentional empty
  catches, all documented in place.
- **Dead code: near-zero.** All 305 `lib/` files have an inbound import; all 87
  providers, all 473 class/enum/mixin declarations and all 123 top-level
  functions are referenced; all 30 backend exports accounted for. Exceptions are
  the 🟡 items above.
- **l10n: 587 keys in each ARB, identical sets, no duplicates, EN/FR parity
  perfect.** Only 2 unreferenced keys, one of them deliberate.
- **No duplicated logic at 3+ sites.** A normalized-token duplicate detector
  (6-line sliding window) over every production file returned only widget
  boilerplate and a repeated constructor field list — neither should be
  abstracted, per the anti-defaults.
- **Convention drift: 7 of 14 categories fully clean** — exactly 3 sanctioned
  `SnackBar` sites, zero `FirebaseFirestore.instance` in any widget, zero
  `throw Exception(` where a Failure exists, zero styling branches on `isDark`,
  all 9 raw `Stream.listen()` calls pass a tagged `onError`, no `DateFormat`
  constructor in a repeated builder, 5 FABs with 5 unique `heroTag`s, and all
  ~130 radius sites use `AppRadius`.
- **All four flagged dependencies are genuinely used:** `freezed` (9 `@freezed`
  classes), `build_runner` (runs it), `flutter_launcher_icons` (config block at
  `pubspec.yaml:170-177`, manual-run tool), `google_maps_flutter_ios_sdk9`
  (runtime SPM implementation override — removing it reintroduces CocoaPods,
  which `ios/CLAUDE.md` forbids).
- **Well-covered and re-verified:** `maintenance_policy.js`,
  `widget_payload_utils.js`, `image_magic.js`, `wave/errors.js`,
  `wave/import_schedule.js`, `params.js` (all 100%); `live_activity_utils.js`
  98.55%; `notification_policy.js` 95.28%; `travel_utils.js` 91.81%. The P4c
  password-before-activation ordering, `performDeleteClient`'s live `count()`
  gate, `_patchWindow`'s `jobCount`-preserving merge and `mergeRetainedAssignees`
  are each pinned.

## Notes / uncertainties

- **The first pass's 11 open items (R1–R11) remain open** unless restated above.
  R7 → S5, R8 and R10 → 🟡, R1 is refined and sharpened by I1, and R2 is
  complementary to (not the same as) I7. R3–R6, R9 and R11 are unchanged.
- **Plan 2 §8 debt confirmed still open, not closed by the first pass.**
  `lib/features/siri/application/schedule_snapshot_provider.dart:31` and
  `lib/features/home_widget/application/widget_sync_service.dart:56,70` both
  consume `appointmentsInRangeProvider` **raw** — zero `runsOn`/`sliceFor`/
  `expandToDays` in either feature — so days 2+ of a run are still invisible
  there. Worth stating explicitly because the first pass's B1 bullet ("four
  surfaces") could be misread as having covered them.
- Prod data state (the emergency-contact backfill, index usage stats for R9)
  cannot be verified from here — S2's confidence is medium for that reason
  alone; its code path is certain.
- Generated files (`*.freezed.dart`, `lib/l10n/.gen/**`) excluded throughout.
- No secrets, tokens or PII appear in this report; findings name locations only.

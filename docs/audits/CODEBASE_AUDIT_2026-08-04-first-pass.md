# Codebase Audit — 2026-08-04

Scope: whole repo (`lib/`, `functions/`, `firestore.rules`, `storage.rules`,
`firestore.indexes.json`, `test/`, `docs/`). Baseline: `9b384aa` on `redesgin`,
clean working tree.

Method: deterministic static scan, then five parallel deep reviewers
(security · bugs · dead-code/conventions · performance · maintainability).
Every finding below was re-verified against source before being acted on.

> Supersedes `CODEBASE_AUDIT_2026-08-02-post-p4c.md`.

## Summary

- **Scanned:** 334 Dart files in `lib/`, 70 JS files in `functions/`, 211 Dart
  test files, both rules files, `docs/`.
- **Statics were already clean:** `flutter analyze` → no errors or warnings;
  `dart fix --dry-run` → nothing to fix; `functions` ESLint → clean. No
  `TODO(pre-ship)` markers anywhere, and `lib/core/testing_flags.dart` is
  confirmed deleted — the destructive pre-ship hole from prior audits is gone.
- **Implemented this pass:** 21 findings (10 bugs · 4 security · 2 performance ·
  4 maintainability) plus a documentation-integrity pass, and 55 new tests.
- **Reported, not implemented:** 12 — deploy-gated on the `#compat-1.37.1`
  shim, or structural refactors whose payoff did not justify the churn.
- **Two fixes were written and then REVERTED** after review showed each traded a
  known gap for a worse one — S2 and B5 below. Both are recorded as open.
- **Verification:** `flutter analyze` clean · `flutter test` **1588 passed**
  (was 1555) · `functions` jest **753 passed** (was 729) · `npm run lint` clean.

### A note on this pass's own review

The five audit reviewers found the bugs; a follow-up simplify + code-review pass
found **four defects in the audit's own fixes**, which is worth recording:
a missed fifth consumer of the widened stream (`DashboardAggregator` — B10), a
missed fifth `liveActivityCtx` call site, a French date regression introduced by
consolidating two formatters, and the two reverts above. Reviewing the fix is
not optional here.

### The headline finding

Commit `a4b6882` (multi-day appointments, 2026-08-03) widened both range
queries to start at `AppointmentDateRange.fetchStart` — **14 days before the
range's start** — so a job already under way is still fetched. That makes every
range stream a deliberate *superset* of its range. Only the calendar screen
re-scoped. **Four other consumers read the widened list raw**, and each was
silently reporting up to a fortnight of past jobs as "today". `CLAUDE.md`
documented the off-screen mirrors as not-yet-updated but did not mention these
in-app surfaces at all.

---

## ⚠️ Pre-ship / deploy-gated checklist

No `TODO(pre-ship)` scaffolding remains. What is left is the
**`#compat-1.37.1` shim** — deliberate, owner-signed-off, and retired as ONE
unit (`grep -rn "#compat-1.37.1"`) once 1.37.1+64 is off the App Store.

Complete inventory, so it can be pulled in a single sweep:

| # | Location | Piece |
|---|---|---|
| 1 | `functions/index.js:16` | `require("./invites")` |
| 2 | `functions/index.js:46-47` | `createEmployeeInvite`, `redeemSignupCode` exports |
| 3 | `functions/invites.js` | whole module (211 lines) |
| 4 | `functions/signup_code_utils.js` | whole module (63 lines) |
| 5 | `firestore.rules:84-86` | `/signupCodes` block |
| 6 | `firestore.rules:128-137` | 4th `/users` read clause |
| 7 | `firestore.rules:156` | `allow delete` on `/users` |
| 8 | `firestore.rules:537` | `allow delete` on `/clients` |
| 9 | `firestore.indexes.json:288-296` | `signupCodes.expiresAt` TTL policy |

**Three of these leave a REAL hole open while they are there** —
`docs/DEPLOYMENT.md` previously claimed only one did, and has been corrected:

- [ ] `firestore.rules:537` — a 1.37.1 admin can `doc.delete()` a client that
      still has appointments, orphaning that history. Exactly what
      `deleteClient`'s live `count()` gate prevents.
- [ ] `firestore.rules:156` — the same build can delete a `users` doc,
      permanently orphaning every past appointment's crew link. Access itself
      fails closed (`authAccessChange` disables the Auth account); the link
      loss does not.
- [ ] `firestore.rules:281-285` — `allow update` on `/users` denylists only
      `uid`/`termsAcceptedAt`/`locationConsentAt`, so 1.37.1's employee edit
      writes `email` straight to Firestore with no Auth call and **desyncs
      sign-in from every admin surface**. Verified against the 1.37.1 tree
      (`employee_form_sheet.dart:426`, `firebase_employees_repository.dart:147`).
      This build routes every email edit through `changeEmployeeEmail`, so the
      tightening below costs the current build nothing — but it breaks 1.37.1
      with an opaque `permission-denied`, so it waits for the sweep:

```
allow update: if isAdmin()
  && !request.resource.data.diff(resource.data).affectedKeys()
       .hasAny(['uid', 'termsAcceptedAt', 'locationConsentAt'])
  && (!request.resource.data.diff(resource.data).affectedKeys()
         .hasAny(['email'])
      || resource.data.get('uid', '') == '')
  && isValidUserData(request.resource.data);
```

- [ ] **Also confirm `signupCodes` is empty in prod.** If it is, the shim can be
      pulled early and S2 below becomes moot.

---

## ✅ Implemented — bugs

### B1 — Four surfaces reported a fortnight of jobs as "today" · high
**Where:** `day_route_screen.dart:147`, `employee_schedule_providers.dart:23`
and `:68`, `app_nav_drawer.dart:292`.

All four reduced `appointmentsInRangeProvider` with no date predicate, trusting
the stream to be range-exact. Since `a4b6882` it is not. Concretely: the Day
route listed every non-cancelled job of the previous fortnight as a numbered
stop and built the "Open in Maps" route from the first 10 of them; the Team
roster's "jobs today" and the employee detail's TODAY panel showed 11 where the
answer was 2 (and agreed with each other, so they looked right); the drawer's
Calendar badge counted the same window *including* cancelled visits.

**Fix:** added `runsOn(appointment, day)` to `AppointmentDaySlice` — the
declared single owner of day-scoping — and routed all four through it. The day
route now works in `AppointmentDaySlice` throughout, so a continuing job also
sorts by *that day's* window rather than the run's first morning, and its card
gets the correct `Day N of M`.

### B2 — Cancelling or deleting a multi-day job mid-run pushed nothing · high
**Where:** `functions/notification_policy.js:139-200`.

Every branch bailed on `notPast(startTime)`. A job running Aug 1 → Aug 10
cancelled on Aug 5 is "past" by its start, so the assigned crew got **no
cancellation push** and turned up on Aug 6. The Live Activity card still ended,
so the only signal was a card silently vanishing.

**Fix:** the gate is now `stillAhead(record)` — the run's `endTime`, falling
back to `startTime` when absent. Four new tests, including that a genuinely
finished run still emits nothing.

### B3 — Multi-day jobs never got the "job finished?" prompt · medium
**Where:** `functions/notification_policy.js:26-33`. `OVERDUE_QUERY_WINDOW_MS`
was `2 × OVERDUE_LOOKBACK_MS` (48 h), commented "the form caps a visit just
under 24h". That cap is now 14 days, so any run longer than a day fell outside
the query floor, never became a candidate, and sat open forever.
**Fix:** `OVERDUE_LOOKBACK_MS + MAX_APPOINTMENT_SPAN_MS`.

### B4 — The nightly digest missed crews already on site · medium
**Where:** `functions/notification_policy.js:233-252`,
`functions/notification_utils.js:597`. Both the query and the grouping bucketed
on `startTime ∈ tomorrow`, so a crew booked Aug 1 → Aug 10 was told "no jobs
tomorrow" every evening of the run.

**Fix:** query floor widened by the max span; grouping now tests whether the run
*overlaps* tomorrow. This is an instant-span overlap, not the app's full
daily-window model, so an overnight run can still be listed on the morning it
finishes — over-inclusive, which is the safe direction. Stated in the
docstring; the full mirror remains Plan 2.

### B5 — A long job drops out of its own travel context · medium · **NOT FIXED, deliberately**
**Where:** `functions/travel_utils.js:66`. `MAX_BOOKING_MS = 24h` bounds the
per-employee context query, so a tech on a 5-day run has that run excluded from
their own context and `decideOrigin`'s intervening-job prong never sees it.

**Widening it to the span cap was tried and reverted.** Pulling the run into the
context does surface it — but `decideOrigin`'s intervening prong tests the RAW
instants (`startMs < candidateStartMs && endMs > nowMs`), which a 10-day run
satisfies at *every hour of every one of its days*. A tech with an 08:00 one-off
during an Aug 1–10 run would then depart "from" that run's address at 07:00,
while they are at home and its window doesn't open until 09:00 — a NEW wrong
origin traded for an old missing one.

Scoping that prong needs the daily-window model mirrored into JS, which is owed
by Plan 2. Until then the gap stands exactly as it did before multi-day booking
existed — a known limitation, not a regression.

> B3–B5 all stemmed from the same thing: no backend constant for the span cap.
> Added `MAX_APPOINTMENT_SPAN_DAYS` / `_MS` to `functions/time_utils.js`, with a
> pointer to the Dart owner (`maxAppointmentSpanDays`) and back. Cross-language,
> so it is a hand-mirror by necessity — documented as such, like
> `kDefaultStartingPassword`/`DEFAULT_PASSWORD`.

### B6 — Phantom booking conflicts across any multi-day run · medium
**Where:** `firebase_appointments_repository.dart:451`. `findBusyEmployees`
tested raw instant overlap, but the two stored times are a *daily window* — so
a crew on Aug 1–5 09:00–17:00 was reported busy for a 19:00 job on Aug 3, when
their window that day ended at 17:00. The admin had to force through a phantom
clash on every evening job during any run.

**Fix:** added `dailyWindowsOverlap` to the slice owner and used it to filter
the query's results. It compares *all* window pairs rather than matching day
indices — an overnight window runs into the following calendar day, which a
same-index comparison misses (caught by a test written before the
implementation was right).

### B7 — Day-route paging drifted an hour across DST · low
**Where:** `day_route_screen.dart:236`, `:277` — `Duration(days: 1)` where
calendar arithmetic is required. The fetch stayed correct (`forDay` normalizes),
but `_day == DateTime.now().dateOnly` became permanently false, so the Today
button never hid again. Now `addCalendarDays`.

### B8 — A `users` doc without an `email` field was permanently un-editable · low
**Where:** `firebase_employees_repository.dart:236`. The pre-flight read
defaults a missing `email` to `''`; the in-transaction re-read left it `null`.
`null != ''`, so the concurrency guard aborted **every** save on such a doc —
including the admin's attempt to add the missing email — with an opaque "try
again". Now normalized identically on both sides.

### B10 — The dashboard hid days 2+ of every multi-day run · medium
**Where:** `dashboard_aggregator.dart:224`. `_startsOnDay` bounded the day
correctly but tested `startTime` alone, so a crew on site all week showed as
free in Today's ops and the workload column; `computeWorkload`'s week gate
(`startTime.isBefore(weekStart)`) dropped a run from the week it was worked.
The same class as B1, opposite sign — and missed by the audit's first pass,
which fixed four consumers of the widened stream and not this one.
**Fix:** `runsOn` for the day, and a new `runsInRange` for the week bucket.

### B11 — The digest named the wrong job as "First:" · medium
**Where:** `notification_policy.js:285`, `notification_messages.js:234`.
Once B4 correctly included runs already under way, both sorts still ordered by
the absolute `startTime` — so a run that began days ago floated to the front of
tomorrow's list and the digest read "First: Acme at 1:00 p.m." when the real
first job was at 08:00. **Fix:** both sort on `businessMinutesOfDay` — clock
time, which is what a daily window actually means. Introduced by this pass's own
B4 fix and caught in review.

### B9 — Double-tapping Delete on a client showed success then an error · low
**Where:** `client_form_controller.dart:170`. `deleteClient` was the only write
here without a reentrancy guard; the second call returned `client-not-found`.
Added `ClientDeleteBusy`, which — per the error-handling rules — surfaces
nothing.

## ✅ Implemented — security

### S1 — One poisoned `employeeIds` entry could silence the nightly digest · low
**Where:** `functions/notification_policy.js:89`, `functions/notifications.js:138`.

`firestore.rules` shape-validates scalar id fields with `isValidDocIdField`, but
rules cannot iterate a *list*, so `employeeIds` reached `toIdList` unchecked and
its elements went straight to `db.collection("users").doc(id)` — which throws
**synchronously** on a slash. `runDailyDigest` fans out with `Promise.all` and
was unwrapped, so one bad element rejected the whole batch and killed the 18:00
digest for every employee, every night. Requires an admin write, so this is
defense-in-depth. `toIdList` now rejects slashes and over-long ids, and the
digest is wrapped like the reminder sweep already was.

### S2 — `redeemSignupCode` never checked `email_verified` · medium · **NOT FIXED, deliberately**
**Where:** `functions/invites.js:157`. The `/users` read clause serving this same
flow requires `email_verified == true`; the callable does not. Someone with a
code obtained out of band (a forwarded message, a screenshot) could register
that address unverified and redeem into an active employee account.

**The gate was written, then reverted the same day.** The security reviewer
believed 1.37.1 gated on verification client-side. It does not: `signUpWithCode`
(verified at `2b1ace5`) calls `register()` — `createUserWithEmailAndPassword`,
so `email_verified == false` — and `redeemSignupCode` on the very next line,
with no `sendEmailVerification` anywhere in that build's `lib/`. Worse, its
`_mapRedemptionError` has no case for the rejection, so it would surface
"Something went wrong" and then ROLL BACK — delete — the Auth account it just
created. That is every invite acceptance on the App Store build, permanently,
with no in-app recovery. The gate belongs in the shim-retirement sweep.
**Cheaper alternative: confirm `signupCodes` is empty in prod and pull the shim
early**, which closes this without a compatibility cost.

### S3 — `waveSetImportSchedule` was an unrate-limited admin write callable · low
**Where:** `functions/wave/callables.js:229`. Every other admin write callable is
durably rate-limited; this one was not. Added at 20/hour, placed **after**
payload validation so a burst of malformed submissions can't burn a legitimate
caller's window.

### S4 — Unbounded `pictures` and unvalidated `seriesOpId` in the rules · low
**Where:** `firestore.rules:417`. `pictures` is `arrayUnion`-appended by the
offline upload queue with nothing bounding it, and hitting the 1 MB doc ceiling
makes the job permanently un-updatable. `seriesOpId` is interpolated into a doc
id. Added a 100-element cap and `isValidDocIdField` respectively.

### S5 — Client email cap was looser than the callable's · low
**Where:** `text_limits.dart:28`. Both employee sheets bound email to
`TextLimits.email` (320) while `createEmployeeAccount` / `changeEmployeeEmail`
`requireString(..., 254)`. The project's own invariant says a client cap must
never exceed the callable's, or the field accepts a value the callable rejects
as `invalid-argument` — surfacing as an unfixable "Something went wrong". Added
`TextLimits.authEmail = 254` and used it on both sheets. Practically
unreachable (RFC 5321 caps a path at 254), so this is invariant hygiene.

## ✅ Implemented — performance

### P1 — The Team tab pinned a live Firestore listener for the whole session · medium
**Where:** `employee_schedule_providers.dart:21`. `employeeJobsTodayProvider` was
a keepAlive `Provider` watching the `autoDispose` range stream. A keepAlive
watcher is a permanent listener, so the 3-minute eviction grace could never
fire: one visit to the Team tab (or one `EmployeeCard` build) opened a 15-day
appointments snapshot that stayed open until the app was killed. Same bug
already fixed and documented at `employees_screen.dart:274`. Now
`Provider.autoDispose`.

### P2 — `DateFormat` constructed on every day-route build · low
**Where:** `day_route_screen.dart:221`. Added the memoized `dayHeaderFormatFor`
beside the existing per-locale caches in `month_grid.dart`.

## ✅ Implemented — maintainability

### M1 — The irreversible history purge had zero tests · high
`purgeExpiredHistory` is the only unattended, permanent deletion in the repo — a
quarterly cron that batch-deletes appointment docs *and* their Storage prefixes.
`maintenance.js` resolves a Storage bucket at load, so it cannot be `require()`d
outside the emulator and had no sibling test at all.

Extracted the orchestration into `functions/maintenance_policy.js` (the same
pure/orchestration split `notification_policy.js` already uses) and added **18
tests** covering the three rules that destroy data if they regress: the status
gate (live work must never be purged, at any age), the ordering (images first;
a doc whose cleanup failed is kept, so bytes never orphan), and loop termination
(a full page that made no progress must end the loop, not spin it to the 1800 s
timeout).

### M2 — The Live Activity `ctx` literal was hand-copied four times · high
`travel_utils.js:635` and `:652`, `notification_utils.js:252` and `:323`.
`_stateFor` **field-picks** its ctx into `buildContentState`, so a forgotten key
fails silently — the Lock Screen card just reads "Client". That bug has already
shipped once. The drift had restarted: two sites normalized address via
`_address(record)`, two passed `src.address` raw (possibly `undefined`).
Extracted `liveActivityCtx(record, opts)` into `live_activity_utils.js`; all four
call it.

### M3 — `TextLimits` ↔ `firestore.rules` had four exactly-equal pairs and no test · high
`CLAUDE.md` documents this three-way hand-mirror as having caused bugs in *both*
directions, and the only existing test asserted nothing tighter than
`lessThan(10000)`. Bumping any client cap by one would make every save carrying a
long value fail with an opaque `permission-denied`.

`text_limits_test.dart` now reads `firestore.rules` back, regex-extracts each
`isBoundedString(d.<field>, N)` cap, and asserts the client cap never exceeds it
— plus the same check against `requireString(req.data, "email", N)` in
`employee_accounts.js`. It is the only mechanism available (Dart, CEL and JS
cannot share a constant), and it turns a comment into a failing build.

### M4 — `ClientActionsHost` had no test · medium
Both destructive client paths route through this 113-line mixin, and grep for it
across `test/` returned nothing. Added 6 tests pinning the three ordering rules:
a reentrancy-skipped write surfaces nothing, the typed `ClientsFailureHasHistory`
branch wins over the generic cause+tag composer ("archive it instead" is
actionable where a tag is not), and delete confirms *before* the offline guard.

## ✅ Implemented — documentation integrity

The dead-code reviewer's headline was that **the code is exceptionally clean but
the docs are not** — and three doc claims would have caused a wrong action.

- **`docs/ARCHITECTURE.md` + `docs/CLOUD_FUNCTIONS.md` claimed the `signupCodes`
  rules block and TTL `fieldOverride` were already removed.** Both are live.
  Acting on that during a `firestore:indexes` deploy **drops a live TTL policy**
  — this repo has already lost 5 that way (2026-07-21). Corrected in both, with
  an explicit "do not clean this up ahead of the shim sweep".
- **`docs/CLOUD_FUNCTIONS.md` stated two false security guarantees** — that
  `allow delete` was withdrawn on `/clients` and on `/users`. Both are still
  granted. Corrected, each now pointing at the shim.
- **Deployment status was wrong**: "23 defined / 22 deployed" (actual 27/27),
  `deleteClient` and `recountClientJobs` marked "NOT yet deployed" when both are
  live, and `invites.js`/`signup_code_utils.js` described as deleted when both
  survive as the shim.
- **`docs/ARCHITECTURE.md:393` said `TextLimits.phone` is 15.** It is 24, raised
  deliberately — at 15 the mask's pass-throughs were unreachable. The stale
  number invited a "restore" of a fixed bug. Corrected, pointing at M3's test.
- **`docs/ARCHITECTURE.md`'s clients schema omitted `archived` entirely** and
  said the list orders by `createdAt` (it filters `archived` server-side and
  orders by `name`). Added, with the "must be on every doc forever" reasoning.
- **`README.md`** claimed background location capture (foreground-only since
  2026-07-27, App Store 2.5.4) and self-registration (no such path since P4c).
- **`docs/WORKFLOW.md`** is a pre-redesign document presenting itself as current
  — 12 confirmed misses (nav rail, `table_calendar`, `AppointmentTile`,
  `todayFab`, `google_fonts`, six hub tabs, the signup-code flow). Given a dated
  SUPERSEDED banner rather than deleted; its §6 constraints are still useful.
- **`docs/DEPLOYMENT.md`** asserted the `/clients` grant was "the only shim entry
  that leaves a real hole open". Corrected to three.

---

## 🔵 Reported — not implemented

### R1 — Overlapping range listeners bill the same docs 3–4× · medium
The "today" range (`[today-14d, today+1d)`) is a strict prefix of the always-on
Siri snapshot range (`[today-14d, today+8d)`), and `appointmentsInRangeProvider`
is keyed by value — so they are two separate live listeners over overlapping
docs. The calendar (~72d) and dashboard (~70d) windows overlap both.

**Not done because** collapsing them means giving the roster, the detail panel
and the drawer a shared "operational window" range, which changes provider
identity across four surfaces and interacts with the Siri provider's iOS-only
lifecycle. P1 removes the worst of the cost — the session-pinned listener — for
one word. The rest is a real but unmeasured win, and deserves its own change.

### R2 — Travel sweep pays presence + context reads before the gates that discard them · medium
`functions/travel_utils.js:518-565` fetches presence for all candidates and runs
one 50-doc context query *per employee*, then enters `resolveReminderForAssignee`
which only then checks the ledger and `canDeferRoutes`. At `every 5 minutes` =
288 runs/day, with a job sitting in the window for ~18 sweeps, most of that work
is discarded — an estimated ~15k–70k reads/day depending on booking density,
likely the largest recurring Firestore cost in the backend.

**Fix:** batch the ledger existence checks into one `db.getAll(...)` and evaluate
`canDeferRoutes` above the fetch loop, so a sweep where every pair is claimed or
deferred does zero presence/context reads. **Not done because** it restructures
the most timing-sensitive code in the backend; it wants its own change and its
own tests.

### R3 — Change-push builds the widget window before checking for a live token · medium
`notification_utils.js:345` runs an unbounded appointments query per recipient,
then calls `sendToEmployee`, which returns 0 immediately for a non-`active`
user, a disallowed role, or zero tokens. Resolve the user + token docs first
(the `cache` Map already exists), and add a `.limit()` — it is the one
appointments query in `functions/` with no bound. Contained; deferred only to
keep this pass's backend diff reviewable.

### R4 — Nested `IntrinsicHeight` in the day-route timeline · low
`_StopTile`'s `IntrinsicHeight` wraps `AppointmentCard`, which uses its own, so
the text-measure pass runs twice per stop. One short list, so frame cost only.
Fix is a `Stack` + `Positioned.fill` connector.

### R5 — File splits · medium
`edit_person_sheet.dart` (712 lines; six section builders ≈ 214 lines that move
cleanly to `edit_person_sections.dart`) and `auth_form_widgets.dart` (534 lines,
**7 public widgets** — the clearest breach of "one class per file" in the repo;
`AuthPasswordField` carries a security requirement and deserves its own file and
test). Both mechanical, both pure churn in a diff already touching 35 files.

Explicitly **not** worth splitting: `design_tokens.dart` (965 lines, a cohesive
token table) and `main_calendar_screen.dart` (797 lines, but its `build()` is 68
and well decomposed — the valuable extraction there is R6, not the widgets).

### R6 — The calendar's day-selection state machine is untestable · medium
`main_calendar_screen.dart:140-224` — ~85 lines of near-pure date logic sealed in
a `State`, reachable only through a 527-line widget test. `_pageWeek` +
`_setFocusedDay` own the "paging selects" invariant `CLAUDE.md` calls
load-bearing. Extracting it beside `CalendarCollapse` (already extracted for
exactly this reason) would make that rule directly assertable.

### R7 — `npm audit`: 1 critical, 8 moderate, all transitive · low
`websocket-driver` (critical, GHSA-mp7j-qc5w-4988) arrives via `firebase-admin`'s
Realtime Database client, which this project does not use — very likely
unreachable. `body-parser` *is* in the request path, but the advisory needs an
invalid `limit` that `firebase-functions` does not set. Both report a
non-breaking `npm audit fix`. **Not run** because a dependency bump wants its own
verify-and-ship cycle rather than being bundled into an audit diff. Leave the
`uuid` → `firebase-admin@14` chain alone regardless.

### R8 — Two orphaned l10n keys and two unreferenced assets · low
`calendar_date` (`app_en.arb:559`) has zero references and is safe to prune in a
deliberate l10n pass. `nav_myDetails` is orphaned but **forward-provisioned for
P5** — keep it. `assets/images/paul2.png` (1.1 MB) and `logo_splash.png`
(612 KB) are tracked but declared in no pubspec `assets:` block and ship in no
binary; ~1.7 MB of repo weight. Reported rather than deleted, per this audit's
own rule on l10n keys and file-level removals. EN/FR parity is perfect (587 keys
each, `untranslated.json` empty).

### R9 — Possibly-redundant composite index · low
`users (email, role, status)` — no query combines all three, and Firestore serves
equality-only multi-field queries by zigzag merge. Confirm via index usage stats
in the console, **never** by grep, and never remove it with `--force`.
(`appointments (clientId, startTime)` looked orphaned too but is live —
`functions/client_propagation.js:162`.)

### R10 — Unused method kept alive by its own test · low
`event_details_controller.dart:176` `exitEditing()` has zero production callers;
the only references are in its test. The edit sheet dismisses rather than
returning to view mode. Delete both, or keep if in-place cancel is planned —
an owner call, not an audit one.

### R11 — Accepted-by-design items, re-verified
The `Welcome123!` onboarding window and its millisecond-wide reset race; the
server not verifying the password actually rotated before activating
(`enforceAppCheck` is attestation, not authorization); the client-side-only
14-day span cap; per-contact field lengths uncapped inside the bounded
`contacts` array; `placesAutocomplete`'s per-instance in-memory rate limit
(~10× the nominal cap at `maxInstances: 10`). All documented and owner-signed;
listed so a future audit does not re-litigate them.

## Clean results — recorded so the next audit can skip them

- **Dead code: essentially zero.** No orphaned files (all 334 `lib/` files have
  an inbound reference), no dead Riverpod providers (all 87 checked), no dead
  route constants (checked by symbol *and* string value), no dead backend
  exports (all 27 mapped to a caller). The one exception is R10.
- **Convention drift: one instance.** `app_nav_drawer.dart:232` writes
  `vertical: 12` raw where `AppSpacing.sp12` exists. Everything else is clean:
  zero `throw Exception(`, zero `FirebaseFirestore.instance` in any
  `widgets/`/`screens/` directory, zero styling branches on `isDark`, exactly
  the three sanctioned `SnackBar` sites, no raw `Timer` debouncing, and all 21
  hardcoded colours are documented-deliberate.
- **`mounted`/`dispose` discipline: no gaps.** 23 raw regex hits across 325
  files, every one either a multi-line argument list belonging to the awaited
  call or already guarded.
- **Hand-mirrored pairs verified in sync:** `_who` in `notification_messages.js`
  vs `live_activity_utils.js`; `kDefaultStartingPassword`/`DEFAULT_PASSWORD`;
  the two widget payload builders; `displayStatusAt` (one owner, the dashboard
  delegates).
- **Every `onCall` validates via `assertPayloadShape`**, every one enforces App
  Check, and the guard order matches the rule everywhere.
- **Dependency heuristics were all false positives:** `build_runner`/`freezed`
  (9 `.freezed.dart` outputs), `flutter_launcher_icons` (CLI tool),
  `google_maps_flutter_ios_sdk9` (plugin-registration-only iOS SPM swap — no
  Dart import by design, and removing it reintroduces CocoaPods).
- **Feature-dir parity between `lib/features/` and `test/features/` is 17/17.**

## Notes

- The multi-day work's remaining mirrors (home widget, Siri snapshot,
  `widget_payload_utils.js`) are still single-day and remain owed by Plan 2 —
  `docs/plans/2026-08-02-multi-day-appointments.md` §8. B2–B5 closed the
  notification and travel halves of that debt; the display halves are untouched.
- Generated files (`*.freezed.dart`, `lib/l10n/.gen/**`) were excluded
  throughout.
- No secrets, tokens or PII appear in this report; findings name locations only.

# Codebase Audit — 2026-08-25

> ## STATUS: IMPLEMENTED 2026-08-25 (same day)
>
> **All 40 non-pre-ship findings were acted on.** `flutter analyze`
> **No issues found!** · `flutter test` **2796/2796** (was 2753) ·
> `functions` jest **1426/1426 across 63 suites** (was 1374/58) ·
> `npm run lint` clean.
>
> **What is NOT closed, and neither is a code change:**
>
> 1. **⚠️ The Pre-ship checklist below** — the photo-migration clear script
>    (step 4) and, before it, 🔴 **S1's Storage token rotation**. Deliberate
>    launch-time actions; read S1 before running the script, because the script
>    alone revokes nothing.
> 2. **🔴 S3** — confirm the Places API budget alert exists in the GCP console
>    for `schedulingapp-88727`. Unverifiable from the repo; no code change.
> 3. **🔵 I25** (~350 LOC of Cupertino/Material branches unreachable on the only
>    shipping platform) — left as reported. It is an owner call in the same
>    family as the `web/`/`windows/` scaffold decision, and both directions are
>    defensible.
>
> Everything else below is DONE. Notable behaviour changes to review in the
> diff: `setDayOff` now forces `isAllDay` (B1/B4), Undo in the clash dialog now
> inverts its own swap instead of restoring a snapshot (B3), a day off no longer
> stores a typed address (B5), photo uploads use `Cache-Control: private` (S2),
> and `nameInitials` takes graphemes rather than UTF-16 code units (I31).
> Two new sealed members — `AddEventBusy` / `EventDetailsSaveBusy` — made the
> compiler force a third branch at both save call sites (I21).


Scope: whole repo (`lib/`, `functions/`, `firestore.rules`, `storage.rules`,
`firestore.indexes.json`, `test/`). Baseline: `c15ef944` (1.51.0+80, branch
`redesgin`), working tree clean.

## Summary

- **Scanned:** 398 Dart files / 69k LOC in `lib/`, 311 test files, 120 JS
  modules in `functions/`, both rules files.
- **Auto-fixed (safe): 0** — and that is the finding, not a gap. `flutter
  analyze` reports **no errors or warnings**, `dart fix --dry-run` says
  **"Nothing to fix!"**, `eslint` is clean, the unused-file heuristic found
  **nothing**, and all four unused-dependency hits are verified false
  positives. There was no mechanical, behaviour-preserving change left to make.
  Every finding below is semantic and needs your decision.
- **Reported for your decision: 41**
  (⚠️ 1 pre-ship · 🔴 3 security · 🟠 6 bugs · 🔵 31 improvements)
- **Verification:** `flutter analyze` clean (baseline `No issues found!`
  holds) · `flutter test` **2753/2753** · `functions` jest **1376/1376 across
  58 suites** · `npm run lint` clean. Nothing was modified, so this is the
  baseline, not a post-change result.

### Top 3 to look at first

1. **🔴 S1** — legacy `pictures[]` download URLs are still live in prod and the
   only control that could revoke them was deleted. Running the clear script
   removes the app-visible copy but does **not** invalidate a link already
   captured on-device; that needs Storage token rotation, which went with
   `7ace6528`.
2. **🟠 B1** — a four-tap sequence on the add sheet leaves **Save permanently
   inert**: no notice, no field error, nothing in Crashlytics. The same root
   cause makes a *timed day off* storable (B4), which fires a "time to leave"
   push on somebody's day off.
3. **🔵 I8** — a load-bearing comment asserts in the **past tense** that the
   pending irreversible photo migration already ran, sitting next to the two
   artifacts it would license deleting. `DEPLOYMENT.md` says the opposite in
   two places.

---

## ⚠️ Pre-ship checklist

There are **zero `TODO(pre-ship)` markers** in `lib/` or `functions/` — the
project-map note is still accurate. One release-gated item remains:

- [ ] **Photo migration step 4** — `functions/scripts/clear-appointment-picture-arrays.js`
  has not run. `docs/DEPLOYMENT.md:653` gates it on the fleet ageing off builds
  that still write `pictures[]`; Crashlytics still shows 1.46.1/1.45.0. Ship the
  app build (step 3) first. **Read S1 before you run it** — the script alone
  does not revoke anything, and its `main()` is 0% covered (I9) in a repo that
  has already shipped a `--dry-run` that wrote everything then threw.

---

## 🔴 Security findings

### S1 — Legacy `pictures[]` download URLs are live in prod; the control that revoked them was deleted · severity: **high** · confidence: high

- **Where:** `firestore.rules:563-564` (surviving `pictures` clause) ·
  `firestore.rules:699-708` (the repo's own statement of this) ·
  `docs/DEPLOYMENT.md:653`
- **Risk:** Every appointment written before the CONTRACT step still carries a
  `pictures[]` array whose entries hold a `?alt=media&token=…` Storage download
  URL beside `storagePath`. That token is stable per object, never expires, and
  serves the bytes over plain HTTPS with **no auth and no `storage.rules`
  evaluation**. `rotateAssignedImageTokens` — which rotated those tokens on
  deactivation — was deleted at the CONTRACT deploy on the premise that nothing
  stores such a link. That premise holds for the *subcollection* (prod count: 14
  scanned, 0 url-only) but **not** for the parent arrays, which are a strictly
  larger set and are not url-*only*, so the count script's filter could not see
  them. `allow read` on `/appointments` hands an assignee the whole document,
  arrays included — so any employee assigned to those jobs on a pre-1.49 build
  already holds these URLs on-device. Deactivating them now rotates nothing:
  `syncUsersByUid` disables Auth, revokes refresh tokens and flips the
  `status == 'active'` gate, and **every one of those controls is bypassed by
  the token URL**. Net effect: a terminated technician retains permanent,
  unrevocable access to client property photos.
- **Fix:** two steps, and the second is the one that actually revokes.
  (1) Run the clear script (dry-run first; `countArrayUrls` sizes the exposure) —
  this removes the app-visible copy. (2) Rotate `firebaseStorageDownloadTokens`
  on the objects under `appointments/*/images/` to kill the outstanding links.
  Until (2), treat every pre-CONTRACT job photo as readable by anyone who ever
  held an assignment on it.
- **Note:** this is the repo's own documented open item, not an inference — but
  it is *open*, not mitigated, and the "ship the build, then the clear script"
  framing understates it by one step.

### S2 — Appointment photos upload with `Cache-Control: public` · severity: **low** · confidence: medium

- **Where:** `lib/core/images/image_storage_service.dart:69`
- **Risk:** `SettableMetadata(cacheControl: 'public, max-age=31536000')` is set
  on every upload. Since the CONTRACT step these bytes are fetched via
  authenticated `ref.getData()`, i.e. requests carrying an `Authorization`
  header. Per RFC 9111 §3.5 a shared cache must not store an authenticated
  response *unless* it carries `public` — so this directive is precisely what
  re-authorizes shared/intermediary caches to store and reuse a photo fetched by
  one entitled user, for a year, without revalidation. It also amplifies S1: the
  same header rides the tokened `?alt=media` responses. Realistic exploitation
  needs a TLS-terminating proxy or CDN in path, hence low/medium.
- **Fix:** `cacheControl: 'private, max-age=31536000'`. Nothing is lost —
  `AppointmentImageDiskCache` already owns offline/session caching and keys on
  the write-once `storagePath`. Affects only objects uploaded after the change.

### S3 — `placesAutocomplete`'s rate limit is per-instance; its backstop is outside the repo · severity: **low** · confidence: high

- **Where:** `functions/places.js:38-40, 140-162, 181`
- **Risk:** `enforceRateLimit` is a `Map` local to the function instance. With
  `maxInstances: 10` the real per-uid ceiling on a **billed** Google Places
  endpoint is ~200/min, and a cold start resets the bucket. Not an authz hole —
  `assertAdmin` + App Check mean it takes a compromised admin session. It is a
  billing-DoS whose only real control is unverifiable from the repo. The code
  says so itself and names the backstop as a GCP billing alert "which lives in
  the console and NOT in this repo."
- **Fix:** no code change required. **Confirm the Places API budget alert exists**
  for `schedulingapp-88727`. If not, create it, or switch this route to
  `enforceDurableRateLimit` the way `placesGetDetails` already does.

### Verified clean (checked, not skipped)

App Check `enforceAppCheck: true` on **all 14** callables and
`FirebaseAppCheck.instance.activate()` at `main.dart:136`; no `onRequest`/HTTP
function anywhere. Guard order correct on all 14 (auth → `assertAdmin` →
payload → limiter → work); **zero** instances of the fail-open
`if (req.auth.token && …)` shape. No privilege escalation: `performCreateAccount`
hard-codes `role = "employee"`; the `#compat-1.47.0` entry is genuinely
accepted-and-ignored and **must stay** (fleet is on 1.46.1/1.45.0). The `invited`
carve-out is an exact match checked before the active gate at both gates.
`liveActivityTokens.expiresAt` is required and bounded `< request.time + 31d`
against the client's 30d. All 4 credential fields pass
`kCredentialImePersonalizedLearning`. Magic-byte validation intact both sides.
No secret in any tracked file; `dev/.env` and `android/local.properties` both
confirmed ignored. No email/password/phone reaches a logger on either side.

---

## 🟠 Bug findings

### B1 — A day off with all-day off makes Save permanently inert, silently · severity: **high** · confidence: high

- **Where:** `lib/features/calendar/widgets/sections/appointment_form_fields.dart:483,488`
  · `lib/features/calendar/domain/policies/appointment_form_validator.dart:70-76`
  · `lib/features/calendar/widgets/sheets/add_appointment_sheet.dart:247`
- **Problem:** the schedule panel hides the all-day switch (`if (!isDayOff)`)
  *and* the time rows (`if (!isAllDay && !isDayOff)`) on the premise that a day
  off "is all-day by definition". **Nothing enforces that premise.** `setDayOff`
  sets only `isDayOff` (`add_event_controller.dart:185-187`,
  `event_details_controller.dart:285-287`), and the validator still requires both
  times whenever `!isAllDay`.
  Repro (~4 taps): new appointment → Personal **ON** (`setPersonal` sets
  `isAllDay = true` only because no times are picked) → All day **OFF** → tick
  **Day off** (switch *and* time rows both vanish) → pick a date and assignee →
  **Save**. `submit()` returns `AddEventInvalid`, the sheet's
  `case AddEventInvalid() … break` shows nothing, and `_err(context,'startTime')`
  is only read inside the un-rendered `timeRows()`. The button does nothing — no
  notice, no field error, no log. The only escape is un-ticking Day off, which is
  not discoverable. Same dead end on edit (`_announce` returns silently on
  `EventDetailsInvalid`). The one covering test walks the happy path where
  `setPersonal` happened to set all-day.
- **Fix:** make the invariant real — have `setDayOff(value: true)` also set
  `isAllDay: true` in both controllers, and pin it. (Relaxing the validator to
  `if (!input.isAllDay && !input.isDayOff)` fixes the inert button but leaves B4
  open.)

### B2 — `setState` after an await with no `mounted` guard, filed FATAL · severity: **medium** · confidence: high

*(Found independently by two reviewers.)*

- **Where:** `lib/features/calendar/widgets/dialogs/personal_block_clash_dialog.dart:488`
  (root cause), callers at `:446` and `:459`
- **Problem:** `_write()` guards its *failure* path (`:491 if (!mounted) return
  false;`) but returns `true` on success **unguarded**; both `_swap` and `_undo`
  then `setState` immediately. `showDialog` at `:64` passes no
  `barrierDismissible: false`, so tapping the scrim or the back gesture while an
  `updateAppointment` round trip is in flight unmounts the State before the
  `setState` lands. `State.setState`'s lifecycle check lives inside an `assert`,
  so in release it falls through to `_element!.markNeedsBuild()` on a nulled
  element → escapes to `runZonedGuarded` and is filed **FATAL**
  (`isFatalUnhandledError` excepts only `permission-denied`). The write itself
  lands, so no data loss. `use_build_context_synchronously` cannot see it because
  `setState` is not a `BuildContext` use — that is the analyzer blind spot this
  hides in. The asymmetry proves oversight, not decision: `_openRow` guards at
  `:425` and `_write`'s own catch guards at `:491`; every other post-await
  `setState` in `lib/` is guarded.
- **Fix:** `if (!mounted) return false;` immediately before `return true;` at
  `:488` — corrects both call sites at once.

### B3 — Undo writes a stale whole-record snapshot, re-adding a person who is off · severity: **medium** · confidence: high

- **Where:** `personal_block_clash_dialog.dart:456-466` (`_undo`)
- **Problem:** `_swap` correctly builds on `_live(job)` (`:445`), but `_undo`
  writes `state.original` verbatim — the record as it stood before *that row's*
  swap, not before the last one.
  Scenario: a block covers Marc **and** Nadia; job J has crew `[Marc, Nadia]`.
  (1) Row `Marc|J`: swap Marc→Alice → `_jobs[J] = [Alice, Nadia]`,
  `original = [Marc, Nadia]`. (2) Row `Nadia|J`: swap Nadia→Bob →
  `_jobs[J] = [Alice, Bob]`. (3) Undo row 1 → writes `[Marc, Nadia]`: it
  silently reverts Bob's swap **and puts Nadia — who is off — back on the job**,
  while row 2 still reads "Bob takes this job." That is precisely the outcome the
  dialog exists to undo. `personal_block_clash_dialog_test.dart:227` pins the
  two-swap write path; `:329` covers only a single-swap undo.
- **Fix:** store the *replacement* rather than the snapshot and undo by inverting
  it — `_replaceAssignee(_live(job), removeId: took.id, add: <the person who is
  off>)` — so Undo composes with later swaps the way `_swap` does. Add a test:
  two swaps on one job, undo the first, assert the second survives and the off
  person is not re-added.

### B4 — A *timed* day off is storable; off-screen mirrors then treat it as a job · severity: **medium** · confidence: high

- **Where:** `add_event_controller.dart:185-187` ·
  `event_details_controller.dart:285-287` (same root cause as B1)
- **Problem:** pick a start/end time first, *then* flip Personal on
  (`setPersonal` leaves `isAllDay=false` because times exist), then tick Day off
  → saved as `isPersonal:true, isDayOff:true, isAllDay:false, 09:00–17:00`. Also
  reachable in **one tap** on edit: open an existing timed personal block and
  tick Day off. Consequences, all silent:
  - `selectTravelCandidates` (`functions/travel_utils.js:265`) skips on
    `isAllDay === true` only → fires a **"time to leave" push for the employee's
    day off**.
  - `displayStatusAt` (`appointment_record.dart:180`) completes the day off at
    17:00 instead of end of day.
  - `_DayOffBody` (`details_view_body.dart:249-250`) uses `endTime` /
    `runLengthDays` rather than `lastWorkDayOf` — correct only while the block is
    really midnight→23:59; an overnight timed day off renders one day too many.
  - The picker's day-off figure (`employee_picker.dart:193-197`) renders a date
    range for what is actually a few hours.
- **Fix:** as B1 — force `isAllDay: true` when `isDayOff` goes on, in both
  controllers. This closes B1 and B4 together.

### B5 — A comment claims both save paths clear the address; neither does · severity: **low** · confidence: high

- **Where:** `appointment_form_fields.dart:560-566`
- **Problem:** the comment reads "…it drops the field entirely — **and both save
  paths clear it**, since a hidden field must never keep a value the form no
  longer shows." Neither does: `add_event_controller.dart:328` writes
  `address: address.trim()` unconditionally and
  `event_details_save_pipeline.dart:109` does the same; `isDayOff` appears in
  neither save path. Type an address on a personal block, then tick Day off → the
  field disappears but the address is stored on the record, invisible everywhere
  (`_DayOffBody` renders no address row). This is the "long comment vs.
  predicate" shape that has shipped two bugs here before.
- **Fix:** clear `address` when `isDayOff` in both `buildUpdatedRecord` and
  `AddEventController.submit` (matching the `clientId`/`clientName`/`clientPhone`
  treatment) — that is what the sentence promises — or correct the comment.

### B6 — The live availability path drops the fail-closed rule the one-shot path enforces · severity: **low** · confidence: medium

- **Where:** `lib/features/calendar/application/assignee_availability_provider.dart:53-61`
- **Problem:** `findClashingAppointments` reads the raw map and passes
  `windowUnknownIds`, so a doc with unparseable `startTime`/`endTime` clashes
  unconditionally (`assignee_availability.dart:47-54`, pinned by "a doc with
  unparseable times is kept"). The live reduction calls `clashingAppointments(…)`
  with **no** `windowUnknownIds`, and by then `AppointmentRecord.fromMap` has
  substituted `DateTime.now()`. So the same legacy/console-written row is dropped
  from the picker when the calendar's open range covers the span and kept when it
  doesn't — two surfaces, two answers, from the rule that exists so they can't
  disagree.
- **Fix:** either have the range stream expose the unparseable ids alongside the
  records, or state the limitation in the doc comment on
  `assigneeAvailabilityProvider` so the next reader doesn't take the "same pure
  rule" claim literally.

### Checked and clean

`offerableAssignees` / `assigneeOfferState` / `mergeRetainedAssignees` all key on
the stored `employeeIds` as documented; `_covers` is sound against `fetchStart`;
every `Stream.listen` in `lib/` passes `onError`; **no `ref.read` sits after an
await or inside a catch** anywhere in `lib/`; EN/FR ARB keys are in lockstep;
`functions/day_slice_utils.js` is still in step with `appointment_day_slice.dart`.

---

## 🔵 Areas to improve

Ordered by payoff. Nothing here is auto-applied — each reshapes code or adds
tests.

### Highest payoff (~7 h, three are one-liners)

#### I1 — `assertAdmin` has zero direct tests and gates 8 of 14 callables · impact: **high** · effort: XS (~30 min)

`functions/security.js:241-251`. **Verified:** every reference to `assertAdmin`
in `functions/__tests__/` is a `jest.mock` stub — the real predicate
`role !== "admin" || status !== "active"` is never executed by any of the 1376
tests. Untested: a **disabled admin**, a missing `usersByUid` bridge row, the
`permission-denied`/`wave/not-admin` code. Its two siblings in the same file
*are* pinned (`assertFreshReauth` 5 tests, `enforceDurableRateLimit` 8) — this is
the one hole in an otherwise complete row. Drop the `status !== "active"` clause
and a deactivated admin keeps full write access to `deleteClient`,
`createEmployeeAccount`, `deleteEmployeeAccount` and all five Wave callables,
with nothing noticing. Copy the harness from `rate_limit.test.js`.

#### I2 — `matchClientDocs` builds a full record above the match test its own comment forbids · impact: **high** · effort: S

`lib/features/clients/data/firebase_clients_repository.dart:331`.
`ClientRecord.fromMap` runs for **every** doc in the scan window; the comment
directly below it (`:333-338`) states the rule — *"anything computed above this
`continue` is paid ~200× over for nothing"* — and the line above breaks it. The
sibling `matchHistoryDocs` (`firebase_appointments_repository.dart:612`) does it
correctly, reading the three fields it needs off the raw map. The window is 5000
docs and a committed search keeps 25 → up to **4975 discarded record
constructions per uncached search**, each ~22 map reads plus a `contacts` list
parse and a freezed constructor. Order of 10⁵ throwaway allocations; ~100–250 ms
of search latency at a 3–5k roster. Runs inside `compute`, so latency not jank.
**Fix:** add a raw-map sibling to `ClientSearchPolicy.index` (must reproduce the
`name ← businessName` fallback per `.claude/rules/clients.md`) and call `fromMap`
only after the `continue`. Mirror `matchHistoryDocs`.

#### I3 — A `catch` that swallows behind a comment saying it doesn't · impact: **medium** · effort: S

`lib/features/clients/widgets/sections/client_job_history_section.dart:47-48`.
The comment reads "logging happens elsewhere." **It doesn't:**
`fetchClientHistory` (`firebase_appointments_repository.dart:394`) has no
try/catch, `pageToCap` has none, and the provider's `onError:`
(`appointment_history_providers.dart`) covers only the `onLocalWrite` invalidate
subscription — not the fetch. This widget is the provider's only consumer and
imports no logger. The query needs the composite `(clientId ASC, startTime DESC)`
index and index drift is live here (the 2026-08-22 deploy deliberately omitted
`firestore:indexes`). A `FAILED_PRECONDITION`, rules rejection, or cold offline
read shows "Couldn't load the appointment history" on every admin client detail
while Crashlytics stays silent. **Fix:** `ref.listen` on the data→error
transition (shape already in-repo at `dashboard_screen.dart:61-78`) — *not*
inside `.when`'s error branch, which the rules forbid as rebuild spam.

#### I4 — `assigneeAvailabilityProvider`'s live-vs-fallback routing has no test · impact: **high** · effort: S (~1.5 h)

`lib/features/calendar/application/assignee_availability_provider.dart:36-81` —
zero references in `test/`. The surrounding cluster is superbly covered
(`assignee_resolver_test.dart` pins all five documented traps;
`assignee_availability_scope_test.dart` pins the three "answers nothing"
carve-outs) but none of those reach the provider. Untested: the `_covers`
boundary, the live reduction over `openCalendarRangeProvider`, and **the
`findClashingAppointments` fallback** — which `CLAUDE.md` calls out by name:
*"without it a date past the open range makes every clash invisible and the
picker silently reports everyone as free."* That failure mode has no error, no
log, and no visual difference from "nobody is busy." **This is the only unpinned
seam in the feature shipped in this very HEAD commit.** `ProviderContainer` +
overrides; no Firebase needed.

#### I5 — `deleteClient` callable guard chain unexecuted · impact: **high** · effort: S (~1 h)

`functions/clients.js:68-78` (69.2% stmt / 50% func). `performDeleteClient` is
100% covered; the wrapper is not. Untested: non-admin rejection,
`unexpected-field`, and that `assertPayloadShape` precedes limiter consumption —
the `.claude/rules/security.md` ordering rule, restated verbatim in a comment
above the function. `allow delete` on `/clients` is withdrawn in rules, so this
is the **only** client-delete path.

#### I6 — `deleteAccount` orchestration untested (irreversible, App Store 5.1.1(v)) · impact: **high** · effort: S (~1.5 h)

`functions/account.js:37-70` (0% branch / 0% func). Every *piece* is tested; the
*wiring* is not. Untested: guard order auth → `assertPayloadShape(new Set())` →
`assertFreshReauth` → limiter → work; that `assertFreshReauth` precedes the
limiter (its own comment: "so a stale-auth rejection doesn't burn one of the
caller's deletion slots"); that the `stale-auth` code reaches the client — **a
string contract the Flutter client branches on**; the `onAuthFailure` →
`internal/delete-auth-user-failed` mapping. Every other callable family has
ordering tests.

#### I7 — `notifications.js`: 5 tests, none of which invoke a handler · impact: **high** · effort: M (~4 h)

`functions/notifications.js` — 33.3% stmt / **0% branch / 0% func**. The existing
tests are `fs.readFileSync` + regex source assertions. Untested: the **per-rider
`try/catch` isolation** in `sendDailyJobDigest` (digest → Live Activity TTL prune
→ `runWaveDaily`) and `sendUpcomingJobReminders` (travel → overdue sweep), plus
`apnsAuth()`'s null/trim path. The file's own comment calls that isolation "the
whole safety argument" for merging six Cloud Scheduler jobs into three. Collapse
two riders into one `try` and a single bad appointment silently kills the TTL
prune *and* the whole daily Wave drain+import — while the schedule reports green.
v2 handlers expose `.run()`.

### Migration & script hygiene

#### I8 — A comment asserts a pending irreversible migration already ran · impact: **medium** · effort: XS

`lib/features/calendar/data/appointment_images_store.dart:11-12`. The file says
the `pictures` array is *"gone — nothing reads it, nothing writes it, and
`clear-appointment-picture-arrays.js` **emptied it** on every document that
predates the change."* Introduced in `7ace6528` (the CONTRACT commit). But
`docs/DEPLOYMENT.md:653`, written the same day, says *"STILL OUTSTANDING: step 3
… then step 4 (the irreversible clear script)"*; `:411-425` gates step 4 on the
fleet ageing out; and `firestore.rules:705-708` says the arrays *"survive until
`clear-appointment-picture-arrays.js` runs."* No deploy-log row records it
running. **The two things that comment would license removing — the `pictures`
rules size cap and the clear script — are exactly the two the runbook says must
stay** until the fleet moves off builds that still write the array (1.46.1/1.45.0
do). **Fix:** correct the comment to future tense. Do not act on it as written.

#### I9 — `clear-appointment-picture-arrays.js` `main()` is 0% covered · impact: **high** · effort: M (~4 h)

`functions/scripts/clear-appointment-picture-arrays.js:161-269` (31.1% stmt).
`planClear`/`needsRecount`/`storedImageIds` have 13 good tests; the paging loop,
the **two `--dry-run` gates**, and the `doc.ref.update` that deletes `pictures[]`
do not. This is the pending irreversible runbook step, and this repo has already
shipped exactly this bug ("a backfill whose `--dry-run` wrote everything then
threw"). Broader: across `functions/scripts/` (3526 LOC, 36.5% stmt) **not one
`main()` is exported or invoked by any test**. Next by LOC×risk: `backfill.js`
(12.7% stmt / **2.8% branch**), `restore-business-client-names.js` (25.9%),
`drain-wave-queue.js` (38.5% — pushes to a live third-party API).
**Do this before running the clear script against prod.**

#### I10 — Spent one-shot scripts still executable · impact: **medium** · effort: S

- `functions/scripts/backfill-client-phone-from-name.js` — its own header reads
  `// !! SUPERSEDED 2026-08-14 — DO NOT RUN THIS SCRIPT AGAIN. !!` …
  *"Re-running THIS script now would redo that damage."* The most destructive
  re-run available in that directory, and **the only guard is a comment.**
  Referenced from no runbook. Suggest deleting script + test; the history it is
  "kept for" is in `.claude/rules/clients.md:259` and git.
- `functions/scripts/restore-client-name-halves.js` — purpose discharged (prod
  dry run empty, 0 of 703, 2026-08-21) but **no committed doc records that**, and
  `docs/plans/README.md:156-161` still says it is needed. A future operator reads
  the README and re-runs a repair against clean data. Record the empty dry-run,
  then retire.
- `functions/scripts/restore-business-client-names.js` — hardcoded restore table,
  **no run record anywhere**. Confirm whether it ran, record the answer, retire.
- `functions/scripts/count-legacy-image-urls.js` — the **only** script in the
  directory with no jest test, and its `countArrayUrls` half is *the* security
  claim gating step 4. Add a spec before leaning on it.

#### I11 — `docs/plans/README.md:156-171` is stale on two counts · impact: medium · effort: XS

`:168` says *"Three orphaned Cloud Scheduler jobs are still live"* vs
`docs/DEPLOYMENT.md:494` *"RESOLVED 2026-08-23, there were none."* `:164-167`
quotes the superseded `13 photos / 10 appointments` run and *"the app build is
the only step still outstanding"* vs `DEPLOYMENT.md:396` (14/11) and `:653`
(steps 3 **and** 4). This is the index a future session reads first.

### Dead code (verified; none auto-removed)

#### I12 — `AuthBannerKind.success` has never been constructed · impact: medium · effort: XS

`lib/features/auth/widgets/auth_banner.dart:7`. **Verified:**
`grep -rn "AuthBannerKind.success" lib test` → no output; all four `AuthBanner`
call sites omit `kind:`, so it defaults to `.error` forever. `isError` is always
true, so five ternaries are dead branches and the `ValueKey` can only emit
`banner_error_*`. **Owner call:** delete the enum + field, **or** wire it at
`forgot_password_screen.dart:233`, which sits right above `_SentPanel` and is the
obvious "reset email sent" surface.

#### I13 — `_hubRoute`'s `userName`/`userEmail` are never supplied · impact: medium · effort: S

`lib/routes/app_routes.dart:171-172`. All three callers pass only `isAdmin:` and
`employeeId:`. **Latent gap, not just dead weight:** on the cold-start fallback
branch a drawer tap to Team/Clients/Live map builds `HubShell` with empty
name/email, so a Settings push from that shell gets `SettingsArgs(name: '',
email: '')`. The redirect branch is unaffected. **Don't just delete** — either
drop both params or thread name/email through the three hub arg classes; the
second closes the gap.

#### I14 — A dead server constant disagrees with the live client by 10× · impact: medium · effort: XS

`functions/live_activity_registry.js:49,84,373`. `TOKEN_TTL_MS` (3 d) and
`activityTokenExpiry()` are dead — its own comment at `:46` says *"No write path
actually uses this."* The real owner is `live_activity_token.dart:19`
(`liveActivityPushToStartTtl = Duration(days: 30)`). Harmless today; anyone
"wiring up" the server helper would cut push-to-start token life 30 d → 3 d and
silently kill cold-start Live Activities. Delete both, or leave a one-line
pointer to the Dart owner. **Never revive the 3 d value.**

#### I15 — Small dead exports · impact: low · effort: XS

- `functions/day_slice_utils.js:113,231` — `isOvernightRecord()` exported, never
  called in production (added 2026-08-10, test-only since). No Dart twin, so it
  dilutes the file's hand-mirror contract.
- `functions/wave/mappers.js:512` — `IMPORT_FIELD_CAPS` exported to nobody (used
  internally at `:145`; zero hits elsewhere, tests included). Drop the export
  line, keep the const.
- `lib/features/calendar/domain/month_grid.dart:6` — `monthGridMaxRows` is
  referenced only by a test while its doc says "Used to bound layout." Correct
  the comment or inline `6` in the test.

### Convention drift

#### I16 — Six sign-in log tags use an unregistered `login.*` convention · impact: **high** · effort: XS

`sign_in_controller.dart:182,189,196,226,233` and `login_screen.dart:57`:
`'login.auth_cache_save'`, `'login.remember_email'`, `'login.sign_in'`,
`'login.resume_after_sign_up.auth_cache_save'`, `'login.resume_after_sign_up'`,
`'login.prefill_email'`. **Verified: zero of them appear in the "meant to be
EXHAUSTIVE" registry** in `.claude/rules/error-handling.md`. Since notices
dropped support codes (2026-08-04) the registry is the only place a tag lives —
so **the entire sign-in path is invisible to a Crashlytics search by registry
tag**, and the registry has `ACCT-SIGNOUT`/`AUTH-SETUP` but no tag for sign-in
itself. **Fix:** rename to `AUTH-SIGNIN` / `AUTH-PREFILL` and register them, or
document `login.*` as an exception. Also: `resumeAfterSignUp` is named for the
sign-up flow P4c deleted — it now serves account *setup*.

#### I17 — `logContext:` is an undocumented fifth tag-hiding shape · impact: medium · effort: XS

`splash_controller.dart:46,51` — a helper taking `required String logContext` and
calling `logger.warn(logContext, …)`; call sites `:81`, `:103` pass `'SPLASH …'`.
`.claude/rules/error-handling.md` lists four shapes (named `tag:`, positional,
interpolated, ternary) and not this one. No tag is currently missing, but the
rule says *"describing the shapes beats counting the sites"* — the shape list is
the mechanism that keeps the registry exhaustive. Add it.

#### I18 — Minor drift · impact: low · effort: XS

- `functions/clients.js:25` + `functions/employee_accounts.js:140` define
  `const APP_CHECK = {enforceAppCheck: true}` twice while five other sites inline
  the literal — three spellings of one constant, against
  `functions/CLAUDE.md:236` ("shared guards belong in `security.js`").
- `functions/scripts/restore-business-client-names.js:43` imports
  `assertKnownFlags` from a **sibling script** rather than `_flags.js` (11 of 12
  scripts use `_flags`). One line — and deleting I10's neighbour would break it.
- `.claude/rules/frontend.md` claims a stale `FormSheetScaffold` comment survives
  in `add_client_sheet_test.dart`; `:49` now reads `FormSheetFrame`. Drop the
  half-sentence.

### Performance

#### I19 — `shortAssigneeName` is O(N²) in regex splits on the keystroke path · impact: medium · effort: S

`lib/features/calendar/domain/assignee_resolver.dart:117`; call sites
`employee_picker.dart:68`, `personal_block_clash_dialog.dart:600`. The picker
hoists the `names` list out of the chip loop with a comment saying inlining it
*"made the naming pass quadratic on a widget that rebuilds on every form
keystroke"* — but **the quadratic part is inside the helper, not the list**: it
re-scans all of `among` doing `split(_nameGap).first.toLowerCase()` per candidate,
for every employee. Hoisting removed N allocations, not N² splits. The clash
dialog is worse — it rebuilds `among` **per chip** (`:601-602`), the exact
pattern the picker's comment claims to have fixed. At N=40: ~1600 regex splits +
~3200 string allocations per rebuild, on the main thread, and the picker rebuilds
on every keystroke in the client-search field. **Fix:** pass a precomputed
`Map<String,int>` of lowercased first-name counts, built once per build; then
hoist it out of the clash dialog's `Wrap` loop.

#### I20 — `ClientSearchPolicy.normalize` makes 9 passes and 9 strings per call · impact: low · effort: S

`lib/features/clients/domain/policies/client_search_policy.dart:32` —
`toLowerCase()` + 8 chained `replaceAll(RegExp)`, each scanning and allocating.
Called once per document via `index()` inside both matchers over 5000-doc
windows: order of 10⁷ character copies and ~45k transient strings per search.
Only worth doing while I2 is open — together they are the search-latency fix.
Single pass over code units; keep the public signature (existing tests pin it).

### Maintainability

#### I21 — A reentrancy skip is conflated with a validation failure in both save controllers · impact: medium · effort: S

`add_event_controller.dart:237` and `event_details_controller.dart:435` return
`Invalid` on a double-tap (`if (state.isSubmitting) return const
AddEventInvalid();`). `.claude/rules/error-handling.md` mandates a `Busy` member
for exactly this and names the three that were fixed
(`EventDetailsActionBusy`, `EmployeeSaveBusy`, `ClientSaveBusy`) — **these two
*save* families were missed.** Latent today (both call sites no-op for `Invalid`
and `Busy` alike), but it is the same ambiguity class as the bug that shipped
"marked as complete" without a write. Neither has a double-tap test.

#### I22 — `personal_block_clash_dialog.dart` is a 773-line "dialog" with 11 types · impact: medium · effort: M

A dialog that owns a 5-member sealed `_RowState` machine, the appointment
**reassignment write path** (`_openRow`/`_swap`/`_undo`/`_write`), and
`_replaceAssignee` — a private pure function carrying two documented traps. It is
also where B2 and B3 live. **Highest-payoff single split in the tree:** lift the
write path + `_RowState` + `_replaceAssignee` into `calendar/domain/` or
`calendar/application/`. The file already has 13 widget tests, so extraction is
low-risk, and it makes `_replaceAssignee`'s legacy-status trap directly testable
(currently only its positional-pairing half is pinned).

#### I23 — 65 of 324 `build()` methods (20%) exceed the project's own ~60-line limit · impact: low-medium · effort: M

Top offenders: `details_action_bar.dart:33-139` (107),
`client_view_body.dart:33-133` (101), `details_edit_body.dart:86-185` (100),
`additional_contacts_section.dart:155-253` (99),
`appointment_date_rows.dart:100-198` (99), `month_year_picker.dart:72-169` (98),
`auth_scaffold.dart:45-142` (98), `notice_listener.dart:184-281` (98).
**Honest read:** this is a stated-limit-vs-reality mismatch more than a defect —
none is doing hidden logic, and the 61–70 tail is noise. Either fix the top ~5,
or revise the number in `.claude/rules/code-quality.md` to something the tree
actually holds (~100) so the rule stops being decorative. Suggest both.

#### I24 — The one genuine 3+ duplication worth extracting · impact: medium · effort: S

`busy_conflict_dialog.dart:45`, `personal_block_clash_dialog.dart:194`,
`series_scope_dialog.dart:71` — the only three `return Dialog(` sites in `lib/`,
all repeating an identical 12-line frame (`insetPadding: EdgeInsets.symmetric(
horizontal: 26, vertical: AppSpacing.sp24)` → `RoundedRectangleBorder(circular(
AppRadius.rDialog))` → `Padding(all: sp24)` → `Column(min, start)`). The raw `26`
is an untokenized magic number repeated 3×. Suggest `AppDialogFrame` in
`lib/shared/widgets/dialogs/`, beside the existing `confirm_dialog.dart`.

*Explicitly checked and left alone*, per the anti-defaults: `showMapChoices` vs
`showEmailChoices` (2 instances); the `busyEmployees`/`start`/`end` trio (3, but
two are members of **different sealed families** — a shared base would break the
exhaustiveness that is their whole point); `isAdmin`/`employeeId` ctor params;
`dispose(){_controller.dispose()}`. Also left: `submit()` (142 lines) and
`save()` (139) — both **linear, not branchy**, roughly a third invariant-encoding
comments; extracting would serve one caller each.

#### I25 — ~350 LOC of production UI that never renders on the only shipping platform · impact: medium · effort: M — **owner call**

`context.isCupertino` (`lib/core/adaptive/adaptive.dart:7`) reads
`Theme.of(context).platform`, always `TargetPlatform.iOS` on a shipped build, so
every `else` branch behind it is unreachable in production — including a ~45-line
hand-built Material bottom sheet duplicated in `address_map_launcher.dart:54`
**and** `email_compose_launcher.dart:49`, plus `new_account_dialog.dart:21,87`,
`delete_account_dialog.dart:61`, `confirm_dialog.dart:21`,
`adaptive_pickers.dart:12,33`, `adaptive_action_sheet.dart:36`,
`hub_shell.dart:239`, `app_back_button.dart:66`. **The tension:** the doc comment
says the seam exists so widget tests can force either look, and 9 test files do
force `TargetPlatform.android`. So it is not dead by the analyzer's reckoning —
it is code kept alive by its own tests. Same family as the `web/`/`windows/`
scaffold decision, so **reporting, not recommending deletion.** If you keep it,
the cheap win is moving the Material branch *into* `showAdaptiveActionSheet`
(2 callers, already named for it). If you drop it, ~350 LOC and 9
platform-forcing test files go with it.

#### I26 — `AppointmentFormFields` takes 31 constructor parameters · impact: low · effort: XS

`appointment_form_fields.dart:115-147`. Two grouping objects already exist, and
the file documents the criterion for staying loose (nullability a reader needs to
see at the call site). Sound — but `onDayOffChanged` and `onAllDayChanged` are
`required` and loose, so **2 of the 6 loose callbacks don't meet the stated bar.**
Narrow drift, not a redesign.

### Remaining test gaps

#### I27 — `MyDetailsScreen` has four `catch` sites and zero failure tests · impact: medium · effort: S

`my_details_screen.dart:146, 222, 302, 344`. `my_details_screen_test.dart` (11
tests) contains **not one `thenThrow`** — it covers seeding, the "later snapshot
doesn't clobber typing" trap, offline fast-fail and role gating, but never a
throwing repository. So `ME-SAVE` ×3 and `ME-EMAIL`, and the three `error_intro*`
keys they compose, are unexercised. Largest error-path hole in `lib/`; every
other save controller has explicit failure tests.

#### I28 — `ClientSaveBusy` is the only Busy member never asserted · impact: medium · effort: XS

`client_form_controller.dart:94, 121`. `employee_form_controller_test.dart` has a
dedicated reentrancy group (3 tests) and `event_details_controller_test.dart`
asserts `EventDetailsActionBusy` at three sites; `client_form_controller_test.dart`
(12 tests) never asserts `ClientSaveBusy`. Given all three previously returned
`SocketException('in-flight')` and rendered "you appear to be offline" while
online, the un-pinned one is the one that can regress back.

#### I29 — The `DateFormat` memoization invariant has no pin · impact: medium · effort: XS

`month_grid.dart:58, 72-91` — four caches, zero tests. `CLAUDE.md` documents the
regression this prevents (30–90 constructions per rebuild on every day tap and
month swipe). A "simplification" back to a direct constructor produces no test
failure, no lint and no error — only jank. Four lines:
`expect(identical(longDateFormatFor('en'), longDateFormatFor('en')), isTrue)` per
accessor.

#### I30 — Remaining `functions/` gaps, ranked · impact: medium-high · effort: ~7 h total

- **`bridge.js:138-142`** — the invalid-role skip, whose own comment documents a
  **shipped regression** (a doc with no `role` threw inside a `retry: true`
  trigger, the `usersByUid` bridge was never written, "every rules gate that
  resolves through it failed for that person"). `VALID_ROLES` has zero references
  in any test. Also uncovered: `:189-206` (stale-bridge delete), `:247-252` (the
  auth-access rethrow `retry: true` depends on).
- **`maintenance.js:22-27, 36-81, 98-104`** — the *decisions* are perfect
  (`maintenance_policy.js` is 100/100/100, all three destroy-data rules pinned —
  the `CLAUDE.md` claim is accurate). What is untested is the **wiring**: that
  `purgeExpiredHistory` hands `runHistoryPurge` a real `db`, a `deleteImages`
  actually bound to `purgeAppointmentImages`, and `now`. Mis-wire one dep and the
  only unattended irreversible deletion either orphans Storage bytes or stops
  validating magic bytes.
- **`appointment_scan.js`** — `grep -r "candidate cap" __tests__/` returns
  **zero**: all three sweeps can silently truncate with nothing asserting the
  warn. The `descending` direction is pinned at only **1 of 3** call sites —
  `runTravelAwareReminderSweep` uses `startTime` **asc** (the odd one out) with
  no assertion, against a docstring spending two paragraphs on how getting it
  wrong "silently discards exactly the jobs the sweep exists for."
- **`places.js:157`** — the autocomplete rate-limit *rejection* is uncovered, as
  is the >200-entry eviction sweep. Ties to S3.
- **`client_job_count.js:95-111`** — the `recountClientJobs` trigger wiring: the
  `Promise.all` fan-out for a **reassignment** (two client ids) and the
  log-then-rethrow `retry: true` depends on.
- **Callable failure-path cells:** `deleteEmployeeAccount` (0% of the callable
  body); `createEmployeeAccount` (**no `unexpected-field` test pinning its
  `#compat-1.47.0` allowlist** — `.claude/rules/security.md` calls removing a key
  from it a BREAKING change, and nothing pins the set); `completeEmployeeSetup`
  (no malformed-payload / limiter-rejection test).

#### I31 — Small gaps and robustness · impact: low · effort: XS each

- `notice_listener.dart:157,162` — two `CurvedAnimation`s never disposed
  (`dispose()` covers only `_controller`); its own sibling
  `fade_in_item.dart:49-50` does it correctly. No leak-tracker configured, so CI
  cannot catch it.
- `add_client_sheet.dart` — mixes in `ClientFormState` but never calls
  `disposeAdditionalContacts()`. Latent by design (contacts aren't offered on the
  add sheet) but a loaded gun for the obvious parity request, with no
  compile-time signal.
- `firestoreStringList` (`core/utils/firestore_parsing.dart:36`) has no direct
  test while both siblings in the same file have explicit "unexpected type"
  cases. `CLAUDE.md` flags it as ONE-owner precisely because the history filter
  reads raw maps through it — *"a search that quietly stops finding a crew
  member, with nothing logged."*
- `Debouncer.tagged` (`core/utils/debouncer.dart:57`) is never exercised — all 6
  tests use the raw constructor. The factory exists specifically to force logger
  resolution at the construction site, and the one call site that deviated
  shipped a FATAL.
- `nameInitials` — pure logic, 4 call sites, zero tests; `parts[0][0]` indexes a
  UTF-16 code unit, so a non-BMP first character yields a broken half-surrogate.
- `confirm_dialog.dart:19` `message!` is protected by a **debug-only `assert`**
  stripped in release.
- `OnboardingScreen` (243 LOC) is only asserted to *exist*, never driven, and is
  in no scale sweep. First thing a new user sees; a build failure there is
  invisible until a fresh install.
- `notice_listener.dart:165-167` — uncancellable `Future.delayed`;
  `mounted`-guarded, so only a closure held ~6 s. Defensible as-is.

---

## Notes / uncertainties

- **No auto-fixes were applied**, because none were available: the analyzer,
  `dart fix`, eslint and the unused-file heuristic all came back empty. The tree
  is genuinely clean at the mechanical level.
- **Dependency scan:** all four heuristic hits verified as false positives —
  `build_runner`/`freezed` (9 `.freezed.dart` files exist),
  `flutter_launcher_icons` (config block at `pubspec.yaml:179`), and
  `google_maps_flutter_ios_sdk9` (deliberate direct-dependency SPM swap,
  documented at `pubspec.yaml:91-95`, registered in
  `GeneratedPluginRegistrant.m`).
- **l10n verified clean:** 732 EN / 732 FR keys, **0 orphans**, **0 EN↔FR
  drift**, **0 missing `@key` blocks**, 0 placeholder mismatches. No l10n pass
  needed — this is the first audit where that section is empty.
- **Also verified clean:** 107 providers, 0 unreferenced · all 12 route constants
  live · 326 widget classes all constructed · 24 sealed families / 91 subclasses
  all constructed · all 43 `TourStepId` members live · **zero** TODO/FIXME/HACK
  markers in `lib/` and `functions/` · zero BOMs · zero `throw Exception(` · no
  `FirebaseFirestore.instance` in any widget · exactly the 3 sanctioned SnackBar
  sites · all 6 debouncers use `Debouncer.tagged` · all 14 `DateFormat` sites
  hoisted or memoized · `guardedOffline` has exactly the two documented
  carve-outs · the status allowlist is byte-identical in
  `firebase_appointments_repository.dart:283` and `firestore.rules:440`, with
  `overdue` correctly absent from every write path.
- **`#compat-1.47.0` must stay.** The repo is 1.51.0+80 but
  `docs/DEPLOYMENT.md:250` records the fleet at 1.46.1/1.45.0; removing it fails
  Create *and* Reset password on every device in the field.
- **Environment note:** `.worktrees/p7b-wave-invoices/` is a live registered
  worktree (branch `p7b-wave-invoices`, gitignored). It doubles repo-wide grep
  results — all searches above were scoped to `lib/`, `test/` and `functions/`.
- S3 depends on GCP console state that cannot be verified from the repo.
- The ms figures in I2/I19/I20 are reasoned estimates from the code, not
  measurements.

---

Say **"do everything but the pre-ship"** and I'll implement every finding above
except the Pre-ship checklist (the photo-migration clear script and its S1
token-rotation prerequisite, which are deliberate launch-time actions).

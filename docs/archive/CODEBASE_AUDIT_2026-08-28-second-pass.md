# Codebase Audit — 2026-08-28 (second pass)

Scope: whole repo — `lib/` (401 Dart), `functions/` (JS), `test/` (319),
`functions/__tests__/` (66 suites), `firestore.rules`, `storage.rules`,
`firestore.indexes.json`, both ARBs.
Baseline: **working tree** on `redesgin` at `fb4c88a6`.

> ## Read this first — what this pass is
>
> An audit ran **earlier today** against this same commit and its 31
> implemented fixes are the **69 modified + 4 untracked files still
> uncommitted** in this tree. This second pass therefore audits *that
> uncommitted work*, not a fresh tree. Findings already closed by it are not
> repeated; its six deliberately-deferred items are carried forward in
> **Still open from the earlier pass**.
>
> **Headline:** the earlier pass extracted `functions/recount_claim.js` whose
> own header declares it the **"ONE owner"** of the recount claim protocol
> "because a second hand-written copy is a second chance to get that order, the
> staleness takeover, or the fail-open backwards." It migrated only **one of
> the two** counters. `appointment_images.js` still carries a complete second
> copy — so the module extracted to prevent drift *is itself the second copy*,
> and the invariant its header states was violated on arrival. **Four of five
> independent reviewers surfaced this without prompting.**
>
> Nothing found is exploitable, and nothing blocks a ship.

## ✅ Resolution — all 17 implemented, 2026-08-28

Every reported finding (S1, B1–B4, I1–I12) is closed. The 🟡 section stands
as written (the audit's own call was "defer" / "left alone deliberately") and
so does **Still open from the earlier pass**.

`flutter analyze` **No issues found!** · `flutter test` **2942/2942** ·
`functions` jest **1530/1530 across 67 suites** · `npm run lint` clean.

| # | What was done |
|---|---|
| S1 | `updatedAt == request.time` added to the employee mark-done branch. |
| B1 | `appointment_images.js` routes through `debounceRecount`; six duplicated bodies and three constants deleted; the duplicated claim tests dropped for adapter-level ones. |
| B2 | `.doc()` moved inside the `try`; `clientIdOf` also screens `"."`/`".."`. |
| B3 | `launchFailureRecord` — one owner for the URL-free record, carrying `PlatformException.code`. |
| B4 | Left as-is (rule-conformant) + a `fakeAsync` test pinning the 3-retry / 4.1 s splash budget. |
| I1–I3 | `buildingKeysIn` memoized on `_CachedClientScanWindow`; the filter and the row builder read that map. |
| I4 | Debounce gated on `mayShareABatch`. |
| I5 | New `functions/__tests__/appointment_scan.test.js`, 17 cases. |
| I6 | Three loggers hoisted above their callbacks. |
| I7 | `_DayOffText`/`_DayOffRail` extracted; `DetailsActionBar` split into three builders; `ClientDetailViewBody`'s handlers hoisted. |
| I8 | `segmentsOf` and `sumCounts` unexported. `CLIENT_RECOUNT_CLAIMS` KEPT — I11's test asserts it, which is what the audit said would earn it. |
| I9 | Redundant index deleted — **see the caveat below**. |
| I10 | The `setThrows` takeover-write branch is now tested (plus a B2 regression case). |
| I11 | `recountClientJobs` adapter tested via `.run()` with `recount_claim` mocked. |
| I12 | Sentence corrected to name `isValidDocIdField` and the Admin-SDK/console bypass. |

### Two deviations from the report, both deliberate

- **I4's gate drops the `seriesId !== appointmentId` clause.**
  `add_event_controller.dart:318,334` writes the series ROOT in the SAME
  `WriteBatch` as its siblings and stamps it with its own id, so excluding it
  would leave the root recounting alone while its siblings collapse to a
  second recount — two aggregates where the point is one. The gate is
  `dayCount > 1 || seriesId != ""`.
- **I9 carries a caveat the report did not weigh.** The three-field composite
  that serves the query as a prefix is `"density": "SPARSE_ALL"`, so it omits
  any document with **no `startTime`**, where the deleted two-field index did
  not. The Dart model always writes one, so only a legacy or console-written
  row is affected — but `countFutureAssignments` is the caption that must err
  towards over-reporting. If such rows are ever found, restore the two-field
  index rather than re-reasoning about it. Recorded in
  `.claude/rules/appointments.md`.

### Still needs a deploy / console trip

`firestore.rules` (S1) and `firestore.indexes.json` (I9) are changed but not
deployed, on top of the backend delta this tree already carried. The stale
`(employeeIds CONTAINS, endTime DESC)` index still needs its CONSOLE delete;
the `(employeeIds CONTAINS, endTime ASC)` one I9 removed goes with it on the
same trip.

## Summary

- **Auto-fixed (safe, mechanical):** 13 — 11 `dart fix` lints across 6 files,
  1 hand-fixed `cascade_invocations`, 1 stray-blank-line cleanup.
- **Reported for your decision:** 17 (🔴 1 security · 🟠 4 bugs · 🔵 12 improvements).
- **Verification:** `flutter analyze` **No issues found!** (restored from 12
  info lints) · `flutter test` **2938/2938** · `functions` jest **1503/1503
  across 66 suites** · `npm run lint` clean.

### The mechanical scan is clean — recorded so it isn't re-derived

**0** orphan Dart files (import-graph over all 401, from `lib/` **and**
`test/`; only `main.dart`, correctly), **0** dead Riverpod providers (all 110
have >1 `lib/` reference), **0** dead route constants (all 12, grepped by
string value), **0** orphaned ARB keys, **0** EN/FR drift (**749 = 749**), **0**
ARB keys missing `@key`, **0** unused dependencies (all 6 heuristic hits
verified false positives, each already documented in `pubspec.yaml`), **0**
`TODO`/`FIXME`/`HACK`/`XXX`/`TEMP`/`REMOVEME` markers, **0** BOMs, **0**
commented-out code blocks, **0** `throw Exception(...)`, **0**
`FirebaseFirestore.instance` in UI, **0** `isDark` styling branches, **0**
`DateFormat` constructed in a cell/item builder, **0** leaked
subscriptions/controllers/timers, **0** missing `mounted` guards, exactly the
**3** sanctioned SnackBar sites, and **25 trigger definitions ↔ 25 `index.js`
exports, exact 1:1**. Of 830 public top-level symbols, 55 had no cross-file
reference and **all 55 were cleared by hand** as extension-member or
file-local use.

## ⚠️ Pre-ship checklist

**Empty.** Re-verified: `grep -rn 'pre-ship'` across `lib/`, `functions/` and
`test/` returns nothing, as does a marker grep of every kind. Nothing is gated
on launch.

## Auto-applied cleanups (review the diff)

| File | Change | Why |
|---|---|---|
| `lib/shared/widgets/feedback/status_chip.dart:4` | directive ordering | `directives_ordering` |
| `lib/features/home_widget/application/widget_sync_service.dart:66` | 3 stray blank lines → 1 | residue of a deleted closure |
| `test/core/utils/reentrant_sync_test.dart:123` | `_GenerationHost()..invalidateSync()` | `cascade_invocations` (hand-fixed; `dart fix` can't) |
| `test/core/utils/reentrant_sync_test.dart` | 2 × public type annotations | `type_annotate_public_apis` |
| `test/core/security/appointment_status_rules_test.dart` · `.../appointment_status_values_test.dart` · `.../event_details_run_member_test.dart` | 3 × unnecessary import | `unnecessary_import` |
| `test/features/calendar/domain/appointment_day_slice_test.dart` · `.../event_details_run_member_test.dart` | 5 × redundant argument | `avoid_redundant_argument_values` |

> Ten of these sit in test files the **earlier pass itself added**, so they
> postdate its recorded `No issues found!`. `CLAUDE.md` states the baseline is
> `No issues found!` — "any lint you see is yours" — so a dirty baseline makes
> the next change's real lint indistinguishable from noise. It is clean again.

## 🔴 Security

Every callable re-verified: all 15 set `enforceAppCheck`, guard order is
auth → `assertAdmin`/identity → payload → re-auth → rate limit → work at all of
them, `assertFreshReauth` still fails closed on a missing token,
`createEmployeeAccount` hard-codes `role: "employee"`, `generateStartingPassword`
uses `crypto.randomInt` and is never persisted, no HTTP/CORS endpoint exists,
storage deny-all fallback and server-side magic-byte validation are intact, all
4 credential fields pass `kCredentialImePersonalizedLearning`, and role is read
only from Firestore. **No critical, high, or medium findings.**

The new `functions/recount_claim.js` is **not a callable** — it is an internal
helper for a `retry: true` trigger, so App Check/auth/payload/rate-limit do not
apply. Its write surface is correctly closed: `firestore.rules:103-110` denies
client read *and* write on both claim ledgers, and both carry TTL policies.

### S1 — Assignee `updatedAt` is unconstrained on the mark-done branch · low · confidence high
- **Where:** `firestore.rules:680-685`
- **Risk:** the branch admits `updatedAt` into `affectedKeys()` with no type
  check and no `== request.time` pin, unlike the `presence` rule at `:426`
  which forces `serverTimestamp()` for exactly this reason. A modified employee
  client can write `status: 'done'` with an arbitrary — future, past, or
  non-timestamp — `updatedAt` on any appointment they are assigned to. Impact
  is **audit-trail integrity only**: no server-side logic branches on an
  appointment's `updatedAt` (the sole logic read is `presence.updatedAt`,
  already pinned). Hardening, not an exploitable defect.
- **Fix:** add `&& request.resource.data.updatedAt == request.time`. The
  shipped client already sends `FieldValue.serverTimestamp()`, so no live write
  breaks. Needs a rules deploy.

## 🟠 Bugs

### B1 — `recount_claim.js`'s "ONE owner" invariant is violated on arrival · medium · confidence high
- **Where:** `functions/recount_claim.js:3-17` (the claim) vs
  `functions/appointment_images.js:64, 73, 104, 113, 125, 251, 292, 336` (the
  second copy). `grep` confirms `appointment_images.js` never
  `require("./recount_claim")`; only `client_job_count.js:21` does.
- **Problem:** the header states the module exists because **two** counters need
  the protocol — appointment `pictureCount` and client `jobCount` — and "a
  second hand-written copy is a second chance to get that order, the staleness
  takeover, or the fail-open backwards." Only `jobCount` was migrated.
  `appointment_images.js` still declares `isAlreadyExists`, `claimBody`,
  `defaultSleep`, `claimRecount`, `releaseRecount`, `debouncedRecountPictures`,
  plus `RECOUNT_CLAIM_STALE_MS` (15 s) and `RECOUNT_CLAIM_TTL_MS` (5 min) —
  byte-identical semantics and numbers to the new module's. The drift it was
  extracted to prevent is therefore live *today*: the next change to the
  staleness window, the fail-open branch, or the release-before-aggregate order
  lands on one counter and silently not the other. Photos are the worse half —
  a suppressed-and-uncounted photo corrupts `pictureCount` with only a server
  log.
- **Fix:** route `debouncedRecountPictures` through
  `debounceRecount(RECOUNT_CLAIM_COLLECTION, appointmentId, () => recountPictures(...), deps)`
  and delete the six duplicated bodies and three constants (keep
  `RECOUNT_CLAIM_COLLECTION` — it becomes the argument). Then delete the ~14
  duplicated claim tests at `functions/__tests__/appointment_images.test.js:315-493`,
  keeping only those asserting `recountPictures` itself. The rules blocks and
  TTL policies for **both** ledgers already exist, so this is purely a code
  swap. If you'd rather not migrate, the header must be rewritten — but then
  the module's stated reason for existing is gone.
- **Do NOT fold in** `claimSeriesNotice` (`notification_utils.js:582`, a third
  ledger): it claims-and-holds for dedupe rather than releasing before an
  aggregate. It looks similar and is deliberately different.

### B2 — The documented FAIL-OPEN doesn't cover the one error that precedes the `try` · low · confidence high (low on reachability)
- **Where:** `functions/recount_claim.js:74` — `const ref = db.collection(collection).doc(key);` sits one line *above* `try {` at `:75`.
- **Problem:** the JSDoc at `:63-66` promises "any ledger error returns true, so
  a broken claim collection degrades to the un-debounced behaviour rather than
  silently stopping every recount." But `.doc()` throws **synchronously** on an
  invalid id (`.`, `..`, or `/`). `clientIdOf` (`client_job_count.js:32-41`)
  screens only `/` and empty. A console- or Admin-SDK-written appointment with
  `clientId: "."` makes `claimRecount` reject, `recountClientJobs` rethrow, and
  `retry: true` turn it into the redelivery storm `clientIdOf` exists to
  prevent. Unreachable from the app (Firestore auto-ids), but it inverts a
  stated contract.
- **Fix:** move line 74 inside the `try`. One line.

### B3 — The launch-failure PII fix also discarded the diagnosis · low · confidence high
- **Where:** `lib/core/launchers/external_uri_launcher.dart:35-39`,
  `lib/features/maps/address_map_launcher.dart:127-133`
- **Problem:** introduced by the earlier pass. Suppressing the exception object
  is correct — `url_launcher_ios` quotes the offending `tel:`/`mailto:`/Maps
  URL, which `recordError` would serialize into Crashlytics. But substituting
  `StateError('${e.runtimeType}')` throws away `PlatformException.code`, the
  only thing separating "no app handles this scheme" from "malformed URL" from
  a channel failure — and Crashlytics now groups every launch failure of every
  scheme under one synthetic type.
- **Fix:** keep the type-only record but carry the code where it exists:
  `e is PlatformException ? 'PlatformException(${e.code})' : '${e.runtimeType}'`.
  Still URL-free, so the PII property is preserved.

### B4 — Three retry sites doubled their budget by dropping explicit `delays:` · low · confidence high
- **Where:** `lib/features/splash/application/splash_controller.dart:67`,
  `lib/features/auth/application/active_user_identity_provider.dart:37`,
  `lib/features/calendar/data/firebase_appointments_repository.dart:399`
- **Problem:** each previously passed `const [500ms, 1500ms]`; they now inherit
  `kAuthPropagationDelays` = `[400ms, 1200ms, 2500ms]`. Three attempts instead
  of two, and up to **4.1 s** of backoff instead of 2.0 s before a
  `permission-denied` surfaces. The splash one is **user-visible**: a cold start
  on a deleted or deactivated account now sits on the splash screen ~2.1 s
  longer before sign-out.
- **Fix:** none if intended — this is rule-conformant (`error-handling.md`
  mandates the single ladder owner), so it reads as deliberate. Flagged only
  because it is an uncommitted user-facing latency change with nothing pinning
  it. If the splash budget matters, pass `delays:` there with a comment.

## 🔵 Areas to improve

### I1 — Every client write recomputes every building key over the whole scan window, on the UI isolate · high · confidence high
- **Where:** `lib/features/clients/application/clients_providers.dart:74-78` →
  `lib/features/clients/data/firebase_clients_repository.dart:243` →
  `lib/features/clients/domain/policies/client_building.dart:104`
- **Opportunity:** `clientBuildingCountsProvider` is watched unconditionally in
  `ClientsListView.build` (`clients_list_view.dart:455`), so it is on the
  always-open path — not just when the Building menu opens. It chains to
  `clientBuildingsProvider`, which watches `clientsRefreshProvider`, bumped by
  **every** add/edit/archive/delete. `_patchWindow`
  (`firebase_clients_repository.dart:81`) builds a *new*
  `_CachedClientScanWindow`, discarding both `late final records` and
  `late final buildings`. Per client write, synchronously on the UI isolate:
  N × `ClientRecord.fromMap` plus N × `buildingKeyFor` (~8 regex `replaceAll`,
  `splitApt`, 2 × per-codeunit `normalize`). At ~700 clients that is roughly
  **15–25 ms — one to two dropped frames right behind the archive-swipe
  animation**; at the documented `_clientScanLimit` of 5000, **~100–180 ms**, a
  visible freeze. Unlike `searchClients` (`:277`), none of it is offloaded via
  `compute`.
- **Suggested improvement:** memoize the per-client key alongside the other two
  derived values on `_CachedClientScanWindow`
  (`firebase_clients_repository.dart:437-457`) — add
  `late final Map<String, String?> buildingKeys`, populated by a `buildingsIn`
  variant returning the keys it already computes and currently throws away.
  **That one map also closes I2 and I3.** This is the only finding in this
  report that costs a user-visible frame drop on a routine path.

### I2 — `fetchClientsByBuilding` recomputes those same keys a second time · medium · confidence high
- **Where:** `lib/features/clients/data/firebase_clients_repository.dart:236-239`
- **Opportunity:** a full second O(window) pass of the work I1 just did and
  discarded, on every building-filter selection.
- **Suggested improvement:** free once I1's key map exists — becomes a map
  lookup per record.

### I3 — `buildingKeyFor` runs per row inside the paginated item builder · low · confidence high
- **Where:** `lib/features/clients/widgets/views/clients_list_view.dart:228`
- **Opportunity:** the *counts* are correctly one shared reduction, but the
  *key* is recomputed per row on every rebuild and scroll-in — ~0.2 ms/frame,
  below budget alone, but this is the third site paying for the same value.
- **Suggested improvement:** read `_buildingKeys[client.id]` from I1's map.

### I4 — `debounceRecount` adds 2 s and doubles the writes on every *single* appointment write · medium · confidence high
- **Where:** `functions/recount_claim.js:141-148`, called from
  `functions/client_job_count.js:127-132`
- **Opportunity:** the debounce is unconditional, but the batch it absorbs is
  only reachable for a multi-day run day-document or a repeat-series sibling.
  On the overwhelmingly common single create/delete it buys nothing and costs
  `await sleep(2000)` of billed wall-clock plus a claim `create()` **and**
  `delete()` — taking the common path from 2 writes to 4, **doubled**, to save
  writes on the rare path. The batch win itself is real and large (14 writes → ~3).
- **Suggested improvement:** keep the mechanism, gate it. Read the after-doc
  once and go straight to `recountOne` when the write cannot be part of a batch
  — `(a.dayCount || 0) > 1 || (a.seriesId && a.seriesId !== event.params.appointmentId)`.

### I5 — `appointment_scan.js`: a shared boundary helper with two fail-fast throws and a truncation warn, and zero tests · medium-high · confidence high
- **Where:** `functions/appointment_scan.js:48-89` (92 lines), required by both
  `notification_utils.js:59` and `travel_utils.js:34`
- **Opportunity:** `grep -rn "appointment_scan\|scanAppointmentWindow" functions/__tests__/`
  → **no output**. Its own docstring says "Get it wrong and the cap silently
  discards exactly the jobs the sweep exists for… NOTHING here is optional, and
  that is the point." Three behaviours are unpinned: the
  `!label || !consequence || !logger` throw, the
  `typeof descending !== "boolean" || !loOp || !hiOp` throw, and the
  `snap.size === cap` truncation warn. Those throws exist to stop a *future*
  call site omitting an argument — a guard that only ever runs in production is
  a guard nobody knows is broken. Its Dart twin `pageToCap` **does** have
  `test/core/data/paged_scan_test.dart`.
- **Suggested improvement:** one small `functions/__tests__/appointment_scan.test.js`
  with a fake `db` — four cases: each throw, the warn firing at `size === cap`,
  and no warn below it.

### I6 — Three `ref.read(loggerProvider)` deferred inside a stream `onError` callback · medium · confidence medium
- **Where:** `lib/features/clients/application/appointment_history_providers.dart:39-41`
  and `:54-56`; `lib/core/notices/notice_listener.dart:38-39`
- **Opportunity:** `.claude/rules/error-handling.md` states the rule and names
  its casualty — resolving the logger inside a later-firing callback is what
  "escaped a `Debouncer` timer callback into the zone handler as a **FATAL**",
  and the rule closes with "`ref.read` inside a `catch` is mechanically
  greppable; treat a new one as a bug." These are the same shape at a different
  callback type, and the two `appointment_history_providers` sites are
  `autoDispose.family`, where the `Ref` is disposed the moment the last
  listener goes and `ref.read` then throws `StateError`. Practical risk is low
  — `ref.onDispose(sub.cancel)` runs before teardown — but "practical risk is
  low" is the reasoning that shipped the fatal once.
- **Suggested improvement:** hoist `final logger = ref.read(loggerProvider);`
  above each `.listen(`. One line moved per site.

### I7 — Five `build()` methods over 100 lines · low · confidence high
- **Where:** `appointment_card.dart:260` (`_DayOffStrip`, **123**),
  `details_action_bar.dart:33` (**107**), `appointment_date_rows.dart:109`
  (**105**), `details_edit_body.dart:86` (**103**), `client_view_body.dart:32`
  (**103**)
- **Opportunity:** **66 of 328** `build()` methods exceed the project's ~60-line
  rule. The tail is mostly 61-70 and chasing all 66 is not proportionate — only
  the top three are worth doing.
- **Suggested improvement:** `appointment_card.dart:260` — extract the
  `Positioned` `CustomPaint` rail as `_DayOffRail` and the text column as
  `_DayOffText`; `build` drops to ~60. `details_action_bar.dart:33` — three
  mutually exclusive `if` blocks become three builder methods on the same class,
  no new widget classes. `client_view_body.dart:32` — hoist the four leading
  `ref`-dependent closures into a `_handlers(context, ref, client)` helper.

### I8 — Three `module.exports` entries nothing requires · low · confidence high
- **Where:** `functions/client_job_count.js:144` (`CLIENT_RECOUNT_CLAIMS`),
  `functions/scripts/backfill-client-address-street.js:260` (`segmentsOf`),
  `functions/scripts/count-multi-day-appointments.js:268` (`sumCounts`)
- **Opportunity:** each is used file-locally but exported to nothing — not even
  a test. Over-broad export surface, not dead logic.
- **Suggested improvement:** drop the three names from their `module.exports`.
  (`CLIENT_RECOUNT_CLAIMS` becomes genuinely useful if you take I4's gate or
  B1's migration — decide it alongside those.)

### I9 — Redundant composite index on `appointments` · low · confidence medium
- **Where:** `firestore.indexes.json` — `(employeeIds CONTAINS, endTime ASC)`
- **Opportunity:** a strict prefix of
  `(employeeIds CONTAINS, endTime ASC, startTime ASC)`, which Firestore serves
  for the same queries (`countFutureAssignments`, `fetchEmployeeWidgetWindow`).
  Costs index storage and write latency proportional to
  `documents × employeeIds.length`; no billed write ops, so storage/latency
  only.
- **Suggested improvement:** delete it alongside the stale
  `(employeeIds CONTAINS, endTime DESC)` index your notes already flag for
  console removal — one trip to the console for both.

### I10 — An unused injection point in the new claim tests · low · confidence high
- **Where:** `functions/__tests__/recount_claim.test.js:39` (`opts.setThrows`)
- **Opportunity:** defined and never used by any test. It covers the takeover
  `set()` failing — which shares a `try` with the `get()` and so reaches the
  same fail-open `catch`, but is a distinct branch (the takeover decided the
  claim was stale, then failed to rewrite it). Otherwise this suite is strong:
  it pins both fail-open branches, the swallowed release failure, the
  `Timestamp`-vs-`Date` read, the staleness boundary on both sides, and the
  three that matter most — batch collapse, release-before-aggregate, and a
  throwing aggregate leaving no claim behind.
- **Suggested improvement:** add the one test, or drop the injection point.

### I11 — `client_job_count.js`'s debounce adapter has no test · low · confidence high
- **Where:** `functions/client_job_count.js:125-137`;
  `functions/__tests__/client_job_count.test.js` is untouched in this tree and
  covers only `clientsToRecount` and `recountOne`.
- **Opportunity:** the adapter chooses three things that are each silent when
  wrong — the collection name (which must match the rules block *and* the TTL
  index), `settleMs`, and rethrowing so `retry: true` still means something. A
  typo in the collection name yields a permanently deny-all ledger,
  `claimRecount` fails open on every call, and the debounce simply never
  engages: no error, no log, just the old cost profile. This is the only one of
  the two counters whose adapter is uncovered.
- **Suggested improvement:** one test asserting the trigger's `Promise.all` path
  calls `debounceRecount` with `CLIENT_RECOUNT_CLAIMS` and rethrows on a failing
  recount — the shape `appointment_images.test.js` already uses.

### I12 — A stale comment now contradicts the rules · low · confidence high
- **Where:** `functions/client_job_count.js:38-39`
- **Opportunity:** it reads "firestore.rules validates only `status` on
  /appointments, so a malformed clientId can reach here." That stopped being
  true when `isValidDocIdField` (`firestore.rules:459-461`) was added — rules
  now cap `clientId` at 128 chars and reject `/` on both create and admin
  update. The guard itself is still correct defense-in-depth for the
  Admin-SDK/console path (and B2 depends on it) — only the sentence is wrong.
- **Suggested improvement:** correct the sentence, keep the guard. Related and
  unverified: `isValidDocIdField` still admits `"."` and `".."`, reserved
  Firestore path segments — which is exactly what B2 turns into a retry storm.

## 🟡 Code-quality suggestions (optional)

- `functions/scripts/` — the paged appointment scan is hand-spelled in **4**
  scripts (`backfill-appointment-images.js:191`,
  `clear-appointment-picture-arrays.js:185`, `count-legacy-image-urls.js:157`,
  `count-multi-day-appointments.js:112`), all
  `orderBy("__name__").limit(PAGE_SIZE)` + `startAfter` + empty-page break. The
  directory already has the shared-helper convention (`_batch.js`, `_flags.js`,
  `_project.js`). **Defer** — these are finished one-shot scripts and the payoff
  is only for the next one written. This is the same item the earlier pass
  raised as a broader `_scan.js` proposal.
- 3 raw `EdgeInsets.all` sub-token nudges (`employee_color_grid.dart:194` → 3,
  `language_toggle.dart:22` → 3, `form_helpers.dart:62` → 2). `AppSpacing`
  defines only `sp4/8/12/16/24/32`, so **none has an unambiguous target** —
  left alone deliberately, consistent with `design_tokens.dart:118`.
- `employee_color_grid.dart:200-206`'s 7-stop `SweepGradient` is the only
  hardcoded `Color(0xFF…)` outside the token layer and carries a comment saying
  the spectrum "deliberately ignores the theme". Not drift.

## Still open from the earlier pass (unchanged, carried forward)

Not re-derived — these remain your call:

- **T1 — no Firestore/Storage rules *evaluation* anywhere.** All ten
  `test/core/security/*_rules_test.dart` read the rules as **text** and assert
  with `RegExp`. For ~870 lines across 20 `match` blocks, an operator-precedence
  slip or a clause that never fires passes the entire suite. **Still the largest
  single coverage gap in the repo**, and S1 above is precisely the class of
  thing it would catch. Needs `@firebase/rules-unit-testing` + the emulator in CI.
- `themes.dart` light/dark builders share **121 identical lines** of ~180; and
  its 5-positional-parameter `s()` helper called 16 times.
- `TopRouteObserver` has no production reader (~50 lines + spec + 91-line test).
- Seven completed-migration scripts in `functions/scripts/` (this pass's
  dead-code leg independently reached the same list, adding `backfill.js`).
- Six structure refactors (`personal_block_clash_dialog.dart` 804,
  `event_details_controller.dart` 715, `firebase_appointments_repository.dart`
  690, `main_calendar_screen.dart` 618, `notification_utils.js` 926,
  `travel_utils.js` 887). **New measurement this pass:** the `functions/` files
  are **40-48% JSDoc** — `worker.js` is 968 total but **432 code**,
  `travel_utils.js` 887/**486**. By code lines none is a god file, and each is
  well tested. `notification_utils.js` (**506** code, 9 subjects) is the only
  one worth watching.
- Five remaining test gaps (`backfill.js --prune-orphans`, the two
  `Platform.isIOS` gates, `OpenCalendarRange.clearIfHolding`,
  `matchHistoryDocs`, the `AppointmentSeriesEditor` plan/commit seam).
- S2 (`placesAutocomplete` per-instance limiter — out of repo) and S3 (9
  moderate transitive advisories under `firebase-admin@13` — no safe fix).

## Notes / uncertainties

- **The tree is uncommitted and now carries this pass's fixes too.** The
  earlier pass's 69 modified + 4 untracked files and my 13 mechanical fixes are
  interleaved in one working tree; they were never separable. `git diff` shows
  both. The backend delta still awaits a deploy that includes a
  `firestore.rules` change and the new `clientRecountClaims` block + TTL policy.
- I did not reproduce a `StateError` for I6; that classification rests on
  documented Riverpod 3 behaviour, hence medium confidence.
- B2's reachability is genuinely low — it needs a console or Admin-SDK write.
  Reported because it inverts a contract the module's own JSDoc states, not
  because I expect it to fire.
- `android/` is regenerated on disk again and contains
  `android/app/google-services.json`. Re-verified **not** committed
  (`git check-ignore -v` → `.gitignore:78:/android/`) and `local.properties`
  carries only `sdk.dir`/`flutter.sdk` — **no `MAPS_API_KEY` resurrection**. The
  ignore entry is doing its job; leave it.

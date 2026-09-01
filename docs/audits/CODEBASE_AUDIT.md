# Codebase Audit — 2026-08-31

Scope: whole repo — `lib/` (407 Dart, 59,788 lines), `functions/` (136 JS),
`test/` (323), `functions/__tests__/`, `firestore.rules`, `storage.rules`,
`firestore.indexes.json`, both ARBs.
Baseline: working tree on `redesgin` at `292a43a5`.

> ## Read this first — what this pass is
>
> A proactive "find more ways to improve and optimize" sweep, not a
> regression hunt. Every finding from the audits through 2026-08-28 is closed,
> so this is fresh ground. Five independent reviewers ran in parallel over the
> whole tree (security, bugs, dead code + convention drift, performance,
> maintainability + test coverage).
>
> **The static layer is pristine and yielded ZERO auto-fixes** — `flutter
> analyze` clean, `dart fix` "Nothing to fix!", `functions` ESLint clean, no
> orphan files, no unused dependencies, no dead providers, no dead routes, 768
> ARB keys with zero EN/FR drift and every one referenced, zero convention
> violations. There is nothing in this audit's diff but this document. That is
> the headline, and it is why every finding below is a judgment call rather
> than a cleanup.
>
> **Two findings are HIGH, and both are the same failure shape the repo has
> been bitten by before: a documented decision that one call site does not
> implement.**
>
> 1. `futureSeriesRecords`' `anchor:` parameter exists *specifically* to stop a
>    moved run-day from breaking "this and following days" — its own doc
>    comment narrates the bug. Three of four call sites pass it. The edit path
>    does not.
> 2. `notifyAppointmentChanges` is registered without `retry: true` on the
>    stated reasoning that "a duplicate push is worse than a rare missed one".
>    Its per-recipient loop has two unguarded `await`s, so one transient
>    failure drops the remaining recipients permanently — while five sibling
>    fan-outs in the same file carry the guard with a comment explaining why.
>
> Nothing found is exploitable. Nothing blocks a ship.

## ✅ Resolution — B1 and B2 fixed, 2026-08-31

Both HIGH findings are closed. The other 18 stand as reported.

| # | What was done |
|---|---|
| B1 | `planPropagate` passes `anchor: appointment`, matching the cancel and delete call sites. Two run-scoped cases added to `appointment_series_editor_test.dart` — both reproduce the bug first (`[]` on the moved day 1, `['r1','r5']` on day 4) and pass after. |
| B2 | The per-recipient loop body in `notification_utils.js` is wrapped in `try`/`catch` with a tagged `logger.warn`, matching the five sibling fan-outs. Three cases added to `notification_utils.test.js` — failed send, failed recipient read, and that the failure is logged. All three verified failing against the unfixed file. |

**Deliberately left alone:** the series claim ordering. If a send throws after
`claimSeriesNotice` committed, the claim still stands for its window and
suppresses the sibling occurrence. Releasing it is a separate decision about
claim semantics — the ledger is documented as fail-OPEN by design — and is
noted in a comment at the site rather than changed here.

**B3 is now the cheapest follow-up.** It shares a root with B1: the
scope dialog's count still runs on `startTime` with no terminal filter, so on a
run it disagrees with the write B1 just corrected.

## ✅ Resolution — I1, S3 and two new write-cost findings, 2026-08-31

A follow-up pass looked for optimization on ground the first sweep did not
cover — bundled assets, font weights, and the **write** side of the index
manifest (the perf pass was scoped to Dart runtime and Firestore *reads*).
Assets and fonts came back clean and are recorded under **Verified clean**
below. The index manifest did not.

| # | What was done |
|---|---|
| I1 | `_CachedClientScanWindow` carries `records` and `buildingKeys` across a local write via a new `patched(next, changedId)`, re-deriving only the changed client. The three `late final`s became nullable-backed getters so the patch can tell "materialized" from "never read" — when nothing has read them, a plain window is still built (correct and free). `buildings` is deliberately not carried: it is a reduction over the two maps, and carrying it would put the count/label rules in a second place. |
| S3 | `clients` / `wave.problems` exemption added, matching its twin `clients/contacts`. |
| **N1** | **Dead composite index deleted from the manifest:** `users (email, role, status)`, added 2026-05-15 for the signup-code/invite flow that P4c replaced and the `#compat-1.37.1` deletion finished off. Every surviving `users` email query is single-field equality with a `limit()`, served by the automatic index; `role`+`status` is not a prefix of it, so the two role/status queries can't use it either. It served nothing and cost write latency on every employee edit, status flip and setup completion. |
| **N2** | **Three never-queried timestamp fields exempted:** `appointments.createdAt`, `appointments.updatedAt`, `clients.updatedAt` — each was getting two automatic indexes written on every document write for a field nothing queries or orders by. `clients.createdAt` (`fetchClientsCreatedSince`) and `presence.updatedAt` (ordered) are queried and stay indexed. |

**On the tests for I1.** Unlike B1/B2 these are **characterization** tests: an
optimization must not change behavior, so the four write-shape cases
(edit-in, edit-out, archive, delete) pass **before and after** by design. The
fifth — "an untouched client is NOT rebuilt across a write" — is the one that
pins the optimization itself, asserting `identical()` on a record the write did
not touch, and it does fail against the unpatched window.

One test was wrong on first writing and the code was right: moving a client to
`7 Rue Seule` grouped it with `c3`, already there, forming a *second* building
rather than dissolving the first. The address was changed to one nothing else
in the window shares.

### ⚠️ N1 needs a console step — the manifest edit alone does nothing

Removing an index from `firestore.indexes.json` does **not** delete it in prod:
a redeploy cannot delete, and `--force` is banned here (it wiped all five live
TTL policies once, 2026-07-21). The composite must be deleted through the
console or the admin API, exactly as I9 was on 2026-08-29. The four
`fieldOverrides` additions, by contrast, apply normally on
`firebase deploy --only firestore:indexes`.

## Summary

- **Scanned:** 407 Dart + 136 JS + 3 rules/index files + 2 ARBs
- **Auto-fixed (safe):** **0** — the static layer had nothing to fix
- **Reported for your decision:** 20
  (⚠️ 0 pre-ship · 🔴 3 security · 🟠 5 bugs · 🔵 12 improvements)
  — **2 since fixed (B1, B2)**, 18 open
- **Verification (after the B1/B2 fixes):** `flutter analyze` **No issues
  found!** · `dart fix --dry-run` **Nothing to fix!** · `flutter test`
  **3035/3035** · `functions npm run lint` **clean** · `functions` jest
  **1568/1568 across 68 suites**

### Top 3 to look at first

1. **B1** — `planPropagate` omits `anchor:`; a multi-day run silently
   mis-writes or silently no-ops on "save this and following days".
2. **B2** — the change-notification fan-out drops recipients 2..N on one
   transient failure, permanently (no retry by design).
3. **I1** — `_patchWindow` discards three memos on every client write,
   putting ~700 record constructions on the UI isolate behind the
   archive-swipe animation.

## Auto-applied cleanups

**None.** `flutter analyze` reports no errors or warnings, `dart fix
--dry-run` reports "Nothing to fix!", and `functions` ESLint is clean. The
unused-file and unused-dependency heuristics both came back empty once
verified:

| Heuristic hit | Verdict |
|---|---|
| `google_maps_flutter_ios_sdk9` | False positive — native-registered SPM impl; `pubspec.yaml:93` says don't "fix" it |
| `build_runner`, `freezed` | False positive — generate the 9 `.freezed.dart` files via `part` |
| `flutter_launcher_icons` | False positive — CLI tool, config block at `pubspec.yaml:179` |

> The only file this audit changed is this document (plus archiving the prior
> report to `docs/archive/`). Nothing in `lib/`, `functions/` or the rules was
> touched.

## ⚠️ Pre-ship checklist

**Empty, verified.** Zero `TODO`/`FIXME`/`HACK` markers anywhere in `lib/` or
`functions/`, zero `TODO(pre-ship)` scaffolding, zero `XXX`/`TEMP`/`REMOVEME`.
All callables set `enforceAppCheck`. Nothing is gated on launch.

## 🔴 Security findings

### S1 — A real customer's name is committed in source and four test literals · severity: low · confidence: high

- **Where:** `functions/wave/customer_contract.js:43,128-129`;
  `functions/__tests__/wave_customer_contract.test.js:138,142,144,157,242`;
  `docs/DEPLOYMENT.md:715`
- **Risk:** The Phase-1 Wave contract module documents its `NOT_DIALABLE`
  severity decision by quoting a live production record verbatim — a named
  individual's full name paired with that customer's production Firestore
  document id. `.claude/rules/security.md` says "Never log secrets, API keys,
  tokens, passwords, or **PII**." This is PII pinned into git history: it
  survives any scrub of the working tree, replicates to every clone (this repo
  is worked from two machines), and leaves with the source if it is ever
  shared, forked, or handed to a contractor. Pairing a name with the exact
  prod doc id to look up is worse than either alone. Not an attack — a
  disclosure: anyone with repo access reads it without touching Firestore,
  App Check, or the rules.
- **Fix:** Replace the name with a synthetic placeholder in the comment and
  the four test literals (`"Contact Person"` asserts identically). Keep the
  doc id only if you want the audit trail, or move the incident detail into
  `docs/plans/` and reference it. Editing does not remove it from history — if
  that matters it needs a history rewrite; otherwise accept and stop the
  bleeding. **This is the one security finding worth acting on.**

### S2 — `ios/GoogleService-Info.plist` is recoverable from git history · severity: low · confidence: high (fact) / low (exploitability)

- **Where:** untracked now; added in `bc5a7aaa`, deleted in `6f89c3cb`.
  Correctly gitignored today at `.gitignore:14`.
- **Risk:** Carries `API_KEY`, `GOOGLE_APP_ID`, `GCM_SENDER_ID`, `PROJECT_ID`,
  `STORAGE_BUCKET`. To be explicit rather than inflate it: the Firebase iOS
  `API_KEY` is **public by design** — it ships inside every IPA — so this is
  not a credential compromise. What earns it a line is that this repo has been
  bitten by this exact shape once already (the `MAPS_API_KEY` a merge
  resurrected via `android/local.properties`, deleted 2026-08-23), and an
  *unrestricted* Google Cloud key is abusable for quota/billing even when it
  is a client key.
- **Fix:** No code change. Verify in the Cloud Console that this key is
  application-restricted to the iOS bundle id **and** API-restricted to the
  services it needs (Identity Toolkit, FCM, Firestore, Storage) — not "None".
  Rotation is not required for a key that ships in the binary anyway.

### S3 — `wave.problems` has no index exemption · severity: low (cost, not security) · confidence: high

- **Where:** `functions/wave/customer_contract.js:218` writes it;
  `firestore.indexes.json` has 40 `fieldOverrides` and none covers it.
- **Risk:** Not a security hole — a write-cost and latency one, filed here
  because the security pass surfaced it. `wave.problems` is an array of
  objects on every `clients` doc, so Firestore indexes each element's
  subfields (`field`, `code`, `severity`, `detail.length`, `detail.cap`) on
  every client write. **`clients/contacts` — the same array-of-objects shape —
  already has an exemption** (`indexes: 0`), as does `appointments/pictures`.
  This one was added 2026-08-30 and missed it.
- **Fix:** Add a `fieldOverrides` entry for `clients` / `wave.problems` with
  `"indexes": []`, matching `clients/contacts`. Needs an index deploy.

## 🔴 P2 — the travel sweep has been BROKEN in prod since 2026-08-29

**Found in `functions_get_logs`, and nowhere else.** Crashlytics could not see
it and the app never showed it. It was **60 of 60 warnings** in a 2.5-hour
window, with `has_more` — firing on every run of a 5-minute sweep.

```
sendupcomingjobreminders  code=9  travel: context query failed
The query requires an index … appointments/ employeeIds, endTime, __name__
```

**The 2026-08-28 audit caused it.** Its I9 deleted
`appointments (employeeIds CONTAINS, endTime ASC)` as a "redundant prefix" of
`(employeeIds CONTAINS, endTime ASC, startTime ASC)`. That is not a prefix
relationship: Firestore appends `__name__` to the END of the ordered fields, so
the surviving index really reads `(employeeIds, endTime, startTime, __name__)`
and no prefix of it puts `__name__` directly after `endTime` — which is exactly
what `travel_utils.js:774-778`'s `decideOrigin` context query needs
(`array-contains` + two `endTime` bounds + `orderBy("endTime")` + `limit`).

**Impact:** every travel-aware "time to leave" reminder degraded to the fixed
30-minute `reminder` kind for two days. Nothing surfaced it, because that path
is best-effort by design — it logs `travel: context query failed` and falls
through. The degradation is the documented fallback working correctly, which is
precisely why nobody noticed the feature had stopped.

**Fixed:** index restored in `firestore.indexes.json`; the reasoning recorded
in `.claude/rules/firestore-indexes.md` so it is not "simplified away" again.
**Needs a `firestore:indexes` deploy, then a build wait**, and the fix is only
confirmed when `travel: context query failed` stops appearing in the logs —
verify by re-reading them, not by assuming.

### ⚠️ Correction — N2 was wrong and is reverted

`.claude/rules/firestore-indexes.md` states that `createdAt`/`updatedAt` are
**deliberately NOT exempted** — they are what you sort and filter by in the
Firebase console when investigating a live document. N2 exempted them for write
cost without reading that, reversing a documented owner decision. **Reverted.**
S3 (`wave.problems`) stands: that is the array-of-objects shape the rule does
cover, the same case as `clients/contacts`.

The index manifest's net change is therefore three edits: drop the dead `users`
composite (N1), restore the `endTime` composite (P2), add the `wave.problems`
exemption (S3).

## ✅ Resolution — the cheap fix batch, 2026-08-31

| # | What was done |
|---|---|
| S1 | The customer's name is replaced by `"Contact Person"` in `customer_contract.js` and its four test literals, with a note saying why so nobody restores it. The doc id stays — it is the audit trail, and it was the *pairing* with a name that mattered. Editing does not purge git history; that is accepted rather than rewritten. |
| B3 | `seriesOutlook` moved out of `domain/` and beside `futureSeriesRecords` in `event_series_helpers.dart`, and now DERIVES from it — so the dialog's count cannot disagree with the write. (No domain→application import exists in this repo, so the move went that way rather than adding one.) Two new cases pin the divergences: a terminal sibling counted-but-never-written, and a run scoped on `startTime` instead of `dayIndex`. |
| B4 | The `.future` await in `_loadClientIfNeeded` moved inside a `try`, with the logger hoisted above it. It ran in a DISCARDED microtask, so an `unavailable` there recorded as a **FATAL** from a sheet that merely failed to prefill a client name. |
| I8a | `PushRegistrationController._syncGuarded`'s `try` moved up to cover the gate read and `_refreshSub.cancel()`. `sync()` is called unawaited from four sites — which is what the catch below it exists to contain. |
| I8b | `WaveSettingsSection._runWaveAction` gained a trailing `catch`. A non-`WaveFailure` throw escaped to the zone with NO notice: the admin tapped Sync and nothing visibly happened. Reuses the existing generic string rather than minting an `error_intro*` key for a path that should never fire. |

## ✅ Resolution — P1, the live-map geocode storm, 2026-08-31

**Found from production Crashlytics, not from the code.** Every finding above
came from static review; this one came from asking what users actually hit.
Worth recording as a method note: three open issues in August, **zero fatal**,
and the top one was mis-titled.

**The triage hazard first:** Crashlytics groups the top issue (34 events,
3 users) under `permission-denied` / `cloud_firestore`, but every *current*
event under it is `[firebase_functions/deadline-exceeded]` from
`placesReverseGeocode`. Two unrelated causes share one blame frame
(`_extractReplyValueOrThrow`, a pigeon file). Anyone triaging by title chases a
rules problem that does not exist. `lastSeenVersion` is 1.54.0 — the shipping
build.

**The mechanism**, from the sample event's breadcrumbs (ten identical
`ADDR-PLACES placesReverseGeocode callable failed` inside 33 ms):

1. `staff_roster_sheet.dart:218` watches `reverseGeocodeProvider` **per row**,
   inside a `ListView.separated` builder. N staff = N concurrent calls to a
   **billed** Geocoding API, fired together.
2. `google_places_repository.dart:14` sets a **10 s client callable timeout**,
   so the client gives up — but the function kept running, because
   `fetchPlacesJson` called `fetch()` with **no timeout and no
   `AbortController`** (Node's fetch has no default). Every abandoned lookup
   still spent the upstream call and the rate-limit slot it had consumed.
3. A failure was never `keepAlive`d, so a recycled row (scroll away, scroll
   back) re-requested it immediately. Budget is 120/hour per uid.

| # | What was done |
|---|---|
| P1a | **Server:** `fetchPlacesJson` arms an `AbortController` at `UPSTREAM_TIMEOUT_MS` (8 s), deliberately **under** the client's 10 s so the server gives up first and the work is never orphaned. Shared by all three Places callables. The transport log gains `timedOut`, which is what separates "the upstream is slow" from "the network broke". Three jest cases, incl. one asserting the budget stays under the client's. |
| P1b | **Client:** a failed cell is held for `kReverseGeocodeFailureCooldown` (5 min) via `keepAlive` + a release timer, then retried. "Retries later" was always the intent; this makes *later* real. The cooldown must outlast the roster's 30 s tick or the loop returns. The error still reaches the widget — the row renders "No location" off it. |

**Not claimed:** the events record `processState: BACKGROUND`, which most
likely means calls fired while foregrounded timed out after backgrounding —
not that a loop runs in the background. `TickerMode` pauses a hidden *tab*, not
a backgrounded app. And the third issue (`MapsFailureRateLimit` on
`getPlaceDetails`, new in 1.54.0) is a **different limiter** (40/15 min,
separate key) — a parallel symptom, not a consequence. The second
(`WaveAuthInvalid`) last appeared in 1.45.0 and looks aged out at 1.54.

### Two test-harness traps this hit, both already documented

- **A bare `ProviderContainer` does not inherit `main()`'s `retry: null`.**
  Riverpod 3's default exponential retry re-runs an errored provider on its
  own, so `.future` never settles and the test times out at 30 s instead of
  failing — and it confounds any call-count assertion. `.claude/rules/testing.md`
  names this exactly; the four containers now pass the same override.
- **autoDispose disposal is SCHEDULED, not immediate.** The first version of
  these tests re-listened before teardown ran, so the provider was never
  actually recycled and **all four passed against the unfixed code**. Letting
  the event loop turn after `sub.close()` is what makes the recycle real: the
  key test then reports `Expected: 1, Actual: 3` — the production bug,
  reproduced.

### Still worth considering

Neither fix reduces the **fan-out** itself: opening the roster with N staff
still issues N concurrent billed lookups. Capping that concurrency, or
resolving the roster's cities in one pass, is the remaining lever — it needs a
batch endpoint, so it is a design change rather than a fix.

### Verified clean — bundle and index manifest (2026-08-31 follow-up)

Recorded so a later pass doesn't re-derive them:

- **Bundled assets total 2.0 MB, and only 180 KB of it ships.** The 1.0 MB
  `icon.png` master is deliberately on-disk-only for
  `flutter_launcher_icons`/`flutter_native_splash`; `pubspec.yaml` bundles just
  the 512 px `brand_mark.png` derivative, with the reasoning inline. Already
  optimized — don't "tidy" the master into the bundle.
- **Every declared font weight is used.** All four `InstrumentSans` weights and
  all three `IBMPlexMono` weights (500/600/700) resolve to real `AppMonoType`
  and theme call sites. No dead weight to drop.
- **The remaining 13 composite indexes each trace to a real query**, including
  the ASC/DESC pairs on `clientId` and `status`, which genuinely need both
  directions (`propagateClientEdits` vs `fetchClientHistory`; the travel sweep
  vs the digest). `(employeeIds CONTAINS, startTime ASC)` is NOT a prefix of
  the three-field `(employeeIds CONTAINS, endTime ASC, startTime ASC)` and is
  separately needed.

### Verified clean (stated so the coverage is legible, not implied)

- **`firestore.rules` — no hole found.** Every non-admin write path is
  `hasOnly`-locked. `presence.updatedAt` and the appointment status flip's
  `updatedAt` are pinned to `request.time`. Function-owned fields (`uid`, both
  consent stamps, `waveCustomerId`/`wave`/`jobCount`, `pictureCount`) are
  denylisted on create and update. `liveActivityTokens.expiresAt` is required
  and capped at `request.time + 31d`, with the matching `COLLECTION_GROUP` TTL
  index present, so the reaper reaches every row a client can mint. Both
  status gates check `status == 'active'` rather than bridge-doc existence, so
  a deactivated employee loses job PII and photos.
- **All 13 callables** set App Check; guard order is auth → identity → payload
  → re-auth → rate limit → work everywhere; every state-changing callable is
  durably rate-limited; `rateLimits/*` is `read, write: if false`. No callable
  consumes `data.*` unvalidated.
- **Fail-closed guards.** Hunted specifically for the inverse of
  `assertFreshReauth`. Found no `if (token && token.claim !== true)`-shaped
  guard anywhere.
- **Secrets.** No hardcoded credentials. All server-side keys are
  `defineSecret`. The generated starting password is `crypto.randomInt`-derived,
  never persisted, never logged. No `*firebase-adminsdk*.json` in any ref.
- **PII in logs.** `upstreamErrorCode` extracts only an enum-shaped code;
  `enforceDurableRateLimit` logs a sha256 prefix; `changeEmployeeEmail`'s
  revert log carries `{uid, docId}` and never the addresses.

## 🟠 Bug findings

### B1 — `planPropagate` selects run siblings by `startTime`, not `dayIndex` — the anchor is never passed · severity: high · confidence: high

- **Where:** `lib/features/calendar/application/appointment_series_editor.dart:83-87`

```dart
final siblings = futureSeriesRecords(
  series,
  excludeId: id,
  after: appointment.startTime,   // <-- no `anchor:`
);
```

- **Problem:** `futureSeriesRecords`' own doc comment
  (`event_series_helpers.dart:23-33`) narrates this exact bug as the reason
  the `anchor` parameter exists: *"a run member's start date is editable, so
  moving day 1 forward past its siblings made 'this and the following days'
  select nothing and report success, while the same action on day 4 swept up
  the moved day 1."* Without `anchor`, `runIndex` is null and the predicate
  falls back to `a.startTime.isAfter(after)` — the comparison the parameter
  was added to replace.

  **Call-site audit:**

  | Call site | Passes `anchor:`? | |
  |---|---|---|
  | `event_details_controller.dart:364` (cancel) | ✅ | |
  | `event_details_controller.dart:714` (delete) | ✅ | |
  | `appointment_series_editor.dart:44` (rewrite) | ➖ | guarded by `!appointment.isRunMember` — correct |
  | **`appointment_series_editor.dart:83` (propagate)** | ❌ | **reachable by a run member via `:609`** |

  Preconditions verified: `appointment_form_fields.dart:488` hides only the
  **end**-date row on a run member, so a run day's **start date is editable**;
  `details_edit_body.dart:345-392` lets a run member reach the scope dialog,
  and `applyToSeries: true` flows to `event_details_controller.dart:609`.
  `appointment_series_editor_test.dart` has no run-scoped propagate case, so
  nothing catches it.
- **Failure scenario:** Book Mon–Fri (5 docs, `dayIndex` 1…5, Aug 1–5). Move
  **day 1** to Aug 10 (supported).
  - Edit **day 1**, choose "save this and following": `after = Aug 10`, no
    sibling starts later → `propagated = []`. Only day 1 is written; days 2–5
    keep the old title/crew/address. `_announce` sees `updatedSiblings == 0`
    and shows the plain "changes saved" notice — the admin is told nothing
    went wrong.
  - Edit **day 4**, choose the same: `after = Aug 4` matches day 5 **and** the
    moved day 1 (Aug 10) → day 1 is overwritten with day 4's fields and
    `withTimeOfDay` rewrites its clock time. The day deliberately moved out of
    the run is silently swept back in.
- **Fix:** Thread the anchor through, exactly as cancel and delete do:
  ```dart
  final siblings = futureSeriesRecords(
    series, excludeId: id, after: appointment.startTime, anchor: appointment,
  );
  ```
  Add a run-scoped propagate case to `appointment_series_editor_test.dart`.

### B2 — Change-notification fan-out has no per-recipient isolation, in a handler with no retry · severity: high · confidence: high

- **Where:** `functions/notification_utils.js:427` and `:447`, inside the
  `for (const {employeeDocId, kind} of events)` loop at `:392`
- **Problem:** Two rejectable awaits sit in the loop with no `try`:
  `await _loadRecipient(...)` (`:427` — a `users` get plus an `fcmTokens`
  subcollection get) and `await sendToEmployee(...)` (`:447`), whose
  `await messaging.sendEach(messages)` is at `:189`, **outside** its own try
  (which opens at `:192` under the comment "Nothing below may throw").

  `notifyAppointmentChanges` is registered **without `retry: true`**
  (`functions/notifications.js:89-90`: *"a duplicate push is worse than a rare
  missed one"*). So one transient FCM or Firestore failure on the first
  assignee throws out of the whole handler, recipients 2..N are never
  attempted, and the event is dropped **permanently**.

  **This reads as drift, not a decision.** Five comparable fan-outs in the
  same file carry the guard with an explicit rationale:
  `_deliverRecipientOnce` (`:487-499` — *"must still not abort the sweep for
  the remaining recipients"*), `runDailyDigest` (`:798-807`),
  `sendToActiveAdmins` (`:869-874`), `endCardOnTerminal` (`:336-350`), and
  `travel_utils.js:640-646`. The loop's *other* awaits (`updateLiveActivity`,
  `fetchEmployeeWidgetWindow`, `claimSeriesNotice`) all catch internally.
- **Failure scenario:** A 3-person job is cancelled. The `users` read for
  assignee 1 hits a transient `unavailable`. Assignees 2 and 3 are never
  attempted and never learn the job was cancelled — nothing retries, nothing
  surfaces. On a series it is worse: if `claimSeriesNotice` (`:430`) already
  committed for recipient 1 and the send then throws, the claim stands for
  `SERIES_CLAIM_WINDOW_MS` and suppresses the sibling occurrence's trigger too.
- **Fix:** Wrap `:427`–`:449` in
  `try { … } catch (err) { logger.warn("appointment-write: recipient failed", {id, employeeDocId, err}); }`,
  matching the five siblings. Leave the claim ordering alone.

### B3 — The series-scope dialog counts on a different rule than the write it describes · severity: low · confidence: high

- **Where:** `lib/features/calendar/widgets/views/details_edit_body.dart:264`
  → `lib/features/calendar/domain/series_outlook.dart:6-22`
- **Problem:** `seriesOutlook` counts every sibling with `startTime >= from`.
  `futureSeriesRecords` — which decides what is actually written —
  additionally drops `isTerminalStatusRaw` siblings, and (per B1) is meant to
  switch axes for a run. Two divergences from one dialog: terminal siblings
  are counted but never written, and a run inherits B1's axis problem so the
  number and date agree with nothing.
- **Failure scenario:** A weekly series with 5 future occurrences, one already
  cancelled. The button reads **"Save 5 visits"**; `commitPropagate` writes 4;
  the success notice says "changes applied to 3 visits". The number the admin
  confirmed is not the number that changed.
- **Fix:** Derive the outlook from `futureSeriesRecords(...)` itself so the two
  cannot disagree by construction (or give `seriesOutlook` the same
  `isTerminalStatusRaw` filter and optional `anchor`). Best done with B1.

### B4 — `event_details_controller.dart:172` — await outside the try, in a discarded microtask · severity: medium · confidence: high

- **Where:** `lib/features/calendar/application/event_details_controller.dart:172`
  (fired from `:93`)
- **Problem:** `build()` fires
  `Future.microtask(() => _loadClientIfNeeded(appointment.clientId))`. Inside,
  `:172` does `await ref.read(currentUserDocProvider.future)` **above** the
  method's try. `currentUserDocProvider` is a `StreamProvider`, so `.future`
  genuinely rejects when the stream errors before first data — the
  `docState.hasError` guard one line up covers a *settled* error, not one
  arriving during the await. The future is discarded (not `unawaited`, no
  `.catchError`), so the rejection reaches `runZonedGuarded`:
  `permission-denied` degrades to non-fatal via `isFatalUnhandledError`, but
  `unavailable` or a transport failure records as **FATAL** — from a sheet
  that merely failed to prefill a client name. `unawaited_futures` cannot see
  it because `build()` is synchronous. The two sibling microtasks at `:94-95`
  are already safe.
- **Fix:** Move the await inside the existing try, or attach `.catchError`
  logging under `APPT-OPEN`.

### B5 — The conflict prefilter cannot see a doc with no `endTime` · severity: low · confidence: medium-high

- **Where:** `lib/features/calendar/data/firebase_appointments_repository.dart:616-618`
  (`_conflictSnapshots`), consumed at `:568-582`
- **Problem:** `.claude/rules/appointments.md` says *"A record whose stored
  times DON'T PARSE clashes unconditionally… must never quietly disappear from
  a booking check."* `windowUnknownIds` implements that by reading the raw
  map. But the prefilter query is `.where('endTime', isGreaterThan: …)`, and
  Firestore **excludes documents lacking the filtered field entirely** — so a
  row with a *missing* `endTime` (as opposed to an unparseable one) never
  reaches the loop that would classify it.
- **Failure scenario:** A console-written or pre-migration appointment with
  `startTime` but no `endTime` (the case `_recordFrom`'s breadcrumb at
  `:120-126` exists for, and `day_slice_utils.js:96-100` handles server-side)
  is invisible to `findBusyEmployees`/`findClashingAppointments`. Booking over
  it reports no clash. Only reachable for legacy/console rows — the Dart model
  always writes both instants.
- **Fix:** Either state the limitation in the `windowUnknownIds` comment
  (missing-field rows are structurally unreachable here, unlike unparseable
  ones), or drop the `endTime` bound and let the Dart `dailyWindowsOverlap`
  pass narrow — it is already "COARSE by design".

## 🔵 Areas to improve

### I1 — Every client write re-derives the whole scan window on the UI isolate · impact: high · confidence: high

- **Where:** `lib/features/clients/data/firebase_clients_repository.dart:69-86`
  (`_patchWindow`) with `:446-478` (`_CachedClientScanWindow`)
- **Opportunity:** `_patchWindow` constructs a **new**
  `_CachedClientScanWindow`, discarding the `late final records` /
  `buildingKeys` / `buildings` memos. Every add/update/archive/delete also
  calls `clientsRefreshProvider.bump()`, which immediately re-runs the three
  building providers → the memos rebuild on the spot. Per write: an O(N) doc
  copy, N × `ClientRecord.fromMap` (freezed, ~25 fields + contacts parse),
  N × `buildingKeyFor` (up to 4 `_localityKey` calls, up to 4 regexes, 2
  `normalize` passes), plus `buildingsIn` re-deriving per distinct key. At the
  ~700 clients your prod notes record that is ≈700 record constructions + 700
  key derivations, **~15–40 ms on the main isolate**, i.e. 1–3 dropped frames
  landing behind the archive-swipe dismissal and the save-sheet close. Unlike
  `searchClients`, this path does **not** cross the `compute` boundary. The
  class comment at `:465-469` anticipates the hazard but solves only the
  per-surface 3× duplication, not the per-write invalidation.
- **Suggested improvement:** Patch incrementally — keep `records` and
  `buildingKeys` as mutable maps and update only the changed id in
  `_patchWindow` (`buildings` is then a cheap reduction). Failing that, move
  the derivation into the existing `compute` hop.

### I2 — Opening the Clients tab now reads the whole `clients` collection · impact: medium · confidence: high

- **Where:** `lib/features/clients/widgets/views/clients_list_view.dart:470-471`;
  `lib/features/clients/screens/clients_screen.dart:146`
- **Opportunity:** `build()` watches `clientBuildingCountsProvider` +
  `clientBuildingKeysProvider` before the filter switch, and the filter bar
  watches `clientBuildingsProvider`. All three land on the paged
  `orderBy('name')` scan capped at 5000. That window used to be paid only on a
  search or filter-chip tap; it is now paid **on tab open**, for a per-row
  "Building" pill and a menu that renders nothing when no address is shared.
  At ~700 clients that is ~700 reads + 2 sequential round-trips on top of the
  paginated list's 50 — roughly **14× read amplification** on the first
  Clients open per session, ~250–300 KB over cellular, growing linearly to the
  cap. Off the critical path (the list renders from the paged query), so this
  is read-cost, not jank.
- **Suggested improvement:** Defer `clientBuildingsProvider` /
  `clientBuildingKeysProvider` until the Address menu is first opened, letting
  `_buildingKeyOf` (`clients_list_view.dart:462`) derive keys for the ~10
  visible rows via its existing fallback. If the pill's `buildingCount` must
  stay eager, at minimum skip the fetch on the booking-flow reuse path.

### I3 — `functions/scripts/` repeats the same prod bootstrap at 14 sites · impact: high · confidence: high

- **Where:** `backfill-appointment-images.js:167`,
  `backfill-client-address-street.js:178`, `backfill-client-name-digits.js:152`,
  `backfill-client-name-with-phone.js:268`,
  `backfill-client-phone-formatting.js:125`, `backfill-client-phone-from-name.js`,
  `backfill-clients-archived.js:76`, `backfill.js:82`,
  `clear-appointment-picture-arrays.js:277`, `count-legacy-image-urls.js`,
  `count-multi-day-appointments.js`, `drain-wave-queue.js:160`,
  `restore-business-client-names.js:120`, `restore-client-name-halves.js:278`
- **Opportunity:** Each spells `argv → assertKnownFlags(argv) → dryRun =
  argv.includes("--dry-run") → initializeApp({credential: applicationDefault()})
  → getFirestore() → printTargetBanner(app, {dryRun})`. `_flags.js` owns flag
  rejection and `_project.js` owns the banner, but **nothing owns the wiring
  between them** — "resolve `dryRun` once and hand the same value to both".
  Commit `3059ac0a` ("pass the required dryRun flag to the audit's target
  banner") is exactly this drift, and repo memory records a backfill whose
  `--dry-run` wrote everything anyway. These scripts touch prod.
- **Suggested improvement:** `bootstrapScript(argv, {exact, prefixes})` in
  `_project.js` returning `{app, db, dryRun}`. Flag *lists* stay local (they
  legitimately differ) — only the wiring moves.

### I4 — `audit-wave-contract.js` is structurally untestable and runs at require time · impact: high · confidence: high

- **Where:** `functions/scripts/audit-wave-contract.js:59`
- **Opportunity:** The **only 1 of 15 scripts** with no
  `if (require.main === module)` guard and no `module.exports` at all, so
  `main()` executes at require time against whatever ADC is ambient, and a
  test cannot require the file without running it. It is the newest script in
  the tree (`485c88cb`, 2026-08-30) and per project memory its report is the
  gate holding Wave rearchitecture Phases 2–4 unwritten. `buildCustomerPayload`
  beneath it is well covered; the script's own layer is not — the `refused`
  (blocking, `!ok`) vs `flagged` (any problem) split at `:80-87`, the
  deliberately-not-gated-on-`ok` advisory path, and the `orderBy("__name__")`
  paging that exists so legacy docs missing a field aren't excluded.
  Miscounting advisory as blocking mis-sizes a program decision.
- **Suggested improvement:** Trivial — it already takes an injected `db`. Add
  `module.exports = {audit, assertKnownFlags}` plus the `require.main` guard,
  then pin blocking-only→refused, advisory-only→flagged-not-refused, both, and
  the multi-page cursor walk.

### I5 — `count-legacy-image-urls.js` predicates unexported · impact: medium · confidence: high

- **Where:** `functions/scripts/count-legacy-image-urls.js:84`
  (`countLegacyUrls`) and `:150` (`countArrayUrls`); `module.exports` at `:254`
  exposes only `assertKnownFlags`
- **Opportunity:** This script's verdict (prod count = 0) is what authorized
  permanently retiring `images.url` from the rules, the loader, the store and
  the backfill — an irreversible schema decision made on an untested count. A
  misclassification at the `storagePath !== "" → continue` branch, or an early
  exit from the `snap.size < PAGE_SIZE` loop, reads as "no legacy data". Every
  sibling exports its predicate for exactly this reason (`needsArchivedField`,
  `patchFor`, `runClear`).
- **Suggested improvement:** Export both with injected `db`; pin the three-way
  classification (has-storagePath skipped / url-only legacy / neither orphan)
  and the cursor advance.

### I6 — `toIdList` boundary rules unpinned, and its documented twin IS pinned · impact: medium · confidence: high

- **Where:** `functions/notification_policy.js:141`, exported at `:413`, used
  at 12 call sites (`notification_policy.js:204,209,215,220,221,299`;
  `notification_utils.js:312,324,325,328,329,691`;
  `travel_utils.js:591,621`)
- **Opportunity:** Zero direct test hits, and no test exercises a 128/129-length
  id or one containing `/`. Its own docstring says *"Change the 128 here and in
  `requireDocId`/`isValidDocIdField` together"* — and the `security.js` half
  **is** pinned by `security.test.js`, so the pair can drift silently.
  Over-rejection means an employee silently receives no push or travel alert,
  with nothing logged.
- **Suggested improvement:** Pin the four rejection rules, the
  exactly-128-accepted / 129-rejected boundary, and an equality assertion
  against `security.js`'s cap so the documented coupling is enforced.

### I7 — `buildSelfEmailChangedMessage` untested, and its rule is a PII rule · impact: medium · confidence: high

- **Where:** `functions/notification_messages.js:327`, called from
  `employee_accounts.js:658`
- **Opportunity:** Zero test hits while all three siblings are tested. Its
  docstring states the rule: *"Carries the NAME, never the address — this
  lands on every admin's Lock Screen and an email is PII."* A regression that
  interpolates the address is a PII leak to every admin's lock screen, caught
  by nothing.
- **Suggested improvement:** Assert the body contains the name and contains no
  `@`, in EN and FR, plus the empty-name fallback.

### I8 — Two "move the `try` up" robustness fixes · impact: medium · confidence: high

- **Where:** `lib/features/notifications/application/push_registration_controller.dart:84,92`;
  `lib/features/wave/widgets/wave_settings_section.dart:87-96`
- **Opportunity:** (a) The push controller's `try` opens at `:108`, but
  `readAccountGateInputs(...)` (`:84`) and `await _refreshSub?.cancel()`
  (`:92`) sit above it. `sync()` is invoked `unawaited` from four sites, so a
  throw there escapes to the zone handler — exactly what the catch at `:137`
  documents itself as preventing. The tell is the asymmetry:
  `PresenceSyncController._syncGuarded` puts the identical gate read *inside*
  its try. (b) `wave_settings_section.dart` catches only `on WaveFailure`, but
  the `action:` closures also run notices, `ref.invalidate` and `setState`; a
  non-`WaveFailure` throw escapes as a crash record with **no notice shown** —
  the admin taps Sync and nothing visibly happens.
- **Suggested improvement:** (a) Move `try {` up to just after
  `final generation = syncGeneration;`. (b) Add a trailing `catch (e, st)`
  logging `WAVE-$tag` and composing a notice.

### I9 — The account-exit stub trio is hand-copied across 3 test files · impact: medium · confidence: high

- **Where:** `test/features/settings/widgets/delete_account_flow_test.dart:39-62`,
  `test/core/app/account_exit_listeners_test.dart:41-65`,
  `test/core/app/device_deregistration_test.dart:28-60`
- **Opportunity:** The first two are byte-identical apart from the class
  prefix; the third is the recording variant. `.claude/rules/testing.md:29-46`
  documents all three copies **by name** and states the failure mode: without
  the loader override the test **hangs to timeout with no error naming the
  cause**. This is the "identical decision spelled in files that must agree"
  case, and `test/support/tour_test_support.dart` already sets the precedent.
- **Suggested improvement:** `test/support/account_exit_stubs.dart` exporting
  the recording trio with an optional `List<String>? calls` (null = silent
  stub), which subsumes both variants.

### I10 — Three files hold a separable concern · impact: medium · confidence: high

- **Where:** `lib/features/calendar/data/firebase_appointments_repository.dart`
  (704 lines); `lib/features/calendar/screens/day_route_screen.dart:190-267`;
  `lib/features/clients/data/firebase_clients_repository.dart:347`
- **Opportunity:** (a) The appointments repository holds CRUD writes, range
  queries/streams, conflict detection **and** the history-search subsystem
  (`:50-96`, `:465`, `:488`, plus top-level `HistorySearchScan`/
  `matchHistoryDocs` at `:652-691`). Precedent exists — `AppointmentImagesStore`
  was split out of this same class. (b) `day_route_screen`'s `_prepareBuild` +
  `_assigneesWithJobs` are 78 lines of pure derivation inside `ConsumerState`,
  reading only `_day`, `_selectedEmployeeId`, `widget.isAdmin`, and embedding
  the documented `runsOn`/`assigneeNameAt` rules — reachable only through a
  widget test today. (c) `matchClientDocs`' **6-tier relevance ladder**
  (`:400-419`) is product behaviour sitting in the data layer; the *match* half
  already lives correctly in `ClientSearchPolicy.rawMatches`.
- **Suggested improvement:** (a) Move `matchHistoryDocs` + `HistorySearchScan`
  to `calendar/domain/policies/`, keeping `_invalidateSearchCache()` on every
  write path. (b) Extract `buildDayRoute({slices, nameMap, isAdmin,
  selectedEmployeeId})` into `calendar/domain/`, leaving the identity-memo in
  the State. (c) Move the ladder beside `matchesClient`. All three are
  "when you're next in that file", not a campaign.

### I11 — Smaller test gaps and two doc/robustness nits · impact: low · confidence: high

- **Where:** `functions/notification_policy.js:86` (`ledgerBody` — zero hits,
  three call sites; its comment says `expiresAt` is the **absolute** deletion
  instant, so the TTL policy must use offset 0, a coupling to
  `firestore.indexes.json` nothing verifies);
  `lib/core/security/biometric_auth_service.dart:17,28` (real class never
  instantiated in a test; both methods are `catch → log → return false`,
  precisely the shape `.claude/rules/error-handling.md` singles out as hiding
  a broken plugin channel — and the constructor already accepts injected deps);
  `functions/scripts/count-multi-day-appointments.js:91`;
  `lib/core/validators/email_format.dart:9` (`normalizeEmail` — the **only**
  CLAUDE.md-named invariant owner with no test; three-line fix);
  `functions/wave/triggers.js:244-245` (JSDoc promises *"Never throws"* but
  `await ref.get()` is unguarded);
  `lib/features/calendar/widgets/sections/photo_picker_section.dart:56`
  (async `initState` call with no try/catch — safe today only because
  `AppointmentImageLoader` never rejects, a property of a different file that
  nothing pins)
- **Suggested improvement:** Each is a few lines. The `normalizeEmail` and
  `biometric_auth_service` ones are the best value per line.

### I12 — `build()` over the documented ~60-line limit at 56 sites · impact: low · confidence: high

- **Where:** worst are `agenda_sliver_list.dart:64` (119, though ~35 lines are
  explanatory comment), `details_edit_body.dart:86` (111),
  `appointment_date_rows.dart:109` (105),
  `additional_contacts_section.dart:155` (99), `month_year_picker.dart:72`
  (98), `auth_scaffold.dart:45` (98), `notice_listener.dart:192` (98)
- **Opportunity:** The rule in `code-quality.md` says under ~60 lines; 56
  methods exceed it. Most are cohesive widget trees where extraction would add
  indirection without adding clarity.
- **Suggested improvement:** **Do not run a 56-site cleanup.** Either extract
  the top 5 opportunistically, or amend the rule to acknowledge that a
  sliver/branch `build` legitimately runs longer. Flagged for the decision,
  not the campaign.

## 🟡 Code-quality suggestions

**None.** The convention pass found zero violations across every documented
rule it checked: SnackBar vs. notice (exactly the 3 sanctioned sites), no
`FirebaseFirestore.instance` in UI, no token-duplicating raw colors or
`EdgeInsets`, one sanctioned `isDark` branch, zero `throw Exception(...)`,
zero hand-spelled email normalization, zero raw debouncing `Timer`s, zero
`DateFormat` construction in an item builder, all 4 credential fields carrying
`kCredentialImePersonalizedLearning`, zero `ref.read` inside a `catch`, and no
log-tag registry drift in either direction.

## Notes / uncertainties

- **Deliberately not re-reported** (verified intentional): the removed
  `email_verified` guard, the removed 4th `users` read clause, the Android
  remnants, the duplicated status allowlist, the dashboard's split window, the
  one-listener roster reducer, `DateFormat` memoization, the bounded scan
  windows, `ClientJobHistorySection`'s 50-row bound, and Dart-side search
  matching.
- **Carried from 2026-08-28, still open:** the `SPARSE_ALL` prefix index drops
  docs with no `startTime` (restore the two-field index if such rows are ever
  found), and the stale `(employeeIds CONTAINS, endTime DESC)` index still
  needs its **console** delete — a redeploy cannot delete and `--force` is
  banned. B5 above is the client-side sibling of that same missing-field class.
- **Not verified:** whether any prod appointment row actually lacks `endTime`
  (B5) — that needs a prod query, and no ADC is available on this machine.
- The working tree was already dirty with in-progress calendar work
  (`main_calendar_screen.dart` grid-height fix + test + a CLAUDE.md note).
  This audit did not touch it.
- Reviewers cross-checked coverage claims by grepping for the **symbol**, not
  the filename — the documented trap where coverage lives under the caller's
  test file. That resolved 19 of 24 Dart and 8 of 11 JS candidates as
  non-gaps.

---

**Next step:** say *"do everything but the pre-ship"* and I'll implement every
finding above (the pre-ship checklist is empty, so that is all of them). Or
pick a subset — B1 and B2 are the two that change behavior users can observe.

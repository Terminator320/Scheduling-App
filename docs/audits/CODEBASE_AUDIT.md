# Codebase Audit — 2026-08-15

> **STATUS: ALL 28 FINDINGS IMPLEMENTED, 2026-08-16** (plus 2 of the 4 optional
> code-quality notes — the root `package.json` deletion and the `navPalette`
> tokens; the `TODO(#issue)` marker and the test-scaffolding duplication were
> left as recorded no-ops).
>
> Two things landed differently from the recommendation, both deliberately:
>
> - **S1** took the fuller option. Beyond correcting the loader docstring and
>   the `CLAUDE.md` paragraph, `functions/appointment_image_tokens.js` now
>   rotates `firebaseStorageDownloadTokens` on a deactivated employee's job
>   photos from `syncUsersByUid`. It also **rewrites the stored `url`** in the
>   same pass, which the finding did not mention and which is not optional:
>   rotating alone blanks those photos on exactly the old builds the `url`
>   write exists for. Needs a **new composite index**
>   (`employeeIds CONTAINS, endTime DESC`) — deploy `firestore:indexes`.
> - **I5** shipped an 82% cut (1,044,191 → 183,909 bytes) rather than the
>   "well under 150 KB" the finding predicted. That prediction assumed a flat
>   logo; the mark carries ~39k distinct colours at 512 px, and a 256-colour
>   palette measured RMS ~3 — visible banding on a brand asset for ~150 KB.
>   Kept as full RGBA; the reasoning is in `assets/images/README.md`.
>
> Verification after the work: `flutter analyze` **No issues found!** ·
> `flutter test` **2352/2352 pass** (was 2349) · `functions` ESLint clean ·
> `functions` jest **1269/1269 across 52 suites** (was 1215/48 — the new
> suites are `appointment_image_tokens`, `bridge_policy`, `scripts_batch` and
> `places_error_logging`) · `cd functions && npm ci` clean after the root
> `package.json` deletion.
>
> **DEPLOYED 2026-08-16** — indexes first in their own command (the new
> `(employeeIds CONTAINS, endTime DESC)` composite verified `READY` before
> anything else), then `functions,firestore:rules,storage`. 25 → 25, so no
> deletion prompt and no abort; all 25 reported `Successful update operation`,
> and no WARNING/ERROR log entry is newer than the deploy. See the deploy-log
> row in `docs/DEPLOYMENT.md`. The app build is NOT cut — nothing here needs
> one, but I5's asset change only reaches devices with the next build.

Scope: whole repo (`lib/`, `functions/`, `firestore.rules`, `storage.rules`,
`firestore.indexes.json`, `test/`, `lib/l10n/*.arb`, `docs/`).
Baseline: `be8e0441` on `redesgin`, working tree clean at start.

## Summary

- **Scanned:** 383 Dart files / 55k lines in `lib/`, 286 test files / 46k lines,
  99 JS files in `functions/`, 856 lines of rules, 722 ARB keys × 2 locales.
- **Auto-fixed (safe, in the diff):** 3 — all documentation-only corrections
  where a written invariant no longer matched the code it describes.
- **Reported for your decision:** 28
  (⚠️ 0 pre-ship · 🔴 3 security · 🟠 1 bug · 🔵 20 improvements · 🟡 4 code-quality)
- **Verification:** `flutter analyze` **No issues found!** (unchanged from
  baseline) · `flutter test` **2349/2349 pass** · `functions` jest
  **1215/1215 pass across 48 suites** · `functions` ESLint clean ·
  `dart fix --dry-run` "Nothing to fix".

This tree is in strong shape. The static layer is completely clean, and the
deep review confirmed — with explicit negative results — that the codebase's
distinctive disciplines are all holding: single-owner helpers, hand-mirrored
Dart↔JS twins, bounded reads, typed failures, design tokens. **The dominant
finding class this round is not broken code, it is documentation that has
drifted out from under the code it governs.** Four separate instances, three of
them fixed here and one (S1) needing your judgment because the drifted claim is
a *security* guarantee.

### Top 3 to look at first

1. **S1** — `ImageStorageService` still mints and persists a permanent,
   rules-free Storage download token on every upload, and ships it to every
   assigned employee's device inside `pictures[]`. The loader's docstring
   asserts the opposite ("there is nothing shareable to capture"). The S1 work
   from the last audit is real but narrower than written.
2. **B1** — the nightly digest's 1000-doc cap keeps the **oldest** open jobs,
   not tomorrow's, because the query orders `startTime` ASC from a floor 15 days
   in the past. The comment above it justifies the cap with reasoning imported
   from a sweep whose window starts at `now`.
3. **I1** — `functions/scripts/backfill.js` is the only script that **deletes**
   (from `usersByUid`, the collection every rules gate resolves a role through),
   and it is the only script with no test. Its three-way orphan decision is four
   interacting conditions guarding a destructive write.

---

## Auto-applied cleanups (review the diff)

All three are documentation corrections. No code, rules, or config changed.

| File:line | Change | Why |
|---|---|---|
| `CLAUDE.md:683` | `docs/plans/…` → `docs/archive/2026-08-02-multi-day-appointments.md` | File moved; this citation is load-bearing — §10 is the stated justification for the multi-day Live Activity skip. Verified §10 exists at the new path. |
| `CLAUDE.md:1711` | `docs/plans/…` → `docs/archive/2026-08-11-history-restyle.md` | Same; file moved to `docs/archive/`. |
| `functions/CLAUDE.md:209` | `OVERDUE_LOOKBACK_MS (24h)` → `(2 h)` + why | Code is `2 * 60 * 60 * 1000` (`notification_policy.js:55`), reduced 2026-08-13 when the sweep folded into the 5-minute timer. The doc implied ~4× more outage-recovery slack than exists. |

A fourth doc drift was found and fixed as part of this set: the live
account-deletion bullet in `CLAUDE.md` pointed at a `ref.listen` in `main.dart`.
`main.dart` contains **zero** `ref.listen` calls — the listener lives in
`AccountExitListeners._listenForDeletedAccount`
(`core/app/account_exit_listeners.dart:144`). The mechanism itself is intact
(`previous: prev` is passed correctly at line 156); only the pointer was wrong.

> Full detail is in `git diff`. Nothing below this line was auto-changed.

---

## ⚠️ Pre-ship checklist

**Empty — verified, not assumed.**

| Grep | Scope | Result |
|---|---|---|
| `pre-ship`, `preship`, `#pre-ship` | `lib/` `functions/` `test/` `ios/` | **0 hits** |
| `enforceAppCheck` | `functions/**/*.js` | **11 hits, all `true`** — zero `false` |
| `kShowTesting`, `testingFlag`, `debugAllow`, `bypassAuth`, `skipAuth` | `lib/` `functions/` | **0 hits** |
| `lib/core/testing_flags.dart` | filesystem | does not exist (deleted as documented) |

No destructive action is wired up for testing. No ship-blocker.

---

## 🔴 Security findings (review required)

### S1 — A permanent, rules-free download token is still persisted per upload and shipped to every assignee · severity: **medium** · confidence: **high**

- **Where:** `lib/core/images/image_storage_service.dart:75` (mints
  `getDownloadURL()`) → `lib/features/calendar/data/firebase_appointments_repository.dart:829`
  (`_imageToFirestoreMap` writes `'url'` into the parent `pictures[]`) →
  `firestore.rules:573` (`allow read: if isAdmin() || isAssignedEmployee(...)`).
- **Risk:** an employee assigned to a job receives the whole appointment
  document, `pictures[]` included, on their device.
  `firebaseStorageDownloadTokens` values are **stable per object and never
  expire**, and fetching `…?alt=media&token=…` serves the bytes over plain
  HTTPS with **no auth and no `storage.rules` evaluation**. A modified client —
  or simply reading the app's local Firestore persistence in the app container —
  yields a link that keeps working forever, including after
  `deactivateEmployee` has revoked the credential, disabled the Auth account and
  flipped the `status == 'active'` gate.
- **Important nuance:** this is **not** the accepted residual "a URL captured
  under an OLD build still works". The current build is still *minting and
  persisting a fresh one per upload*, so the exposure is ongoing, not
  historical. The last audit's S1 correctly ended **render-time** minting; it
  did not end **upload-time** minting.
- **Documentation conflict — this is the part needing your call:**
  `lib/core/images/appointment_image_loader.dart:27-28` states "there is nothing
  shareable to capture", and `CLAUDE.md` describes the bytes-from-memory scheme
  as ending "the app *manufacturing* a permanent rules-free link". While the
  array carries the URL, both overstate the guarantee. The `url` write is
  deliberate and correct (old builds render from it) — the problem is that the
  written guarantee doesn't carry its exception.
- **Fix:** drop the `url` write at the already-planned CONTRACT step. Until
  then, either add a `firebaseStorageDownloadTokens` rotation to the
  deactivation path (`syncUsersByUid`), or — at minimum, and cheaply — correct
  the loader docstring and the CLAUDE.md paragraph so a future reader does not
  build on a guarantee that isn't in force yet. The subcollection writer
  (`_imageToSubcollectionMap`) and `PendingUploadStore` already strip `url`
  correctly, so the migration path is sound.

### S2 — The in-memory photo cache is a process-lifetime singleton that survives sign-out · severity: **low** · confidence: **high** (lifetime) / **low** (exploitability)

- **Where:** `lib/core/images/appointment_image_loader.dart:12` (`Provider`, not
  `autoDispose`; `_cache` up to 24 MB), with no clear in
  `lib/core/app/account_exit_listeners.dart`.
- **Risk:** on a shared device, photo bytes fetched during user A's session stay
  resident in the heap across sign-out into user B's session. To *serve* them B
  must call `load()` for the same `storagePath`, which requires B to be able to
  read that appointment — so this is **not** a rules bypass. It matters as
  memory-forensics / diagnostic-dump exposure, and as drift from the otherwise
  careful teardown ordering in `AccountExitListeners`.
- **Fix:** clear `_cache`/`_sizes`/`_cachedBytes` from the account-exit
  teardown, which is already the single owner of "forget this session".

### S3 — Places proxy logs a 200-char upstream error body, which can contain the address being typed · severity: **low** · confidence: **medium**

- **Where:** `functions/places.js:64-69` (`logResponsePreview: true`, passed by
  `placesAutocomplete:163` and `placesGetDetails:216`).
- **Risk:** Places API (New) error bodies echo the offending request field
  (`"Invalid value at 'input' …"`), so a rejected autocomplete query — a
  client's street address an admin is mid-typing — can land in Cloud Logging
  with no retention control. `placesReverseGeocode` deliberately passes `false`
  for exactly this reason (`:279`), so the two paths are inconsistent about the
  same class of data. Requires GCP log access, and only fires on non-200s.
- **Fix:** log `response.status` and at most the parsed `error.status` code —
  never the raw body — or flip `logResponsePreview` to `false` on both, matching
  the geocode path.

### Security — verified clean (negative results worth keeping)

Recorded so these aren't re-audited next round:

- **Rules:** deny-by-default holds; no `allow read, write: if true`, no bare
  `if request.auth != null` without a role/ownership test. Every collection
  reachable from code has a matching rule (enumerated client-side and
  server-side). The only recursive wildcard grants read to **admins only**.
  The new `appointments/{id}/images` subcollection is covered, *resolves* the
  parent's condition rather than restating it, is `hasOnly`-locked, and fails
  closed on a missing parent. `pictureCount` is banned on create (flat) and
  update (diff), and `toMap()` doesn't emit it. Function-owned denylists are on
  **both** create and update for `/users` and `/clients`. Only one client-written
  TTL field exists and it is required and bounded at +31 d.
- **Caps:** every key emitted by `ClientRecord.toMap()` (20) and
  `AppointmentRecord.toMap()` (17) is capped, and every `TextLimits` constant is
  ≤ its rules cap. `IMPORT_FIELD_CAPS` — including the new `addressLine2: 500`
  flagged as an accepted risk last round — is ≤ the rules caps on every key, so
  no Admin-SDK import can write a doc the app can never update again.
- **Callables:** `enforceAppCheck: true` on all 14, no omissions. No `onRequest`
  function exists anywhere, so there is no unauthenticated endpoint and no CORS
  surface. Guard order correct in all 14; none consumes `data.*` before
  validating; none burns a rate-limit slot before rejecting a malformed payload.
  Guards fail **closed** on missing input (`completeEmployeeSetup:641` uses the
  `!req.auth.token || …` shape, not the permissive `token && …`).
- **No PII or secret** reaches a log or a client error, including the rollback
  branches (`employee_accounts.js:307`, `:498` log uid/docId, never addresses).
- **Secrets:** full-tree scan clean; only hits are test fixtures. `dev/.env`,
  `GoogleService-Info.plist` and `/android/` are gitignored **and confirmed not
  tracked**. The load-bearing `/android/` ignore entry is present and doing its
  job — 400 sampled commit trees contain no `android/local.properties`.
- **Client:** App Check intact in `main()`; no role ever read from
  SharedPreferences; all four `obscureText` fields pass
  `kCredentialImePersonalizedLearning`; all 9 callable responses cast loosely;
  every `Stream.listen()` in `lib/` (13 sites) passes `onError`.

---

## 🟠 Bug findings (review required)

### B1 — The nightly digest's cap keeps the OLDEST open jobs, not tomorrow's · severity: **medium** · confidence: **high** (logic) / **medium** (reachability today)

- **Where:** `functions/notification_utils.js:719-731`.
- **Problem:** the query floor is `tomorrowStart − MAX_APPOINTMENT_SPAN_MS`
  (15 days in the **past**), ordered `startTime` **ASC**, capped at
  `DIGEST_SWEEP_MAX` (1000). Ascending from a past floor means the cap keeps the
  oldest still-open jobs and **discards the newest — i.e. tomorrow's**. The
  comment justifies the cap by asserting "the jobs kept are the ones starting
  soonest, i.e. the ones tomorrow's digest is actually about", which is reasoning
  imported from `runTravelAwareReminderSweep`, whose window starts at `now`. The
  sibling sweep with the same shape (`runOverduePromptSweep`) correctly uses
  `orderBy("endTime", "desc")` for precisely this reason.
- **Failure scenario:** techs not marking jobs done leaves a growing tail of
  stale `pending` rows. Once >1000 open appointments have `startTime` inside
  `[tomorrow−14d, tomorrow+1d)`, the 18:00 digest reads 1000 documents that all
  started a week or more ago, `groupTomorrowsJobsByEmployee` finds no overlap
  with tomorrow for nearly all of them, and **every crew gets no digest at all**
  — the exact silent omission `DIGEST_SWEEP_MAX` exists to prevent. There is a
  `logger.warn` at the cap, so it is not fully silent, but the outcome is
  inverted from what the code claims.
- **Fix:** order so the cap keeps what the digest is about — `.orderBy("startTime",
  "desc")` and reverse in memory before grouping, or switch to the overlap form
  `fetchEmployeeWidgetWindow` already uses (`endTime >= tomorrowStart AND
  startTime < end`). Either way, correct the comment to match the ordering.

### Bugs — invariants verified as holding

The bug pass verified the emphatically-documented invariants against the code
and found them intact. Recorded so they aren't re-derived: `appointment_day_slice.dart`
↔ `day_slice_utils.js` agree on the overnight test, `lastWorkDayOfWindow`, the
14-day clamp and the wall-clock rebuild; `appointmentImageDocId` ↔
`appointment_image_ids.js` are character-for-character equivalent;
`ClientNamePolicy` ↔ `client_name_utils.js` agree on `stripPhone`,
`composeStored` and `isBusiness`, and **both** client sheets pass `type` (the
edit sheet also `businessName`) into `composeSave`; `kSelfServiceUserFields`
matches `isAvailabilityOnlyChange()`'s seven keys; `maxAppointmentSpanDays` =
`MAX_APPOINTMENT_SPAN_DAYS` = the rules' `14d + 2h`; Siri
`scheduleSnapshotVersion` 3 = `supportedVersion` 3; the multi-day Live Activity
skip exists and is last in the chain; `wantsTravelAlerts` is read **before**
`decideOrigin`/`computeTravelSeconds`; `assertFreshReauth` is keyed on `isAdmin`,
not `isSelf`; every range-stream consumer re-scopes through `runsOn`; and the
photo pipeline's `_resolvedFor` keying, 1×1 refusal stand-in,
`existingBytes.length + i` viewer offset and `ImageViewer.open` clamp are all as
specified.

---

## 🔵 Areas to improve (review required)

Ordered by payoff.

### I1 — The only script that DELETES is the only script with no test · impact: **high** · effort: small

- **Where:** `functions/scripts/backfill.js` (257 lines), orphan decision at
  `:200-225`.
- **Opportunity:** with `--prune-orphans` this `delete()`s rows from
  `usersByUid` — the collection every `firestore.rules` gate resolves a role
  through. It exports four helpers (`assertKnownFlags`, `bridgeBody`,
  `bridgeMatches`, `shouldHaveBridge`) *specifically* so jest can require them
  without prod credentials, and has the `require.main === module` guard for the
  same reason. **Nothing requires them.** Verified: `grep -rn 'require("../scripts/'
  functions/__tests__/*.js` returns 6 lines covering six other scripts;
  `backfill.js` is absent.
  The untested branching is the three-way orphan decision: `expectedUids.has(id)`
  → skip; `claimedUids.has(id)` → **retain and warn** (a uid claimed by a
  *skipped* users doc is not an orphan — deleting it locks a live employee out of
  everything); else → delete only when `--prune-orphans` and not `--dry-run`.
  Four interacting conditions guarding a destructive write, zero tests.
- **Suggested improvement:** lift the classification into a pure
  `classifyBridgeRow(uid, {expectedUids, claimedUids})` — the same split
  `maintenance_policy.js` took out of `maintenance.js`, for the same reason —
  and test it. `backfill-clients-archived.js` also has no test; lower risk (one
  boolean, never deletes) and it comes free with I2.

### I2 — The batch-commit write loop is hand-spelled in 4 backfill scripts · impact: **high** · effort: small

- **Where:** `backfill-client-name-with-phone.js:105,296,359-366` ·
  `backfill-client-phone-formatting.js:55,220,250-257` ·
  `backfill-clients-archived.js:50,68,78-85` ·
  `restore-client-name-halves.js:115,304,348-355`.
- **Opportunity:** the `let batch / pending / BATCH_SIZE / commit / reset /
  tail-commit / dryRun continue` body is byte-identical in three of the four
  (only the constant differs). This is the code performing **unattended,
  irreversible bulk writes against prod**, and it is exactly the class where a
  past `--dry-run` bug wrote everything and then threw. Four copies means the
  fix must be found four times, and a fifth script inherits whichever copy gets
  pasted. This clears the 3+-instance bar comfortably.
- **Suggested improvement:** `functions/scripts/_batch.js` beside the existing
  `_flags.js` (which sets the precedent: a shared safety rule, per-script config
  kept local). Export `commitInBatches(db, {dryRun, batchSize})` returning
  `{stage(ref, patch), flush()}`. Each script keeps its own `BATCH_SIZE` and
  reporting. Test it once — that gives four scripts a tested write loop where
  three have none.

### I3 — `EditClientSheet._save` is 100 lines and structurally divergent from its sibling · impact: **high** · effort: small

- **Where:** `lib/features/clients/widgets/sheets/edit_client_sheet.dart:167-266`
  vs `add_client_sheet.dart:130-158`.
- **Opportunity:** the add sheet already extracted record construction into a
  helper; the edit sheet inlines validation + mobile self-heal + `composeSave` +
  a 25-field `copyWith` + the outcome `switch`. The two sheets **must agree** on
  `composeSave`'s arguments — passing `type` (and, on the edit sheet,
  `businessName`) is what stops an ordinary save renaming a business to its
  phone number on live Wave invoices. Divergent structure on a pair that must
  agree is what makes them drift.
- **Suggested improvement:** extract `ClientRecord _buildUpdatedRecord()`,
  mirroring the add sheet's existing helper. `_save` drops to ~45 lines and the
  two `composeSave` call sites become directly diffable.

### I4 — The nightly digest pays a 200-doc query for recipients it cannot reach · impact: **medium** · effort: small · confidence: confirmed

- **Where:** `functions/notification_utils.js:753`.
- **Opportunity:** `runDailyDigest` calls `fetchEmployeeWidgetWindow` (a
  `.limit(200)` query) and builds a full widget payload **before**
  `sendToEmployee` applies `_canReachRecipient` (active + role + ≥1 live token).
  `handleAppointmentWrite:426` already established the opposite order and
  documents exactly why; the digest never got the same treatment.
  Cost: up to **200 wasted reads + one payload build/JSON encode per unreachable
  employee, per day** — a crew of 15 with 3 tokenless actives is up to 600
  wasted reads/day, forever.
- **Suggested improvement:** hoist the `_loadRecipient` + `_canReachRecipient`
  pair above the `fetchEmployeeWidgetWindow` call. No behaviour change —
  `sendToEmployee` would have returned 0.

### I5 — A 1.02 MB PNG ships in the IPA for a mark that renders at ≤156 px · impact: **medium** · effort: small

- **Where:** `assets/images/icon.png` (1254×1254, 1,044,191 bytes), referenced
  by `lib/shared/widgets/branding/brand_logo.dart:20`.
- **Opportunity:** `BrandMark` correctly bounds *decode*, so this is pure
  download/install weight — **~0.85 MB of a ~1.02 MB asset is unused**, the
  single largest bundled asset in the repo. At dpr 3 the splash needs 468 px.
- **Suggested improvement:** keep the 1254 px master out of `pubspec.yaml`'s
  `assets:` (the icon/splash generators read it from disk, not the bundle) and
  ship a 512×512 optimised PNG. At minimum run it through `oxipng`/`pngquant` —
  a flat logo this size should be well under 150 KB.

### I6 — `_deliverRecipientOnce` claims the idempotency ledger before checking reachability · impact: **medium** · effort: small

- **Where:** `functions/notification_utils.js:485-487` (claim) vs `:509`
  (release).
- **Opportunity:** same gap as I4, in the shared delivery core used by both the
  overdue and travel sweeps. Per unreachable (job, assignee) pair: **2 wasted
  writes + 2 reads per sweep run**. The overdue window (2 h) against a 5-minute
  cadence is 24 runs ⇒ ~48 wasted writes + 48 reads per pair per overdue job;
  the travel window (90 min) gives 18 runs ⇒ ~36 writes.
- **Suggested improvement:** move `_loadRecipient` + `_canReachRecipient` above
  the `ledgerRef.create`. Semantics are preserved exactly — "no ledger written"
  is indistinguishable from "written then released", so the late-token retry the
  release exists for still works.

### I7 — The legacy photo path bypasses the session byte cache entirely · impact: **medium** · effort: small

- **Where:** `lib/core/images/appointment_image_loader.dart:110-113`.
- **Opportunity:** `load()` returns `_loadLegacy(image)` before touching
  `_cache`, so a legacy (`url`-only) entry is re-fetched from Storage on **every
  widget State** — every sheet open and again on every View→Edit toggle. That is
  precisely the cost the byte cache was built to eliminate. The stated reason
  ("two legacy docs share the empty `storagePath`") only rules out keying on
  `storagePath`; `image.url` is already a unique handle and is already passed to
  `_fetch` as the log label. The `url` fallback is documented as **permanent**,
  so this does not age out.
- **Suggested improvement:** key the cache on `'url:${image.url}'` and route the
  legacy branch through the same `_cache`/`_settle` path — `_settle` already
  guards on future identity and refuses to cache empty results.

### I8 — `runOnSiteFlipPass` iterates card markers sequentially, unlike every other fan-out beside it · impact: **medium** · effort: small

- **Where:** `functions/travel_utils.js:811`.
- **Opportunity:** each iteration is an appointment `doc.get()` plus a token
  query and a direct APNs push. The candidate loop 200 lines above is explicitly
  `Promise.all`'d with the reasoning "each (job, assignee) pair is an independent
  chain"; markers are equally independent. `listCardsDueForOnSite` is capped at
  `PRUNE_MAX` = 400, so at ~300 ms per marker that is up to **120 s of the 420 s
  budget this function shares with the billable travel half**, every 5 minutes.
  At today's roster (~10 concurrent cards) it is ~3 s — a tail risk, but the cap
  is the number that matters if the fleet grows.
- **Suggested improvement:** `await Promise.all(markers.map(...))`, keeping the
  per-marker `try/catch`.

### I9 — A surviving unbounded query contradicts a documented invariant · impact: **low** (cost) / **medium** (doc accuracy) · effort: small

- **Where:** `lib/features/live_activity/data/live_activity_token_repository.dart:66-72`.
- **Opportunity:** `deleteTokensOfKind` runs a subcollection query with **no
  `.limit()`**. CLAUDE.md states `countFutureAssignments` was "the LAST unbounded
  query in the repository" — that claim is false. Every other query was verified
  bounded: appointments (7), clients (4), employees (6), presence (1). Bounded in
  practice by devices-per-user (1-3) and a 3-day TTL, so this is a tail guard,
  not a live cost — but the written invariant should be true.
- **Suggested improvement:** add `.limit(_deviceTokenScanLimit)` (~50) to match
  every sibling's posture, then the CLAUDE.md claim becomes accurate.

### I10 — Two bounded reads still truncate silently · impact: **low** · effort: small

- **Where:** `lib/features/clients/data/firebase_clients_repository.dart:161-169`
  (`fetchClientsCreatedSince`) and
  `lib/features/calendar/data/firebase_appointments_repository.dart:592-597`
  (`fetchClientHistory`, `limit: 50`).
- **Opportunity:** neither carries the `_logger.warn` that every other capped
  read here has (`_mapRangeSnapshot`, `_historyScanWindow`, `_clientScanWindow`,
  `getSeries`, `countFutureAssignments`, `findBusyEmployees`,
  `fetchAppointmentPictures`). At the cap the dashboard's 8-week new-client trend
  under-reports its oldest weeks, and a client with >50 visits shows only the
  newest 50 with no "see more" and no signal — failing the way the convention
  exists to catch: gradually, with no error anywhere.
- **Suggested improvement:** add the warn at both sites.

### I11 — `sendToActiveAdmins` is unbounded and re-reads every doc it just fetched · impact: **low** · effort: small

- **Where:** `functions/notification_utils.js:811-818`.
- **Opportunity:** the only unbounded collection query left in the push stack,
  and it calls `send(...)` with **no cache argument**, so `_loadRecipient` issues
  a fresh `users/{docId}.get()` for a document already in `snap.docs` —
  **+1 redundant read per active admin per notice**. Small today, but this is the
  shared fan-out CLAUDE.md says P6's time-off requests will build on.
- **Suggested improvement:** add `.limit()` with the warn-at-cap posture used by
  the three sweep ceilings, and pass a pre-seeded `Map` as the `cache` argument
  so only the `fcmTokens` read remains.

### I12 — `CalendarDayCell.build` is 113 lines in the hottest, most-edited widget · impact: **medium** · effort: small

- **Where:** `lib/features/calendar/widgets/views/calendar_month_grid.dart:180-292`.
- **Opportunity:** 42 instances per month page × the pager, and the most-edited
  widget in the app — the crew-dot rule, the today-ring rule and the selection
  rule have all changed recently and all three live inside this one method.
- **Suggested improvement:** two clean seams needing no new state — the number
  circle (`:205-229`) → `_DayNumber`, the dot `Row` (`:230-261`) →
  `_CrewDotRow`. Leaves ~50 lines of gating logic, which is the part worth
  reading. 20 `build()` methods exceed the ~60-line guideline; the same shape
  applies to `dashboard_hero.dart:23` (87) and `verify_email_panel.dart:32` (86).

### I13 — `auth_form_widgets.dart` holds 8 public classes, including a credential field · impact: **medium** · effort: small

- **Where:** `lib/features/auth/widgets/auth_form_widgets.dart` (531 lines,
  10 classes, 8 public).
- **Opportunity:** the only genuine "one class per file" violation in the tree —
  every other multi-class file is one public widget + private sub-widgets, which
  is idiomatic. `AuthPasswordField` is a credential surface (it carries
  `kCredentialImePersonalizedLearning`) and is buried at line 404 of a file named
  after nothing in particular.
- **Suggested improvement:** split into `auth_scaffold.dart`, `auth_fields.dart`,
  `auth_text.dart`; keep `auth_form_widgets.dart` as a barrel re-export so no
  call site changes.

### I14 — Extract the images-subcollection block ahead of the CONTRACT step · impact: **medium** · effort: small

- **Where:** `lib/features/calendar/data/firebase_appointments_repository.dart:305-445`
  (~140 lines).
- **Opportunity:** the repository as a whole is **not** a god file (887 total,
  561 code — the rest is load-bearing doc comment) and should not be split. But
  this one block is the phase-1 migration surface that the documented CONTRACT
  step will change wholesale.
- **Suggested improvement:** move it to an `AppointmentImagesStore` collaborator
  so the migration is a file, not a diff scattered through a 900-line class.

### I15 — A stale duplication comment justifies a divergence that no longer exists · impact: **medium** · effort: small

- **Where:** `functions/scripts/backfill.js:67-69` vs `functions/bridge.js:15-27`.
- **Opportunity:** the comment reads "This deliberately duplicates the shared
  `../bridge.js` helper rather than importing it, since folding the role check in
  up front lets us skip malformed docs outright." `bridge.js:24` now contains
  that same role check, so the two are behaviourally identical and the stated
  reason no longer holds. `VALID_ROLES`/`VALID_BRIDGE_STATUS` are also
  re-declared. This is the same "a long comment is a spec" failure shape as B1,
  and one half of the pair is the untested script in I1.
- **Suggested improvement:** extract the pair into a `bridge_policy.js` both can
  require (the `notification_policy.js` pattern), or at minimum correct the
  comment and add the tests so the two stay pinned.

### I16 — `_pruneExpired` deletes up to 400 rows one round-trip at a time · impact: **low** · effort: small

- **Where:** `functions/live_activity_registry.js:308-311`.
- **Opportunity:** the comment says "the expired set is tiny", but the loop is
  bounded by `PRUNE_MAX` = 400, not by that assumption, and it runs **twice**
  (tokens + card markers) inside the daily digest invocation — up to ~8-16 s per
  sweep × 2 against the digest's 540 s budget, shared with `runWaveDaily`.
- **Suggested improvement:** chunked `Promise.all` or `db.bulkWriter()`, keeping
  per-row failure isolation.

### I17 — `StaffMarkerIconRenderer._cache` has no eviction bound · impact: **low** · effort: small

- **Where:** `lib/features/presence/widgets/staff_marker_icon.dart:18`.
- **Opportunity:** keyed on `(initials, color, selected, ringColor, haloColor,
  dpr)`; the renderer is a field of `_LiveMapScreenState` and the Live Map is a
  hub `IndexedStack` tab, so it survives the session. ~4 entries per staff member
  × a ~10-15 KB PNG ⇒ **~3 MB at 50 staff, ~12 MB at the 500-doc presence cap**.
  Not a leak (bounded by roster × 4), but unbounded by construction — and the
  photo cache one directory over is explicitly byte-budgeted for the same reason.
- **Suggested improvement:** an LRU cap (~64 entries).

### I18 — Sort key recomputed inside the comparator · impact: **low** · effort: small

- **Where:** `lib/features/employees/application/employee_schedule_providers.dart:130-134`.
- **Opportunity:** `sliceFor(a, range.start)` is called on **both** operands of
  every comparison rather than once per record — the exact pattern
  `fetchClientsByType` documents avoiding. `2·n·log n` slice constructions
  instead of `n`; for a 20-job day that is ~170 builds instead of 20, per
  range-stream emission.
- **Suggested improvement:** decorate-sort-undecorate.

### I19 — `runsOn` builds a whole slice to answer a null test · impact: **low** · effort: small

- **Where:** `lib/features/calendar/domain/appointment_day_slice.dart:130-131`.
- **Opportunity:** `sliceFor` runs `_windowOn` (2 `DateTime` allocations) after
  the index check has already decided the answer. `runsOn` is the **mandated**
  re-scoping call on every superset consumer — the drawer badge (over the full
  range list, on every drawer build), `employeeJobsTodayProvider`,
  `employeeTodayJobsProvider`, `DashboardAggregator:161`. At the 1000-record
  stream limit that is ~2000 needless allocations per pass.
- **Suggested improvement:** extract the index test and have `runsOn` return on
  it. **Do not touch `_clampedDayCount`** — that is a correctness guard.

### I20 — `ListView(children:)` where a `.builder` belongs · impact: **low** · effort: small

- **Where:** `lib/features/calendar/widgets/sections/photo_picker_section.dart:194`.
- **Opportunity:** `_EditablePhotoStrip` materialises a widget subtree per photo
  eagerly, capped at 100 photos ⇒ ~600 widget allocations per build of the strip,
  which rebuilds on any edit-sheet form change. Decode is *not* affected —
  `cacheWidth`/`cacheHeight` are correctly set at `:283-284`.
- **Suggested improvement:** `ListView.builder` with an index-mapped builder
  across the three segments.

### I21 — History recomputes two O(N) passes in `build()` · impact: **low** · effort: small

- **Where:** `lib/features/clients/widgets/lists/history_sliver_list.dart:78`
  and `appointment_history_view.dart:540`.
- **Opportunity:** `monthSectionsOf(rows)` and `tallyOf(rows)` re-run on each
  rebuild (page load, filter `setState`, `employeeColorMapProvider` /
  `currentDayProvider` emission), and N grows with scroll depth (25/page,
  unbounded pages). Not per scroll frame.
- **Suggested improvement:** memoize both on the `rows` list identity, exactly as
  `_filterOptionsPages`/`_searchIndexPages` already are two files over.

### I22 — A widget-layer function lives in `domain/policies/` · impact: **low-medium** · effort: small

- **Where:** `lib/features/employees/domain/policies/work_schedule_policy.dart:140-150`.
- **Opportunity:** `showMaxJobsPicker(BuildContext)` pushes a route, which forces
  an unqualified `package:flutter/material.dart` import and `l10n` into the
  domain layer. It is the **only** domain file in the repo that shows UI (the
  other 6 material imports there are all `show TimeOfDay`/`show Color`-style).
  It is the precedent that lands the next `show*Picker` in `domain/` too.
- **Suggested improvement:** move it (and optionally `joinWeekdayNames`) beside
  `availability_panel.dart`. `kMaxJobsOptions` and `maxJobsLabel` **stay** — they
  are the pure part and the reason the single-owner rule exists.

### I23 — `loadAll`'s concurrency bound is never actually asserted · impact: **low** · effort: small

- **Where:** `test/core/images/appointment_image_loader_test.dart:147`.
- **Opportunity:** the existing test exercises `loadAll` for *ordering* past the
  bound, but nothing asserts that at most 4 fetches are ever in flight — so
  `_maxConcurrentLoads` could be removed or raised with no test failing.
- **Suggested improvement:** count concurrent un-completed futures in the fake.

### I24 — `client_propagation.js` page loop has no total bound (visibility only)

- **Where:** `functions/client_propagation.js:163-189`.
- **Note, not a defect:** the loop runs to exhaustion over `clientId == X AND
  startTime >= now − 14d` with no upper time bound; a repeat series pre-books up
  to 120 occurrences out to a 5-year horizon. One name/phone/address edit on a
  client with several live series reads hundreds to low-thousands of documents.
  **It should not be capped** — truncating would leave stale denormalized
  `clientName` on future visits, which is the bug this trigger exists to
  prevent. Two safe wins: commit each page's batch concurrently with fetching
  the next rather than serially, and log the page count so a pathological client
  is visible.

---

## 🟡 Code-quality suggestions (optional)

- **Root `package.json` + `package-lock.json` are dead weight** (repo root).
  A 3-line manifest declaring one dependency (`firebase-functions`), which has
  materialised a **207-package** root `node_modules/`. Verified: no `.js` file
  at the repo root; `firebase.json:10` points at `"source": "functions"`;
  `.github/workflows/ci.yml` sets `working-directory: functions` and caches
  `functions/package-lock.json`; zero references in `docs/`, `README.md` or
  `.claude/`. Both files are git-tracked, added incidentally in `5a42743e`.
  Suggested: delete both + the root `node_modules/`, then confirm with
  `cd functions && npm ci && npm run lint`. Report-only because package-manifest
  edits need their own verification pass.
- **`lib/features/navigation/domain/drawer_catalog.dart:86-93`** — eight raw
  `const Color(0xFF…)` drawer hues. `HubTab.calendar`'s `0xFF005CC8` is
  byte-identical to `AppColors.primary`; the other seven are a bespoke nav
  palette with no token counterpart. **All-or-nothing:** swapping only the
  calendar one leaves a token beside seven literals, which is worse. Either move
  all eight into `design_tokens.dart` as a named `navPalette`, or leave as-is.
- **`lib/features/calendar/application/event_details_controller.dart:138`** —
  the tree's **only** code marker (`TODO(gvogas): revisit at the
  photo-subcollection CONTRACT step.`) is missing the `(#issue)` the convention
  asks for. Cosmetic; there is no issue tracker in play.
- **Test scaffolding duplication (below the action bar, noted for the count):**
  `_FakeHttpsCallableOptions` is an identical one-liner in 5 test files, and
  `adminFirestore()` is an identical 2-line lazy require in 3 `functions/` files
  (`client_propagation.js:53`, `wave/customers.js:195`, `wave/worker.js:113`).
  Per the anti-defaults, three two-line bodies is **not** yet a helper — recorded
  so the count is on file if a fourth appears. `test/support/` already exists if
  you want the test one.

---

## Notes / uncertainties

- **l10n is completely clean** — parsed both ARBs (722 keys each) and built a
  whole-word token index over 880 source files. Zero orphaned keys, zero EN-only
  or FR-only keys, zero missing `@key` blocks, zero placeholder drift. The
  deleted invite-code flow, `kShowTestingDeleteClient` and the Android removal
  all took their ARB entries with them. **No separate l10n pass is needed.**
- **No substantial duplication in `lib/`** — a normalized N-line-window scan
  across all 374 non-generated files at window sizes 5-8, requiring ≥3 distinct
  files, returned **zero hits at windows 7 and 8**; every window-5/6 hit was
  Flutter boilerplate. The single-owner discipline is holding. All duplication
  findings this round are in `functions/scripts/` and `test/`.
- **All four unused-dependency candidates are false positives**, individually
  verified: `google_maps_flutter_ios_sdk9` is a platform implementation override
  (confirmed present in `GeneratedPluginRegistrant.m`); `build_runner` and
  `freezed` back the `.freezed.dart` files in the tree; `flutter_launcher_icons`
  is a CLI tool configured in `pubspec.yaml:164` itself.
- **Robustness is clean** — zero empty catches in `lib/` (the one bare
  `catch (_)` is the documented FCM-background-isolate carve-out); all 70 `late`
  fields assigned before any read; all 7 force-unwraps guarded or documented;
  zero `ref.read` inside a `catch` (all 13 candidates were the correct
  hoisted-before-await form).
- **Documentation drift is this round's theme.** Four instances found (three
  auto-fixed, one — S1 — left for your call because it overstates a *security*
  guarantee), plus two more embedded in findings (B1's comment justifying the
  wrong ordering, I15's comment justifying a divergence that no longer exists).
  Worth noting that in each case the code was reasonable and the *prose* was
  what had gone stale — the inverse of the usual audit finding.
- **Not re-reported:** the documented, accepted residual risks (the `Welcome123!`
  window behind the `email_verified` guard, client-side-only password-then-activate
  ordering, the un-freshness-gated admin email branch, the narrowed-not-closed
  `resetProvisionedPassword` window, presence/FCM not purged on OS permission
  revocation) were each re-verified as unchanged and none has gotten worse.
- **Not verified here:** anything requiring a device or the emulator — push
  delivery, Live Activity rendering, App Attest, and the actual behaviour of
  Storage rules under a live rejection.

---

*Next step: say **"do everything but the pre-ship"** and I'll implement all
non-pre-ship findings above. The Pre-ship checklist is empty this round, so that
is effectively everything — though S1 and I24 involve judgment calls I'd want to
confirm before acting on.*

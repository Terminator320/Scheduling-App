# Codebase Audit — 2026-08-22

Scope: whole repo (`lib/`, `functions/`, `firestore.rules`, `storage.rules`,
`firestore.indexes.json`, `test/`, `lib/l10n/*.arb`, `.claude/rules/`, `docs/`).
Baseline: `7ace6528` on `redesgin`, clean tree.

> **This audit ran the day after HEAD retired the `pictures` array** (the photo
> subcollection CONTRACT step). That commit is undeployed, and several findings
> below are specifically about it — one is a user-visible regression, four are
> comments left pointing at machinery the commit deleted. Read the CONTRACT-step
> items before running the migration's remaining steps.

## Summary

- **Scanned:** 389 Dart files / 56.5k LOC in `lib/`, 302 test files, 114 JS
  files / 35.7k LOC in `functions/`, 2 rules files, 711 × 2 ARB keys.
- **Auto-fixed (safe, in the diff):** 11 — 3 zero-reference deletions, 1
  orphaned docstring, 7 factually-wrong doc pointers.
- **Reported for your decision:** 34
  (⚠️ 4 act-before-release · 🔴 5 security · 🟠 6 bugs · 🔵 19 improvements)
- **Verification:** `flutter analyze` **No issues found!** · `flutter test`
  **2608/2608** · `functions` jest **1343/1343 across 56 suites** ·
  `npm run lint` clean. All match the pre-audit baseline exactly.

**The mechanical level of this codebase is exceptionally clean.** `flutter
analyze` was already at zero, `dart fix --dry-run` had nothing to apply, ESLint
was clean, there are zero orphaned Dart files, zero orphaned ARB keys, zero
EN/FR drift, zero removable dependencies, zero commented-out code, zero
`TODO`/`FIXME`/`HACK`/`XXX` markers and zero debug leftovers. Every documented
performance invariant in `CLAUDE.md` was re-verified and still holds. The yield
is therefore concentrated in three places: **the CONTRACT step's loose ends**,
**documentation that has drifted from the code it governs**, and **test-coverage
gaps on release-critical paths**.

### The top three

1. **🟠 B1 — a just-added photo is invisible until a Cloud Function catches up.**
   A HEAD regression on the most-opened surface in the app.
2. **🔵 I1 — the irreversible migration script prints no target project.** Four
   bulk-write scripts run under ambient credentials with no banner, including
   `clear-appointment-picture-arrays.js` — which is the *next* operational step.
3. **🔴 S1 — legacy `url` photo docs are still permanent, rules-free links**, and
   the control that used to revoke them was deleted on the premise that none
   survive. The rules, the backfill and the loader all say otherwise.

## Auto-applied cleanups (review the diff)

| File:line | Change | Why |
|---|---|---|
| `lib/core/providers/firebase_providers.dart:25-27` | Deleted `extension AuthGatedRef on Ref` | Zero references repo-wide. It is a `watch(...).value` tri-state read — exactly what `streamForUid`, declared 6 lines below, exists to replace. A loaded footgun with no users. |
| `functions/appointment_images.js:371` | Removed `deleteAppointmentImageBytes` from `module.exports` | No external `require`, no test reference. Function and both internal uses (`:185`, `:347`) left intact. |
| `functions/.eslintrc.js:19-25` | Removed the `**/*.spec.*` mocha `overrides` entry | Zero `*.spec.*` files exist in the repo. |
| `lib/features/calendar/data/appointment_image_upload_service.dart:116-120` | Deleted orphaned docstring | Documented `_resolveCarriedUrl`, deleted at HEAD. It had glued itself above `_attempt`'s own doc and described a `null` return contract `_attempt` does not have. |
| `.claude/rules/firestore-indexes.md:53` | Added `appointmentRecountClaims` to the TTL list | The indexes file declares **7** `ttl: true` policies; the list named 6. This is the list guarding the `--force` footgun that wiped all 5 live TTL policies on 2026-07-21. |
| `.claude/rules/error-handling.md:124` | Removed `IMG-URL` from the log-tag registry | `downloadUrlFor` and its warn were deleted at HEAD. The registry is declared EXHAUSTIVE, and this was its only drift. |
| `.claude/rules/frontend.md:214` | `account_exit_listeners.dart` → `account_exit_controller.dart` | The SnackBar moved in the 2026-08-19 detect/teardown split. Count (3) was already right. |
| `lib/core/navigation/CLAUDE.md:46` | `lib/core/navigation/app_routes.dart` → `lib/routes/app_routes.dart` | Cited path does not exist. |
| `.claude/rules/appointments.md:80` | Dropped deleted `AppointmentTile` from the `showActions` list | `lib/features/calendar/CLAUDE.md:184` already says it is deleted; the two rule files disagreed. |
| `lib/features/calendar/CLAUDE.md:107` | `_CollapseHandle` → `CollapseHandle` (+ its file) | Made public into `widgets/views/collapse_handle.dart`. |
| `.claude/rules/clients.md:56` | `functions/wave/customers.js` → `customers_import.js` | The `archived: false` stamp moved 2026-08-19. |

> Full detail is in `git diff`. The closed 2026-08-19 report was moved to
> `docs/archive/CODEBASE_AUDIT_2026-08-19.md`.
> Nothing below this line was auto-changed.

## ⚠️ Act before release

There are **zero `TODO(pre-ship)` markers** in the tree — verified. These are
operational items carried forward from `docs/DEPLOYMENT.md` that are still open,
surfaced here because the CONTRACT step makes two of them newly urgent.

- [ ] **The photo migration's deploy ordering is unstarted, and step 2 gates the
  app build.** `docs/DEPLOYMENT.md:388-414`. HEAD stopped writing `pictures`,
  but the rules relaxation that accepts `pictureCount == 0` on create **must be
  live before the app build ships**, or every appointment create fails
  `permission-denied`. Step 1 (re-run the copy backfill) must also precede it —
  there is no array fallback left in the app, so anything the backfill misses
  shows **no photos at all**. Step 4 is the irreversible one; see 🔵 I1 before
  running it.
- [ ] **Download tokens for anyone deactivated 2026-08-16 → 2026-08-19 were
  never rotated.** `docs/DEPLOYMENT.md:585-600`. `rotateAssignedImageTokens`
  resolved its bucket into a local while the callee read `deps.bucket`, so the
  control logged "nothing rotated" while rotating nothing. The fix shipped; it
  does not act retroactively. Remediation is to flip each affected person to
  `active` and back. **Note this interacts with 🔴 S1** — the rotation has since
  been deleted entirely, so this is now the only way to close that window.
- [ ] **3 orphaned Cloud Scheduler jobs.** `gcloud` is not installed on this
  box; scheduled functions must land on exactly 3, and only 3 are free.
- [ ] **A live `MAPS_API_KEY` remains in git history**, committed by the merge
  that resurrected `android/`
  (`docs/archive/CODEBASE_AUDIT_2026-08-14-pre-deploy.md:530`). `/android/` is
  now correctly gitignored and untracked — verified — but **I found no record
  anywhere in `docs/` that the key was ever rotated.** Rotating it is the fix;
  history rewriting is not required once the key is dead.

## 🔴 Security findings (review required)

### S1 — Legacy `url` photo docs are permanent rules-free links, and the control that revoked them was deleted on a premise the code contradicts · severity: medium · confidence: high

- **Where:** `firestore.rules:687` and `:696-701`;
  `functions/scripts/backfill-appointment-images.js:87`;
  `lib/core/images/appointment_image_loader.dart:166-172`;
  `functions/bridge.js:260-267`; `functions/CLAUDE.md:216`.
- **Risk:** a `?alt=media&token=…` download URL is served with **no auth and no
  `storage.rules` evaluation**, and its token is stable per object and never
  expires. Deactivation (`syncUsersByUid`) disables the Auth account, revokes
  refresh tokens and flips the `status == 'active'` gate — none of which touches
  that string. Unlike a cached byte, the URL is *transferable*: an assigned
  employee can read it out of the image document and paste it anywhere, forever.
  That is precisely what the deleted `rotateAssignedImageTokens` existed to close.
- **Why the deletion premise does not hold.** `bridge.js:264` reasons the
  CONTRACT step "stopped minting it, stopped storing it and cleared the arrays,
  so there is no such link left to invalidate." Two halves of that are not true
  today: (a) the **subcollection** still carries `url` — the backfill
  deliberately preserves it when there is no `storagePath` ("dropping that one
  destroys the only thing that can render the photo"), the rules explicitly allow
  it up to 1000 chars, and the loader fallback is documented as *permanent*; and
  (b) **the arrays are not cleared** — that is step 4 of the runbook and it has
  not run.
- **Fix:** count `appointments/*/images` docs where `url` is set and
  `storagePath` is empty. If **zero**, drop `url` from the rules allowlist and
  delete the loader fallback, which makes the claim true. If **any exist**,
  either re-upload those bytes to a real `storagePath` and strip `url`, or
  reinstate a rotation scoped to just those objects. Until one lands, correct the
  note in `bridge.js`, `functions/CLAUDE.md:216` and `.claude/rules/images.md:45`
  so the risk assessment is not leaning on a claim the rules contradict.
- **Could not verify:** whether any such doc exists in prod. Firebase MCP
  Firestore reads fail `read_time cannot be in the future` on this box (clock
  skew), so this needs a one-shot count run by hand.

### S2 — Process-lifetime repository caches hold client PII across sign-out · severity: low · confidence: high

- **Where:** `lib/features/clients/data/firebase_clients_repository.dart:41-44`
  (up to 5000 full `ClientRecord`s — name, phone, email, address, contacts);
  `lib/features/calendar/data/firebase_appointments_repository.dart:73-89`
  (up to 5000 raw appointment maps with `clientName`/`clientPhone`/`address`,
  plus 50 result lists); `lib/core/app/device_deregistration.dart:107`.
- **Risk:** both repositories are root-scope `Provider`s, so they live for the
  whole process. The 2-minute TTL only gates whether a window is *served*, never
  evicts. Neither is cleared on sign-out or in the account-exit teardown, which
  clears the image loader and nothing else. Heap residency on a shared handset —
  the next signed-in user can only *render* it if they are also an admin, so this
  is not an access-control hole.
- **Fix:** add `clearCaches()` to both repositories and two `_step(...)` calls in
  `deregisterThisDevice`, beside the existing `imageCache de-registration`. Same
  argument already accepted for the image caches.

### S3 — `placesAutocomplete`'s rate limit is per-instance and `maxInstances: 10` multiplies it · severity: low · confidence: high

- **Where:** `functions/places.js:24-26, 126-148`; `functions/index.js:4`.
- **Risk:** every other admin callable uses the durable Firestore limiter; this
  one uses an in-memory `Map` at 20/min per uid. With up to 10 concurrent
  instances the real per-uid ceiling on a **billed** Google Places endpoint is
  ~200/min, and a cold start resets the bucket. Billing-DoS, not data, and it
  needs a compromised admin session (it is behind `assertAdmin` + App Check).
- **Fix:** the in-memory design is a deliberate latency trade — but state the real
  ceiling in the comment, and confirm the GCP billing alert the comment
  references actually exists. Or move to `enforceDurableRateLimit`, which
  `placesGetDetails` already tolerates.

### S4 — `functions/` transitive advisories (informational) · severity: low · confidence: high

- **Where:** `functions/package.json` — `firebase-admin ^13.6.0`.
- **Risk:** `npm audit --omit=dev` reports 9 moderate advisories, all rooted at
  `uuid <11.1.1` (GHSA-w5hq-g745-h8pq) reached via `gaxios`/`google-gax`/
  `teeny-request`. The vulnerable path needs `uuid` v3/v5/v6 called with a
  caller-supplied buffer; nothing here does that and no attacker input reaches it.
- **Fix:** none now. **Do not run `npm audit fix --force`** — it downgrades
  `firebase-admin` to 10.3.0, and the existing project note already forbids
  bumping to admin@14 on functions 7.x. Re-check when the SDK bumps `uuid`.

### S5 — Note: FCM / Live Activity token doc ids are the raw tokens · severity: low · confidence: low (not exploitable)

- **Where:** `firestore.rules:355-368`, `:372-402`.
- An active user may `create` a row at any doc id under their own
  `fcmTokens`/`liveActivityTokens`, i.e. plant another device's token. Reading
  another device's token requires `myDocId() == userId`, so the rules already
  deny the only in-app way to obtain one. **Not a finding** — recorded because
  the doc-id-*is*-the-secret shape matters if a future surface ever exposes a
  token.

### Security checklist verified clean

Guard ordering on all 12 callables (auth → `assertAdmin`/identity → payload →
`assertFreshReauth` → rate limit → work); fail-closed guards (`isReauthStale`
treats any non-number as stale; `resolveEmailChangeCaller` refuses a null bridge,
non-`active` status, unknown role); `enforceAppCheck: true` on all 12, no
`onRequest`/CORS surface; every `assertPayloadShape` allowlist explicit, with
`createEmployeeAccount`'s `isAdmin` correctly `#compat-1.47.0`
accepted-and-ignored and the role hard-coded `"employee"` on both branches;
`generateStartingPassword` uses `crypto.randomInt` (no modulo bias), guarantees
one char per class, Fisher-Yates shuffles, and is persisted nowhere; zero PII,
secrets or tokens in any `functions/` log; no raw Firebase codes or stack traces
returned to clients; rules deny-by-default with no `match /{document=**}`, all
server-owned collections `if false`, `allow delete` withdrawn on `/users` and
`/clients`, exactly three `users` read clauses; `liveActivityTokens.expiresAt`
required and capped at +31d against a 30d client write; every
non-admin-reachable appointment query carries the `employeeIds` filter; role
never cached (`AuthCache` stores uid/docId/name/colour only);
`ClientRecord.toMap` emits no `waveCustomerId`/`wave`; all four credential fields
pass `kCredentialImePersonalizedLearning`; magic bytes validated on both sides
with the read-failure branch failing closed; no secrets tracked, `/android/`
ignored and untracked; no injection surface (Wave GraphQL args all travel as
variables).

## 🟠 Bug findings (review required)

### B1 — A newly-added photo is invisible until a debounced Cloud Function catches up · severity: medium-high · confidence: high

- **Where:** `lib/features/calendar/application/event_details_controller.dart:129`
  (`if (!appointment.hasPictures) return;`);
  `lib/features/calendar/domain/models/appointment_record.dart:96`;
  `functions/appointment_images.js:55` (`RECOUNT_SETTLE_MS = 2000`), `:222`.
- **Problem:** HEAD made the detail sheet seed `existingImages` empty and skip the
  subcollection read entirely when `pictureCount == 0`. That counter has exactly
  one writer — `recountPictures`' `parent.update()` — reached only via
  `debouncedRecountPictures`, which **sleeps 2000 ms before it even runs the
  aggregate**. The client deliberately does not write it
  (`appointment_images_store.dart:84-88`) and the rules reject a client update
  that touches it.

  **Concrete failure:** admin adds a photo → `appendAppointmentPictures` commits
  → sheet closed → sheet reopened within cold-start + 2 s settle + parent-write
  latency → `hasPictures` is still false, `_loadStoredPictures` returns at line
  129, and the sheet renders "No photos" while the card shows no indicator.
  Before HEAD the same batch `arrayUnion`-ed onto the parent, so the record
  carried it the moment the write acked.

  **The file convicts itself:** its docstring (`:117-122`) lists exactly three
  conditions that make the gate safe, then warns *"Should any of those stop being
  true, this reads a job's photos as none — silently, which is the failure mode
  the whole migration was shaped to avoid."* Propagation delay is a **fourth**
  window none of the three cover. The same gate also turns a permanently-failing
  `parent.update()` (retry budget exhausted) into photos that are invisible
  *forever*, with only a server-side log.
- **Fix:** drop the `hasPictures` short-circuit when the sheet is in edit mode —
  it is one bounded `get`, and the sheet is the only surface that pays it. Or
  keep the gate for the card indicator only and let the sheet read
  unconditionally. If the gate stays, at minimum emit a `breadcrumb` when
  `pictureCount == 0` on a job the user just uploaded to.

### B2 — `ref.read` inside a `catch` after an `await`, in two places, one contradicting its own file's comment · severity: low-medium · confidence: high

- **Where:** `lib/main.dart:287`;
  `lib/core/app/appointment_link_opener.dart:142-144` and `:150-151`.
- **Problem:** under Riverpod 3, `ref.read` on an unmounted consumer **throws a
  `StateError`** — an unconditional throw, not a debug assert. This is the exact
  pattern `.claude/rules/error-handling.md` calls "mechanically greppable; treat
  a new one as a bug", and the shape that already put a **FATAL** in the zone
  handler from `address_autocomplete_field.dart` once.
  - `main.dart:197` hoists a logger with the comment *"Read here, never inside
    the handler: the timer can fire after dispose."* Then `_saveSettings` — the
    very action that timer runs (`:256-257`) — does `ref.read(loggerProvider)`
    inside its `catch` at `:287`. The file states the spec and then breaks it.
    Practically low-risk because this is the root `PaulApp` state, which never
    unmounts; the greppability argument only works if the count stays 0.
  - `appointment_link_opener.dart`: `_startWidgetTaps:103` and
    `handleWidgetTap:125` both hoist correctly, but `_startPushTaps` reads `ref`
    inside `.catchError` and inside `onError` 40 lines below. The
    `initialMessage().then(handlePushTap)` chain is not cancellable by dispose,
    so if the tap handler throws post-teardown, `.catchError` reads `ref` again,
    throws again, and escapes as an unhandled record attributed to a *logging*
    call.
- **Fix:** hoist `final logger = ref.read(loggerProvider);` above the first
  `await` at both sites, mirroring the correct siblings in the same files.

### B3 — The clear script does not stamp `pictureCount` on documents with no array, contradicting the third leg of the completeness argument · severity: low-medium · confidence: high

- **Where:** `functions/scripts/clear-appointment-picture-arrays.js:159`
  (`if (pictures.length === 0) continue;`).
- **Problem:** `CLAUDE.md`, `.claude/rules/images.md` and the
  `event_details_controller` docstring all justify the `pictureCount` gate partly
  with "the cleanup script stamped it on every document that predates the
  change." It does not — it `continue`s past any appointment whose `pictures`
  array is absent or empty, so those are never touched. Benign in the common case
  (absent → parsed as 0 → correct). The uncovered shape: an appointment whose
  array was already emptied while its subcollection still holds photos and its
  `pictureCount` write failed. That document is skipped, and **B1's gate then
  hides its photos permanently.**
- **Fix:** don't `continue` on an empty array — read `storedImageIds(doc)` and
  re-stamp `pictureCount` when it disagrees, clearing the array only when
  present. Or correct the three prose claims to say "every document that still
  carried an array."

### B4 — `pageToCap` warns "truncated" on a collection that is exactly `cap` long · severity: low · confidence: high

- **Where:** `lib/core/data/paged_scan.dart:36`.
- **Problem:** `if (docs.length >= cap) { onCapReached(); break; }` runs *before*
  the short-page test at `:40`, so a client with exactly 1000 visits
  (`_clientHistoryScanLimit`, pageSize 500) files a Crashlytics warn claiming
  "older visits are not listed" when there are none. The function can also return
  more than `cap` when `cap` is not a multiple of `pageSize` — no current call
  site hits that, but the contract reads as a ceiling. Log noise only; no
  user-visible effect.
- **Fix:** test `snapshot.docs.length < pageSize` first (nothing beyond ⇒ no
  warn), and return `docs.length > cap ? docs.sublist(0, cap) : docs`.

### B5 — Two comments still assert a security posture that HEAD inverted · severity: low (documentation, but of a security invariant) · confidence: high

- **Where:** `lib/core/images/appointment_image_loader.dart:32-41`;
  `lib/features/calendar/data/pending_upload_store.dart:22-26` and `:73-76`.
- **Problem:** the loader's class docstring — its statement of what guarantee the
  class does and does not give — says `uploadImage` "**still mints one such URL
  per upload and persists it**", that "the whole `pictures[]` array reaches every
  assigned employee's device", and that the residual is "covered … by
  `functions/appointment_image_tokens.js`". At HEAD the mint is gone, the array is
  gone, and that module is **deleted**. The paragraph even says the write "goes at
  the photo-subcollection CONTRACT step" — HEAD *is* that step, so it anticipated
  its own obsolescence and was not updated. It now sends a reader looking for a
  compensating control that does not exist. `pending_upload_store.dart` likewise
  still describes the `arrayUnion` dedupe and a re-mint via
  `ImageStorageService.downloadUrlFor`; dedupe is now the derived
  `appointmentImageDocId` and `downloadUrlFor` is deleted.
- **Fix:** rewrite the loader header to say the mint is gone everywhere and the
  residual is the cache-hit window already described at `:53-56` — **but settle
  🔴 S1 first**, because whether the legacy `url` residual is closed determines
  what that paragraph should say. Point both `pending_upload_store` comments at
  `appointmentImageDocId`.
- **Note:** the three deleted symbols (`appointment_image_tokens.js`,
  `downloadUrlFor`, `rotateAssignedImageTokens`) have **zero live code
  references** — every surviving mention is a comment.
  `functions/__tests__/notification_utils.test.js:46` is the third such site.

### B6 — A lazy `late final` touching `ref`, first accessed from a timer callback · severity: low (latent) · confidence: high

- **Where:** `lib/features/maps/widgets/address_autocomplete_field.dart:45`.
- **Problem:** `late final PlacesRepository _service = ref.read(...)` is exactly
  the shape `.claude/rules/error-handling.md` and `debouncer.dart:24-27` warn
  about, and `_logger` beside it was already made eager for this reason. It
  degrades safely today — both call sites touch it before their first `await`, and
  `Future.sync(action).catchError(onError)` would catch the `StateError` with an
  `onError` that uses `_logger`, not `ref`. It becomes a crash the moment anyone
  moves the access below an `await`.
- **Fix:** assign it in `initState` beside `_logger`.

### Verified sound (no finding)

The `invited` carve-out at both gates including the "unknown status still signs
out" half; `isAccountDeletionSignal`'s populated→empty requirement and its
`AccountExitListeners` wiring; the awaited `_resolveActiveEmployees` →
`mergeRetainedAssignees` path and `assigneeNameAt`'s bounds check; the dashboard
live/history split merged by `mergeById`; both tri-state app-lock gates;
offline-guard-before-in-flight-flag ordering in all three submit controllers;
`_invalidateSearchCache()` on all eight appointment write paths; 30-item chunking
in `findBusyEmployees`; `appointmentImageDocId` vs its JS hand-mirror
(byte-equivalent); every `Stream.listen` in `lib/` passes `onError` (10 sites);
`diffAppointmentForNotifications` emits nothing for the new `updatedAt`-only and
`pictureCount`-only parent writes; no missing `mounted` guards; no floating
futures; no `late` field readable before init; no non-exhaustive switch on a
sealed family; no unsafe force-unwrap; all 78 `functions/` `.data()` sites
guarded.

## 🔵 Areas to improve (review required)

### I1 — Four bulk-write scripts print no target project, including the irreversible one · impact: high · confidence: high

- **Where:** `functions/scripts/clear-appointment-picture-arrays.js` (writes
  `update({pictures: FieldValue.delete()})` at `:181`), `backfill.js`,
  `backfill-appointment-images.js`, `backfill-clients-archived.js` — all four call
  `initializeApp({credential: applicationDefault()})`.
- **Opportunity:** the safety convention exists in 6 of 11 scripts and is
  implemented **two ways** — 3 use the shared `resolveProjectId`, 3 hand-roll a
  weaker banner, and the 4 above have none at all. So the scripts that write to
  whatever project ambient credentials resolve to, silently, include the one
  `docs/DEPLOYMENT.md:414` calls "**the irreversible one**" — and that script is
  the **next operational step** in the photo migration. The shared resolver also
  has a third fallback the hand-rolled copies lack (parsing
  `GOOGLE_APPLICATION_CREDENTIALS`' service-account JSON), so in exactly that
  credential setup the copies print `target: (unknown — check your credentials)`.
  It currently lives in `backfill-client-phone-formatting.js:89` — a one-off
  backfill acting as a shared module for two other scripts.
- **Suggested improvement:** move `resolveProjectId` + the banner into
  `functions/scripts/_project.js` as `printTargetBanner(app, {dryRun})`, beside
  the existing `_flags.js`/`_batch.js` that already set this convention; repoint
  all 6 and **add it to the 4 that have none**. Do this before running the clear
  script.

### I2 — Three release-critical paths have no test coverage at all · impact: high · confidence: high

- **`lib/core/security/app_lock.dart:162-166`** — the **successful unlock**
  transition never executes under test. `app_lock_test.dart:29` stubs
  `authenticate → false` and no test ever overrides it to `true` (the only other
  stub, `:170`, throws). `paused`/`hidden` lifecycle states are never pumped
  either. The *lock* side is pinned at both gates, as `CLAUDE.md` requires; the
  *release* side is entirely unguarded — a regression that never unlocks would
  ship green.
- **`lib/features/settings/.../delete_account_flow.dart:66, 152, 168`** —
  `restoreThisDevice` rollback, **zero references in `test/`**, all three arms
  unhit. The existing test fails during re-auth, i.e. before deregistration, so
  `deregistered` is null and the branch short-circuits. A failed deletion silently
  leaves a signed-in user de-registered from push, presence and Live Activity.
- **`lib/features/live_activity/.../live_activity_registration_controller.dart:107-303`**
  — 100 of 146 lines unhit (31.5%). `if (!Platform.isIOS) return;` at `:93`
  forces every test to bail on **the only platform that ships**. Includes
  `:117-125`, the opt-out branch that deletes stale server token rows.
- **Suggested improvement:** for the third, inject a platform predicate — the
  `WidgetSyncService(isIosPlatform:)` convention already in the repo. The first
  two need a stub override and a rollback test respectively.

### I3 — Client search does ~2.5× the per-document work it needs · impact: medium · confidence: high

- **Where:** `lib/features/clients/data/firebase_clients_repository.dart:326-350`.
- **Opportunity:** six normalize/regex-heavy values (`contactSearchText`,
  `displayName` via `stripPhone`'s two regexes, `normalize(rawDisplayName)`,
  `normalize(personName)`, and two `digitsOnly` calls) are computed for **every**
  document, then the filter at `:352` `continue`s. Only the scoring ladder at
  `:360-377` reads them, and that runs for at most 25 results. `normalize` is 8
  sequential `replaceAll`s. Cost is window size × ~4 redundant passes per
  committed search that misses the 2-minute cache; the window is 5000 and
  archive-not-delete means the roster only grows. It runs inside `compute`, so
  this is search **latency**, not jank: ~20-30 ms at today's ~700 clients,
  ~150-200 ms at the cap.
- **Suggested improvement:** move the `entryMatches(index(client), …)` test to
  immediately after `fromMap`, `continue` on a miss, and compute `:326-350` below
  it. Five-line move.

### I4 — History search builds a full record for every scanned doc to keep a handful · impact: medium-low · confidence: high

- **Where:** `lib/features/calendar/data/firebase_appointments_repository.dart:561`.
- **Opportunity:** the three fields the filter reads (`clientName`,
  `employeeNames`, `clientPhone`) are plain values on `doc.data`, but
  `AppointmentRecord.fromMap` (≈20 map reads, 4 date conversions, 2 list parses, a
  freezed constructor) is paid for all 5000 scanned documents. ~15-40 ms per query
  at the cap.
- **Suggested improvement:** read the three fields off `doc.data` for the test;
  move `fromMap` inside the `if`. Same omission as I3 — fix them together.

### I5 — The appointment sweep query + cap-warn + record-map is spelled out 3 times, and has already drifted · impact: medium · confidence: high

- **Where:** `functions/notification_utils.js:663-680` (`runOverduePromptSweep`),
  `:749-765` (`runDailyDigest`), `functions/travel_utils.js:555-572`
  (`runTravelAwareReminderSweep`).
- **Opportunity:** the same ~15-line block (status-`in` + two range `where`s +
  `orderBy` + `limit` + warn-at-cap + map). The first two use the shared
  `recordOf`; **`travel_utils.js` re-spells the mapper body inline** at `:570`
  *and* `:791`. The warn-at-cap pair alone appears **5 times** (add
  `notification_utils.js:859`, `live_activity_registry.js:324`).
- **Suggested improvement:** `scanAppointmentWindow(db, {statuses, field, lo, hi,
  desc, cap, logger, label, consequence})`. Each caller keeps its own cap, status
  set (`PENDING_STATUSES` is deliberately narrower) and consequence sentence —
  exactly the `pageToCap` precedent this repo already set for the Dart side.

### I6 — `Debouncer` + hoisted-logger boilerplate at 5 sites, for a rule that exists because one site got it wrong and shipped a FATAL · impact: medium · confidence: high

- **Where:** `main.dart:197`, `add_appointment_sheet.dart:69`,
  `details_edit_body.dart:53`, `appointment_history_view.dart:142`,
  `clients_list_view.dart:84` (plus the deviating
  `address_autocomplete_field.dart:48`).
- **Opportunity:** five restatements of the same rationale comment. Making
  `onError` required already closed the omission case; the remaining hazard is
  *where the logger is resolved*, which the prose has to ask for.
- **Suggested improvement:** `Debouncer.tagged(duration, {required AppLogger
  logger, required String tag})` in the existing `debouncer.dart`. A required
  `AppLogger` **parameter** makes lazy/in-callback resolution structurally
  impossible — and would have prevented 🟠 B2 and 🟠 B6 by construction.

### I7 — Five `build()`/method splits with an obvious seam · impact: medium · confidence: high

**45 `build()` methods exceed the project's stated ~60-line ceiling**
(`.claude/rules/code-quality.md:36`) — the rule is de facto unenforced. **Most
large files here are not god files**: `day_route_screen` (689) memoizes via
`_prepareBuild` and has four private sub-widgets, `event_details_controller`
(654) already delegates to `EventDetailsSavePipeline`, and the big JS files are
guard-clause-first. Size is comment density and widget-tree *width*, not tangle.
**Do not mass-refactor.** The five worth doing:

1. `client_search_field.dart:40-162` — `build()` **123 lines**, the worst. Three
   latent seams: `_searchInput()`, `_resultsDropdown()` (with the subtitle ladder
   as `_subtitleFor(client)`), `_noResults()`.
2. `busy_conflict_dialog.dart:9-132` — `showBusyConflictDialog()` **124 lines**,
   one flat tree inside a `showDialog` closure. Move to a private
   `_BusyConflictDialog extends StatelessWidget` (the file already has
   `_BusyEmployeeRow`); the launcher drops to ~10 lines.
3. `employee_picker.dart:28-134` — `build()` **107 lines**; `:52-110` is a
   self-contained chip. Extract `_EmployeeChip`; build drops to ~35 and the chip
   becomes const-able per row.
4. `appointment_image_upload_service.dart:124-243` — `_attempt()` **120 lines**.
   Split the per-file upload loop into `_uploadFiles(...)` returning a record;
   `AttemptOutcome.from` already proves the decision half wants to be separate.
5. `functions/wave/worker.js:344-446` — `reclaimStaleJobs()` **103 lines**. The
   `runTransaction` body is a **pure** decision; extract `reclaimDecision(...)`
   into the existing `retry_policy.js`, whose own header argues for exactly this
   split. All five branches are already tested — the win is moving three
   data-destructive decisions out of a transaction closure.

Also worth noting: `event_details_controller.dart:413-547 save()` (135) and
`add_event_controller.dart:218-348 submit()` (131) share a ~55-line pre-flight
seam. **These are the two highest-risk methods in the app** — touch only with the
45 existing `event_details_controller_test.dart` cases green.

**Explicit non-finding:** `themes.dart:50-229`/`:231-409` (180 + 179
near-parallel lines) looks like the worst offender and is **already guarded** by
`themes_test.dart:38` pinning that both themes configure the same sub-theme set.
Leave it.

### I8 — Two stale git worktrees inside the repo distort every future grep · impact: medium · confidence: high

- **Where:** `.claude/worktrees/login-redesign-remaining-4d0400` (17 MB,
  `fc8d2e34`) and `.worktrees/p7b-wave-invoices` (129 MB, `fd234cb8`).
- **Opportunity:** both are gitignored, so `git status` is clean and they are
  invisible — but they hold full stale copies of `lib/` and `.claude/rules/*.md`,
  so an unscoped `grep -rn` returns hits that look live and are not. That is a
  real hazard for exactly the dead-code and duplication sweeps this repo runs; it
  was hit twice during this audit. `IMG-URL`, deleted at HEAD, still "exists"
  there.
- **Suggested improvement:** `git branch --contains fc8d2e34` shows `redesgin`
  already contains it → **`git worktree remove` the first one**. The second is 20
  commits ahead with real unmerged Wave-invoices work → **keep**, but know it is
  there.

### I9 — `.claude/worktrees/` is ignored only via `.git/info/exclude`, which is not committed · impact: medium · confidence: high

- **Where:** `.gitignore:143` covers `.worktrees/`; lines 154-158 carry the
  explicit "`.claude/` is SHARED (Windows + Mac)" section. But
  `.claude/worktrees/`, `checkpoints/`, `mailbox/`, `agent-registry.json` are
  excluded only in machine-local `.git/info/exclude`.
- **Opportunity:** on the Mac clone none of those are ignored, so a worktree or
  agent-registry created there is untracked-and-visible and can be committed into
  the shared `.claude/`. Given this repo's history with exactly this class of bug
  (a bare `CLAUDE.md` pattern matching at every depth; a merge resurrecting
  `android/` with a live key), moving those patterns into `.gitignore` is cheap
  insurance.

### I10 — Eleven more test-coverage gaps, ranked by risk · impact: medium · confidence: high

Verified against lcov line-hit data, not filename mirroring (see the
methodological note below).

| Gap | Why it matters |
|---|---|
| `appointment_images_store.dart:158-160` | The `uploadedAt`-always-written invariant — the file's own contract says omitting it "would drop that photo out of the read entirely, with nothing erroring". Fixture leaves it null; **no assertion ever reads `body['uploadedAt']`**. Brand-new code, committed at HEAD. `:119-123` cap warn also unhit. |
| `firebase_appointments_repository.dart:191, 234` | `seriesOpId` producer. Server half is pinned, but **nothing asserts the id is the SAME across one batch or DIFFERENT across two calls** — the exact property that fixed "cancel Tuesday then Thursday → second push dropped". |
| `address_autocomplete_field.dart` | 307 lines, **no test file**, 22.5% lines. Unexercised: the known-FATAL post-dispose path, `_lastFetched` dedupe, `_requestId` stale discard, and the Places **session-token lifecycle** — three guards against *billed* API calls. |
| `firebase_appointments_repository.dart:169-183` | `getSeries` is the one bounded read missing from the cap-warning family; all 9 test hits are mocks. Truncation feeds `rewriteSeries`'s `deleteIds`. |
| `wave_service.dart:134-161` | `retryFailedJobs` — the only WaveService method with no service-level test, and its own comment says "This is the only way back" from a dead-lettered job. |
| `app_routes.dart:66` | The fail-closed `isAdmin: args?.isAdmin ?? false` default is unhit, and the whole `dashboard` case is unhit. The comment records the incident it prevents. |
| `widget_sync_service.dart:229-233` | The "an error is not a settled null" arm is unhit; a transient Firestore error would wipe the home-screen widget. |
| `firebase_appointments_repository.dart:511-516` | `findBusyEmployees` never reaches `dailyWindowsOverlap` under test (fixtures lack parseable times). The maths is pinned; the *wiring* is not. |
| `firebase_clients_repository.dart:293-298` | Contact-email normalization loop unhit; only the top-level email is asserted. |
| `delete_appointment_dialog.dart:8-32` | 0% covered; maps confirm→`thisOnly` vs `null` and routes a series to the scope dialog. Both building blocks are 93-99% covered — only the mapping is unguarded. |
| `firebase_clients_repository.dart:359-376` | The 6-tier relevance ladder has one test covering tiers 1 and 3. **Tiers 0 (exact), 2 (phone-prefix) and 4 (phone/contacts-substring) are untested**, as is the 25-result truncation. Since `clients/{id}.name` **IS the bare phone** for a person, the phone tiers matter most on real data, and a mis-rank silently drops a correct match past position 25. |

### I11 — Remaining documentation drift that needs a rewrite, not a pointer fix · impact: medium · confidence: high

Seven doc corrections were auto-applied. These five need a judgement call:

- **`.claude/rules/frontend.md:78, 114, 223-229` — tells you to build new sheets
  on two DELETED classes, and contradicts itself three ways.**
  `FormSheetScaffold` and `EntityFormHeader` have **zero declarations and zero
  call sites**; the only survivors are a tombstone comment in
  `form_sheet_frame.dart:16` and a stale test comment. Line 78 says
  "**`FormSheetScaffold` survives**", line 114 says `EntityFormHeader` is deleted,
  and line 223 says "**Use it for new form sheets**". The live class is
  `FormSheetFrame`. **This is the highest-value doc fix left** — it actively
  misdirects new work.
- **`.claude/rules/error-handling.md:68-71` — the registry's own regeneration
  procedure is wrong in both directions.** It claims "four sites pass the tag as a
  named `tag:` parameter (`LAUNCH-TEL`, `LAUNCH-EMAIL`, `IMG-SAVE`,
  `IMG-SHARE`)". Actual: **12** named `tag:` sites, and `IMG-SAVE`/`IMG-SHARE` are
  *not* among them (they are positional args to `_runExclusive`). Omitted:
  `LAUNCH-MAPS`, `LAUNCH-URL`, `LIVE-ACT`, `PUSH`, `PRESENCE`, `APPT-SAVE`, plus
  the 4 interpolated Wave ones. Following it as written misses seven tags — and
  this is the procedure that keeps the registry EXHAUSTIVE.
- **`.claude/rules/testing.md:70-75` — an Android device-verification workflow.**
  Gives `adb` commands against `net.vogas.scheduling`. Root `CLAUDE.md` makes
  iOS-only load-bearing and `git ls-files android` → 0. The bullet actively pushes
  toward the tree resurrection the root file exists to prevent.
- **`functions/CLAUDE.md` `changeEmployeeEmail` bullet — the guard order omits a
  guard.** Says "auth → payload → identity → rate limit → work"; there are five,
  with `assertFreshReauth` between identity and the limiter —
  `employee_accounts.js:509-511` says so in its own comment. The same file's
  `security.js` module map omits `hasControlChar`, `isReauthStale` and
  `assertFreshReauth` — the last being the guard `.claude/rules/security.md:30`
  holds up as *the shape to copy*.
- **`functions/appointment_images.js:78-79` — comment contradicts
  `firestore.rules`.** Says the `pictures` array's 100-entry cap "the CONTRACT step
  removed"; `firestore.rules:559-564` **still enforces** `d.pictures.size() <= 100`,
  deliberately, for documents the clear script has not reached.
  `.claude/rules/images.md:238` words it more carefully but still reads as if the
  clause is gone.

Minor/inverse: `assignee_resolver_test.dart:5` says `assigneeNameAt` has "six call
sites"; there are 5, and root `CLAUDE.md` correctly says five — the *test comment*
is the stale one. And `docs/ARCHITECTURE.md:1268` says 2611 flutter / 1348 jest;
actual at HEAD is **2608 / 1343**.

### I12 — Three `functions/wave/customers_import.js` exports claim a test that does not exist · impact: medium · confidence: high

- **Where:** `functions/wave/customers_import.js:281-287` — `importOneCustomer`,
  `buildWaveIdIndex`, `BATCH_LIMIT`.
- **Opportunity:** the export block's comment says *"Exported so the two decisions
  the page loop delegates can be driven directly from a unit test"* — but no file
  requires `customers_import` except `wave/customers.js`, which re-exports only
  `importCustomers`. `buildWaveIdIndex` has exactly one hit repo-wide, **inside a
  comment** at `wave_customers.test.js:891`. So the exports are inert *and* the
  comment asserting they are tested is false. This is a **coverage gap wearing a
  dead-export costume**.
- **Suggested improvement:** write the tests the comment promises (both decisions
  are covered today only indirectly, through `importCustomers`), rather than
  deleting the exports.

### I13 — Smaller duplication and cleanup, each below the "act now" bar

- **`adminFirestore()` lazy-require, 4 verbatim copies** —
  `client_propagation.js:53`, `wave/customers.js:139`,
  `wave/customers_import.js:32`, `wave/worker.js:113`. Encodes a load-order rule
  (`functions/CLAUDE.md`: a module touching admin at load can't be tested) and is
  already drifting — `worker.js`'s JSDoc promises `Timestamp`, the others don't. →
  `functions/admin_firestore.js`, the precedent `params.js` sets.
- **Device-registration account gate, 3 controllers** —
  `push_registration_controller.dart:84`,
  `live_activity_registration_controller.dart:126`,
  `presence_sync_controller.dart:108`. Identical 6-line preamble carrying two
  non-obvious decisions (an unsettled/errored doc is a **return**, not a "no";
  role/status read as trimmed strings). The *predicate* is already shared; this
  preamble is not. → `readAccountGateInputs(ref, auth)`.
- **`AppRadius.r24` (`design_tokens.dart:180`)** — the only zero-usage design
  token of 31 checked. Arguably a deliberate rung on a scale; your call.
- **`require("crypto")` vs `require("node:crypto")`** — `employee_accounts.js:6`,
  `security.js:1`, `wave/mappers.js:10` vs `apns_client.js:23`.
- **Six raw `EdgeInsets.fromLTRB`** mixing token values with off-scale nudges
  (`inline_month_calendar.dart:17`, `calendar_header_block.dart:73`,
  `calendar_month_grid.dart:18`, `app_nav_drawer.dart:68` & `:344`,
  `app_header_pair.dart:54`). Consistent with the documented "sub-4px nudges are
  raw on purpose" decision, so partial tokenization would arguably read worse.
  Listed for completeness, not recommended.
- **`address_autocomplete_field.dart:66`** re-spells its own `_debounceDelay =
  700ms` rather than using a shared constant.
- **`app_routes.dart:74, 86, 96, 105, 114, 124, 140`** — seven
  `settings.arguments!` while the `dashboard` case above was deliberately made
  null-tolerant. Unexplained asymmetry: a red screen vs a degraded screen. Worth a
  decision, not necessarily a change.

## 🟡 Code-quality suggestions (optional)

Convention drift came back **almost entirely clean** — each verified, not just
grepped:

- `ScaffoldMessenger.showSnackBar`: exactly **3** sites, all through the shared
  `errorSnackBar` helper, matching the documented carve-out.
- `throw Exception(...)`: **0** in `lib/` and `functions/`.
- `FirebaseFirestore.instance` in a widget/UI file: **0** (all 4 uses are in
  providers, `AuthService`, or `main()`).
- Hardcoded `Color(0x…)` outside `lib/core/theme/`: **1**, a decorative
  `SweepGradient` (`employee_color_grid.dart:200-206`) with an in-line comment
  stating it deliberately ignores the theme. Not drift.
- Branching on `isDark` for styling: **0**.
- `DateFormat` constructed inside a cell/item builder: **0**.
- Raw `Stream.listen()` without `onError`: **0** (paren-balanced scan).
- Code markers and commented-out code: **0**. The only markers are 8 conforming
  `NOTE:` entries. The two `debugPrint` calls in `main.dart:73,83` are the
  deliberate pre-Firebase-init crash fallback.

The only live drift is 🟠 B2 (`ref.read` in a `catch`), reported as a bug because
one of the two sites is a genuine latent crash path.

## Notes / uncertainties

- **A "no mirrored test file" signal is near-worthless in this repo.** Coverage
  lives under the *caller's* test name — four candidate gaps were verified away
  (`matchClientDocs`/`ClientSearchScan` via `searchClients()`;
  `importOneCustomer`/`buildWaveIdIndex` via 14 tests in
  `wave_customers.test.js:942-1266`; `importWithWatermark` via
  `wave_callables.test.js:414-475`; `pageToCap`/`normalizeEmail` at their call
  sites). Every gap in I2 and I10 was confirmed against lcov line-hit data.
- **17 CLAUDE.md invariant helpers were spot-checked and every one is pinned**
  (`mergeRetainedAssignees`, `isAccountDeletionSignal`, `terminalStatusRawValues`,
  `displayStatusAt`, `runsOn`, `hasWorkLeft`, `liveActivityCtx`,
  `appointmentImageDocId`, `isValidAppointmentSpan`, …). `maintenance_policy.js` —
  the only unattended irreversible deletion in the repo — is at **100% lines and
  branches**.
- **Complexity: nothing to do.** A nesting scan across `lib/` and `functions/`
  returned only false positives — chains of flat `if (x) return;` guards. The
  codebase is consistently guard-clause-first; there is no "rewrite with early
  returns" work. The one genuine branch-density case,
  `wave/customers.js:260-386 upsertCustomer()` (127 lines, 5 exits), is a money
  path whose refactor risk exceeds the readability gain — **leave it**.
- **Dependencies: nothing removable.** All 4 pubspec heuristic hits are documented
  false positives (`build_runner`/`freezed` drive 9 live `.freezed.dart` files;
  `flutter_launcher_icons` has its config block at `pubspec.yaml:179`;
  `google_maps_flutter_ios_sdk9` is the deliberate SPM override, confirmed by
  `GeneratedPluginRegistrant.m`). `functions/package.json` is fully used, with no
  undeclared deps.
- **l10n: nothing to do.** 711 keys in each ARB, zero drift either way, zero
  missing `@key` blocks, zero orphans (verified twice — loose identifier index and
  member-access-only scan), corroborated by an empty
  `lib/l10n/.gen/untranslated.json`.
- **Not verifiable from this box:** whether any prod `appointments/*/images` doc
  carries a `url` with an empty `storagePath` (🔴 S1). Firebase MCP Firestore reads
  fail `read_time cannot be in the future` due to local clock skew — a known,
  recorded limitation. This needs a one-shot count run by hand, and it decides both
  S1's severity and B5's wording.
- **`IMPORT_FIELD_CAPS` (`wave/mappers.js:512`) is NOT dead** despite looking
  unreferenced to any JS scan — it is read **as source text** by
  `test/core/validators/text_limits_test.dart:239`, a JS→Dart reference no grep of
  `functions/` will find. Recorded so it is not re-derived next time.

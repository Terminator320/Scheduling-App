# Cloud Functions Reference

Map of every Cloud Function in `functions/` — what it does, how it's
triggered, who calls it, and its security posture. Generated 2026-07-05,
refreshed 2026-07-21 by auditing the source against the app's call sites and
the live deployment (the iOS Live Activity stack added behind
`notifyAppointmentChanges` / `sendUpcomingJobReminders` — APNs secrets, direct
HTTP/2 client; `purgeExpiredHistory`'s timeout corrected to the 1800s scheduled
-trigger max; `sendUpcomingJobReminders` previously rebuilt into the
travel-aware "time to leave" sweep — `travel_utils.js`, Routes API,
`GOOGLE_MAP_API_KEY` shared via `params.js`).
**Every callable now enforces App Check** (`enforceAppCheck: true`); the
earlier `TODO(pre-ship)` carve-outs were retired in 1.25.1
(`grep -rn "enforceAppCheck: false" functions` returns nothing).

- **Project:** `schedulingapp-88727` · **Region:** `us-central1` (except
  `validateUploadedImage`, pinned to `us-east1` by its Storage bucket)
- **Runtime:** Node.js 24, 256 MB, `maxInstances: 10` global
  (`setGlobalOptions` in `index.js`)
- **Wiring:** `index.js` is a thin re-export surface; implementations live in
  domain modules. Shared callable guards (`assertPayloadShape`, `requireString`,
  `readSessionToken`, `enforceDurableRateLimit`, `assertAdmin`) live in
  `security.js`.
- **Deploy:** `firebase deploy --only functions,firestore:rules,firestore:indexes,storage`
  (run `cd functions && npm run lint` first).

## Deployment status

- **21 functions defined** in code; **all 21 deployed** — verified live against
  `schedulingapp-88727` on 2026-07-18 (v2, Node.js 24, 256 MB; `us-central1`
  except `validateUploadedImage` in `us-east1`). The 2026-07-18 deploy shipped
  `placesReverseGeocode`, the travel-aware `sendUpcomingJobReminders` rebuild,
  and the codebase-audit fixes (overdue-sweep ordering, bounded travel-context
  query, client-data rule length caps).
- The 4 **push-notification functions** (`notifyAppointmentChanges`,
  `sendUpcomingJobReminders`, `sendDailyJobDigest`, `sendOverdueJobPrompts`)
  and the 2 **Wave auto-import cadence functions** (`waveSetImportSchedule`,
  `waveScheduledImport`) were **deployed 2026-07-11** together with the updated
  `firestore.rules`. The one-time Firestore **TTL policy** on `expiresAt` for
  the `appointmentReminders` / `appointmentOverduePrompts` ledgers was
  **enabled in the console 2026-07-11** — this list previously said it was still
  outstanding, which was wrong. Still outstanding: on-device push verification.
  TTL was extended to `liveActivityTokens`, `rateLimits`, and `signupCodes` on
  2026-07-20, and a `fieldOverride` for the new `appointmentSeriesNotices` claim
  ledger was added to `firestore.indexes.json` on 2026-07-21 (that ledger has no
  in-code reaper, so the TTL is its only cleanup). Every policy's **expiration
  offset normalized to `0`** — the
  code writes `expiresAt` as the absolute deletion instant, so a non-zero offset
  adds to it and silently doubles retention (the ledgers had been running at
  ~14 days, not 7). `liveActivityCards` has no policy yet: Firestore only offers
  collection groups that already hold documents, and no card marker exists until
  the feature runs on a device. Every one of these is also swept in-code, so TTL
  is storage housekeeping, not correctness. The iOS-native
  APNs key + Push/App-Groups entitlements were wired on the Mac 2026-07-11 (see
  `docs/archive/2026-07-08-push-notifications.md`).
- **Deployed 2026-07-18 (1.33.0):** the travel-aware `sendUpcomingJobReminders`
  rebuild went live. One console step still gates full travel-awareness — the
  **Routes API** must be enabled and added to the `GOOGLE_MAP_API_KEY`
  restriction; until that's verified the sweep logs Routes failures and delivers
  the 30-min fallback (never worse than the old behavior). See
  `docs/archive/2026-07-09-travel-time-notifications.md`.
- **Deployed 2026-07-19 (1.34.1):** the iOS Live Activity dispatch inside
  `notifyAppointmentChanges` / `sendUpcomingJobReminders`, the deep-audit fixes
  (deactivation now revokes Auth access + purges delivery state in
  `syncUsersByUid`; the `status == 'active'` gate in `firestore.rules` /
  `storage.rules`; Wave guard ordering; the travel-sweep estimate memo), and
  **two new composite indexes** — `liveActivityTokens (kind, employeeDocId)` at
  COLLECTION_GROUP scope and `liveActivityCards (phase, startTime)`. Those
  indexes are what make the Live Activity feature work at all; without them the
  registry queries fail `FAILED_PRECONDITION` and the best-effort catch turns it
  into a silent no-op. Remaining gate is on-device verification. Runbook:
  `ios/ScheduleWidget/LIVE_ACTIVITY_README.md`.
- `backfillLegacyClientNames` (a one-time migration completed `2026-06-29`,
  `fixed: 0`) was removed from the codebase 2026-07-05 and is **no longer in the
  deployed set** (confirmed 2026-07-10) — it was pruned by a full
  `firebase deploy --only functions`.

## Summary

| Function | Type | Trigger / event | Module | Called by / fired on | Secret | Guard |
|---|---|---|---|---|---|---|
| `placesAutocomplete` | callable | `onCall` | `places.js` | `google_places_repository.dart` (address field typing) | `GOOGLE_MAP_API_KEY` | App Check ✓ · admin · in-mem 20/min·uid |
| `placesGetDetails` | callable | `onCall` | `places.js` | `google_places_repository.dart` (address selected) | `GOOGLE_MAP_API_KEY` | App Check ✓ · admin · durable 40/15min |
| `placesReverseGeocode` | callable | `onCall` | `places.js` | live staff-location map (admin) | `GOOGLE_MAP_API_KEY` | App Check ✓ · admin · durable 120/hr |
| `deleteAccount` | callable | `onCall` | `account.js` | `account_deletion_service.dart` | — | App Check ✓ · reauth ≤5min · durable 5/15min |
| `createEmployeeInvite` | callable | `onCall` | `invites.js` | `firebase_employees_repository.dart` | — | App Check ✓ · admin · durable 20/hr·uid |
| `redeemSignupCode` | callable | `onCall` | `invites.js` | `firebase_employees_repository.dart`, `auth_service.dart` | — | App Check ✓ · durable 5/15min·**email** |
| `waveBootstrap` | callable | `onCall` | `wave/callables.js` | `wave_service.dart` | `WAVE_FULL_ACCESS_TOKEN`, `WAVE_BUSINESS_NAME` | App Check ✓ · admin · durable 10/hr |
| `waveGetConnection` | callable | `onCall` | `wave/callables.js` | `wave_service.dart` (Settings mount) | — | App Check ✓ · admin |
| `waveSetImportSchedule` | callable | `onCall` | `wave/callables.js` | `wave_service.dart` (Settings cadence picker) | — | App Check ✓ · admin |
| `waveImportCustomers` | callable | `onCall` | `wave/callables.js` | `wave_service.dart` | `WAVE_FULL_ACCESS_TOKEN` | App Check ✓ · admin · durable 5/hr · 300s |
| `syncUsersByUid` | trigger | `onDocumentWritten users/{id}` | `bridge.js` | any `users` doc write | — | `retry: true` |
| `propagateClientEdits` | trigger | `onDocumentUpdated clients/{id}` | `client_propagation.js` | any `clients` doc edit | — | `retry: true` |
| `waveUpsertCustomer` | trigger | `onDocumentWritten clients/{id}` | `wave/callables.js` | any `clients` doc write | — | `retry: true` |
| `validateUploadedImage` | trigger | `onObjectFinalized` (Storage) | `maintenance.js` | `appointments/*/images/*` upload | — | region `us-east1` |
| `notifyAppointmentChanges` | trigger | `onDocumentWritten appointments/{id}` | `notifications.js` | any appointment write | `APNS_AUTH_KEY` · `APNS_KEY_ID` · `APNS_TEAM_ID` | no `retry` (dupe push worse than missed) |
| `purgeExpiredHistory` | scheduled | `0 3 1 1,4,7,10 *` — quarterly, 1st of Jan/Apr/Jul/Oct 03:00 (Toronto) | `maintenance.js` | quarterly | — | `maxInstances: 1` · 1800s |
| `waveSyncWorker` | scheduled | `every 5 minutes` | `wave/callables.js` | timer | `WAVE_FULL_ACCESS_TOKEN` | `maxInstances: 1` · 540s |
| `waveScheduledImport` | scheduled | `every 24 hours` | `wave/callables.js` | timer | `WAVE_FULL_ACCESS_TOKEN` | `maxInstances: 1` · 300s |
| `sendUpcomingJobReminders` | scheduled | `every 5 minutes` (Toronto) | `notifications.js` + `travel_utils.js` | timer | `GOOGLE_MAP_API_KEY` · `APNS_AUTH_KEY` · `APNS_KEY_ID` · `APNS_TEAM_ID` | `maxInstances: 1` · `timeoutSeconds: 120` · ledger · Routes API |
| `sendDailyJobDigest` | scheduled | `0 18 * * *` (Toronto) | `notifications.js` | timer | — | `maxInstances: 1` |
| `sendOverdueJobPrompts` | scheduled | `every 15 minutes` (Toronto) | `notifications.js` | timer | — | `maxInstances: 1` · 300s · ledger |

## Auth & accounts

### `deleteAccount` — `account.js`
Self-service account deletion (Apple 5.1.1(v) / Google Play account-deletion
policy). Deletes the caller's `users/{docId}` doc via `recursiveDelete` (the
doc **plus all its subcollections** — today that is `fcmTokens`, `presence`,
and `liveActivityTokens`) and their Firebase Auth user; the `syncUsersByUid`
trigger then clears the `usersByUid` bridge. Deliberately
does **not** touch shared business data (appointments, clients, images).
Requires a fresh re-auth: rejects `stale-auth` if the ID token's `auth_time` is
older than 5 minutes (checked before the rate limiter so a stale rejection
doesn't burn a slot). Durable-rate-limited 5 per 15 min per uid; refunds the
slot if the Auth delete fails server-side. Auth user is deleted **first**
(irreversible step), then the Firestore doc. App Check enforced.

## Employee invites (one-time signup codes)

### `createEmployeeInvite` — `invites.js`
Admin-only. Creates (or idempotently re-issues) an `invited` `users` doc plus a
`signupCodes/{sha256(code)}` doc, and returns the **plaintext code once** for the
admin to share out-of-band. Everything — duplicate-email lookup, prior-code
sweep, writes — runs in one Firestore transaction to close create/redeem races.
A claimed (non-`invited`) email is rejected. Durable-rate-limited 20/hr per admin
uid — the payload is validated (`assertPayloadShape`/`requireString`) **before**
the limiter, so a burst of malformed submissions can't exhaust a legitimate
admin's window, while `assertAdmin` stays above the limiter so non-admins still
can't burn slots. Full flow: `docs/archive/INVITED_SIGNUP_REDESIGN.md`.

### `redeemSignupCode` — `invites.js`
Validates a signup code server-side (14-day expiry; token email must equal the
invite email) and **activates the account atomically** (`uid` + `status:'active'`,
code consumed). A valid code whose token email ≠ invite email returns a distinct
`code-email-mismatch`. Rate-limited 5 per 15 min **by token email**, not caller
uid — a failed signup mints a fresh uid, which would reset a uid-keyed cap.
Both invite callables share `APP_CHECK = {enforceAppCheck: true}`.

## Maps / Places proxies

### `placesAutocomplete` — `places.js`
Proxies Google Places API (New) autocomplete so the billing-sensitive
`GOOGLE_MAP_API_KEY` (Secret Manager) never ships in the app binary. App Check +
auth + **`assertAdmin`** required — the address field is only surfaced on the
admin-only appointment form, so gating on admin stops a non-admin (or
invited-but-inactive) principal from scripting the billable API. Fires on
address-field typing, so it's the **highest-volume, highest-cost** function —
the Places API bills separately per request. Rate-limited in-memory 20/min per
uid (per-instance, resets on cold start, multiplies by `maxInstances` — set a
GCP Maps Platform billing alert; this is not a hard cap).

### `placesGetDetails` — `places.js`
Proxies Places details for a selected address (one billable call per address the
user actually picks). Same guards as autocomplete (App Check + auth +
`assertAdmin`). Uses the durable Firestore rate limiter (40 per 15 min) — lower
volume, but each call is more expensive, so a hard cap matters.

### `placesReverseGeocode` — `places.js`
Backs the live staff-location map: turns a lat/lng into a human-readable
address. Callable — App Check + auth + `assertAdmin` + durable Firestore rate
limiter (120 per hour per uid; a tap-driven, not keystroke-driven, surface, so
a generous hourly cap suffices). Validates `lat`/`lng` are numbers in their
valid ranges and `locale` is an allowlisted value (`en`/`fr`); rounds
coordinates to 5 decimal places before the upstream call so GPS jitter can't
multiply request volume. Calls the classic Geocoding API (not Places v1, which
has no reverse-geocode mode) with `GOOGLE_MAP_API_KEY`, and returns only the
top result's `formatted_address` (or `null` on `ZERO_RESULTS`) — never logs
coordinates or resolved addresses. **Deployed to prod 2026-07-18.**

## Images

### `validateUploadedImage` — `maintenance.js`
Storage `onObjectFinalized` trigger. For every upload under
`appointments/{id}/images/`, reads the first 8 bytes and deletes the object
server-side unless it's real JPEG (`FF D8 FF`) or PNG (`89 50 4E 47`) — the
Storage rule trusts client `contentType`, so this closes that gap. Deployed to
`us-east1` (follows the Storage bucket region).

## Maintenance (scheduled)

### `purgeExpiredHistory` — `maintenance.js`
Quarterly on the 1st of Jan/Apr/Jul/Oct at 03:00 America/Toronto
(`0 3 1 1,4,7,10 *`). Deletes `done`/`cancelled` appointments whose `startTime`
is older than 2 years, **and** their Storage images. Images are deleted before
the Firestore doc so a Storage failure keeps the doc for the next run's retry
rather than orphaning PII bytes. Non-terminal appointments are never touched.
1800s timeout — the real max for a **scheduled** trigger (a higher value is
rejected at deploy, not silently clamped) — so a quarter of newly-expired
history clears in one run; the loop commits page-by-page, so any leftovers (a
timeout, or a full page whose image deletes all fail) carry to the next run —
~3 months away at this cadence.

## Push notifications (FCM)

All four live in `notifications.js` (thin trigger registrations); the logic —
diff/message/candidate helpers plus the injectable orchestration — is in
`notification_utils.js` (no admin/scheduler requires, so jest drives it with
mocked `{db, messaging, now, logger}`). Recipients are always filtered
server-side to `role == 'employee' && status == 'active'`; tokens live in
`users/{docId}/fcmTokens/{token}` (doc id = token, keyed by users **doc id**
so the send path needs no uid translation), and stale tokens are deleted on
send failure. Text is localized per token doc (`locale: 'en'|'fr'`) from an
inline EN/FR table; every message sets `android: {priority: 'high'}` and an
APNs `sound` so delivery isn't doze-deferred/silent. **Deployed 2026-07-11**
— see Deployment status. Design: `docs/archive/2026-07-08-push-notifications.md`.

### `notifyAppointmentChanges` — `notifications.js`
`appointments/{id}` write trigger → assignment / reschedule / cancel /
unassignment pushes. Diffs before/after (`diffAppointmentForNotifications`):
one event per employee, priority `cancelled > removed > rescheduled >
assigned`; past appointments skipped. Deliberately **no `retry: true`** — a
duplicate push is worse than a rare missed one. **A repeat series collapses to
ONE push per (employee, kind)** via the Admin-SDK-only
`appointmentSeriesNotices` claim ledger (`claimSeriesNotice`): a "this and all
future" edit writes ~15 sibling docs in one batch, each firing this trigger, so
without the claim the tech got ~15 pushes. It **fails OPEN**. WRITES key the
claim on a fresh client-stamped **`seriesOpId`** (`_newSeriesOpId` in the
repository — one uuid per write op, shared by that batch, reused by nobody), so
a collision is definitive and needs no time window and two separate actions
both notify. DELETES have no fresh id (`before.seriesOpId` is stale), so they
fall back to `(seriesId, kind, employee)` + `SERIES_CLAIM_WINDOW_MS` (45 s) +
stale-takeover. Also updates/ends any live
"time to leave" card for the changed job, so it binds `APNS_SECRETS` and gets
`liveActivityDeps()`; the two Firestore-only sweeps below take `liveDeps()`
instead, because reading a secret param a function didn't bind logs a warning
on every invocation.

### Live Activity dispatch (no separate export)
The iOS Lock Screen card has **no function of its own** — it rides
`notifyAppointmentChanges` (update/end) and `sendUpcomingJobReminders` (start).
FCM cannot carry it: a Live Activity push needs `apns-push-type: liveactivity`
on topic `net.vogas.scheduling.push-type.liveactivity`, so `apns_client.js`
talks **directly to APNs over HTTP/2** with an ES256 provider JWT (cached, re-
minted at 50 min) built from `APNS_AUTH_KEY` / `APNS_KEY_ID` / `APNS_TEAM_ID`.
Every path is best-effort: missing secrets, no registered token, or any APNs
error degrades to the plain `leaveNow` push, which is unchanged. Targets resolve
through the Admin-SDK-only `liveActivityCards/{employeeDocId}` marker plus the
self-only `users/{docId}/liveActivityTokens` rows; both carry `expiresAt` for a
TTL prune (the rules cap a client-written `expiresAt` at `request.time + 31 d`,
just above the app's 30-day push-to-start TTL). Card text is built server-side
in EN/FR (`live_activity_utils.js`).

Two **composite indexes are load-bearing** here: `liveActivityTokens`
`(kind ASC, employeeDocId ASC)` at **COLLECTION_GROUP** scope, and
`liveActivityCards` `(phase ASC, startTime ASC)`. Both queries are wrapped in
the feature's best-effort catch, so a missing index surfaces as
`FAILED_PRECONDITION` swallowed into "the card never appears" rather than an
error — deploy `firestore:indexes` alongside the functions. The travel→on-site
flip (`runOnSiteFlipPass`) runs on **every** sweep, not only when travel
candidates exist: a tech whose job has already started is by definition no
longer a candidate, and this pass is also what clears markers for
deleted/terminal jobs. EVERY terminal transition — done, cancelled, deleted,
and unassigned — ends the card server-side from the appointment write trigger
(`endCardOnTerminal`, generalized from the done-only `endCardOnCompletion` on
2026-07-21) — the client never ends cards off its own status write, since
`endAllActivities()` is device-wide.

### `sendUpcomingJobReminders` — `notifications.js` (+ `travel_utils.js`)
Every 5 min (Toronto). **Travel-aware "time to leave" sweep**
(`runTravelAwareReminderSweep`): queries `status in [pending, confirmed]`
(legacy alias) with `startTime` in `(now, now+90min]` on the existing
`(status, startTime)` index. Per (job, assignee) it picks a departure origin —
an intervening job's address → a fresh background-GPS presence doc
(`updatedAt` ≤ 25 min) → a recently-ended job's address (≤ 4 h) → none — via one
per-employee context query (`(employeeIds CONTAINS, endTime ASC, startTime ASC)`
index, bounded by `CONTEXT_QUERY_MAX` and by an `endTime` ceiling of
window + max-booking — narrowing that ceiling to the travel window alone would
drop a long intervening job that started inside the window but runs past it)
plus a batched `getAll` of the presence docs, then calls Google Routes
API `computeRoutes` (`TRAFFIC_AWARE`) and fires at
`startTime − driveTime − 10min` (lead capped at 90 min). **Every failure path —
no origin, empty address, any Routes error — degrades to the fixed 30-min
`reminder` kind**, so it never regresses below the old behavior; the `leaveNow`
kind sets APNs `interruption-level: time-sensitive`. Needs the
`GOOGLE_MAP_API_KEY` secret (shared via `params.js`) and `timeoutSeconds: 120`;
requires the **Routes API** enabled and added to the key's API restriction.
Drive-time estimates are memoized per (job, assignee) for ~10 min so a job
sitting in the 90-min window isn't re-priced on all ~18 sweeps before it fires;
a cached estimate may only ever **defer** a Routes call, never trigger a send.
Fires one localized reminder per assignee, exactly-once **per recipient** via
the Admin-SDK-only
`appointmentReminders/{id}_{startMs}_{employeeDocId}` ledger (`create()` fails
if it exists; a reschedule changes the key → fresh reminder). Per-recipient
keying means an assignee whose token registers late is retried independently
without re-notifying an assignee already delivered (a per-occurrence ledger
would drop the late one for good). As in the overdue sweep, a claim that
delivered **zero** pushes (no live token registered yet, or the send threw) is
released so a later sweep retries while the job is still upcoming, and each
recipient's send is isolated so one transient failure can't abort the sweep.
Ledger docs carry `expiresAt` (+7 d) for the console-enabled Firestore TTL
policy.

### `sendDailyJobDigest` — `notifications.js`
Daily 18:00 Toronto. Groups tomorrow's (Toronto-midnight-bounded) jobs by
employee; one summary push per employee with ≥1 job. No ledger (runs once
daily; a rare crash-retry duplicate is accepted). Queries `status in
OPEN_STATUSES` (`pending`/`in_progress`/legacy `confirmed`, single-sourced from
`OPEN_LIKE`) — it previously hardcoded `["pending", "confirmed"]`, silently
dropping every `in_progress` job from the digest even though the pure grouping
filter excludes only `cancelled`; the query and filter now agree.

### `sendOverdueJobPrompts` — `notifications.js`
Every 15 min (Toronto). The "job finished?" nudge: pushes assignees of a job
whose `endTime` passed within the last 24 h while its status is still open
(`pending`/`in_progress`/legacy `confirmed` — server mirror of the app's
display-only `overdue` state; nothing is ever stored). Queries by `startTime`
over the last **48 h** (24 h eligibility + the <24 h max booking) **ordered
`startTime` DESC** (existing `(status, startTime DESC)` index — no new index)
so the `OVERDUE_SWEEP_MAX` cap keeps the newest-overdue jobs rather than the
oldest, then filters `endTime ∈ (now-24h, now]` in code. At-most-once
**per recipient** via the
`appointmentOverduePrompts/{id}_{endMs}_{employeeDocId}` ledger; a claim that
delivered **zero** pushes is released (doc deleted) so a later sweep retries
that recipient, and each recipient's send is isolated so one transient failure
can't abort the sweep. Candidates are processed serially, so it carries a **300s
timeout** (well over the 60s default) to keep a backlog from leaving the newest
overdue jobs unprompted.

## User → uid bridge

### `syncUsersByUid` — `bridge.js`
`users/{id}` write trigger that mirrors each user into `usersByUid/{uid}` so
security rules can resolve a caller's role from their auth uid alone (rules can
only `get` by full path, and `users` docs use generated ids). Suppresses the
bridge for `invited` users (no uid yet) and unknown statuses; handles uid
rotation (stale delete + new set in one batch). `retry: true` — all writes are
absolute, so retries converge.

It also owns **deactivation enforcement**, all of it strictly after the
auth-critical bridge write and each step independently idempotent: leaving
`active` disables the Firebase Auth account and revokes its refresh tokens, then
purges `presence/location`, the `fcmTokens` and `liveActivityTokens`
subcollections (`recursiveDelete`, so >500 rows can't fail partway), and the
`liveActivityCards/{docId}` marker. Entering `active` re-enables the account.
`auth/user-not-found` is swallowed — `deleteAccount` removes the Auth user
before the Firestore doc, so the trigger's later revoke is a no-op rather than a
retry loop. Without this the rules' `status == 'active'` gates would still be
reachable with a stale credential.

## Client → appointment propagation

### `propagateClientEdits` — `client_propagation.js`
`clients/{id}` update trigger that propagates a client's edited `clientName` /
`clientPhone` / `address` to that client's **future** appointments (history is
left as it was at visit time). `address` follows the client only when the
appointment's stored address equals the client's *previous* address (a differing
one is treated as a per-appointment custom address). Requires the composite index
`(clientId ASC, startTime ASC)` on `appointments`. `retry: true` — writes are
absolute values. **Deployed** (verified live 2026-07-10).

## Wave Accounting

Admin-only integration syncing the `clients` collection to Wave customers. The
full-access Wave token lives in Secret Manager (`WAVE_FULL_ACCESS_TOKEN`); the
target business is resolved server-side from `WAVE_BUSINESS_NAME`. The app never
reads the rules-locked `wave` collection directly. The integration's invariants
(import timestamps, outbox transactionality, cadence) live in the Wave bullet of
CLAUDE.md; the original ultra-review findings are archived at
`docs/archive/WAVE_REVIEW_FINDINGS.md`. (An older `WAVE_INTEGRATION_PLAN.md` was
deleted in `189772a` — don't restore the pointer.)

All four Wave callables run the guards in the documented order — auth →
`assertAdmin` → `assertPayloadShape` → rate limit. `assertAdmin` above the
payload check keeps a non-admin from distinguishing `unexpected-field` from
`wave/not-admin`; the limiter stays below both so a rejected caller can't burn a
legitimate admin's slots.

### `waveBootstrap` — `wave/callables.js`
Admin-only, idempotent get-or-create of the `wave/connection` doc. An
already-connected doc short-circuits (not rate-limited); the not-yet-connected
path makes live Wave calls (`whoami` + `listBusinesses`) and is rate-limited
10/hr. Business is chosen server-side — the app sends no selector.

### `waveGetConnection` — `wave/callables.js`
Admin-only read of `wave/connection` — the **only** Wave read path for the app
(the Settings Wave section calls it on mount to show "Connected to X"). No
secret, no rate limit.

### `waveSetImportSchedule` — `wave/callables.js`
Admin-only setter for the automatic-import cadence — writes the `importSchedule`
field (`off` | `weekly` | `monthly`) on `wave/connection`. Validates the value
against the shared `SCHEDULE_VALUES` set and requires an already-bootstrapped
connection. No secret, no rate limit (a single cheap Firestore write).

### `waveImportCustomers` — `wave/callables.js`
Admin one-shot Wave → app customer seed (paginates ~650 customers over ~7 Wave
pages). Writes `createdAt`/`updatedAt` on every client doc (the list/search order
by `createdAt`, and Firestore excludes docs missing the orderBy field).
Rate-limited 5/hr; 300s timeout.

### `waveUpsertCustomer` — `wave/callables.js`
`clients/{id}` write trigger. When a client's Wave-mapped fields change, marks
the doc `wave.syncState: pending` and enqueues a `customerUpsert` job on the
`waveSyncQueue` outbox (deterministic job id → burst edits collapse to one job).
Both writes land in one batch. No secret (only writes to Firestore). `retry:
true` — idempotent and hash-guarded.

### `waveSyncWorker` — `wave/callables.js`
Scheduled outbox drainer, **every 5 minutes**, single instance. Claims queued
jobs transactionally, dispatches the Wave upsert, and writes the outcome under a
concurrent-re-enqueue guard; a lease-reaper reclaims jobs stranded by a crashed
instance. `batchLimit` 30 × 5-min cadence = 6 Wave calls/min (Wave allows 60/min).
540s timeout with a wall-clock deadline at ~70% so it finishes outcome writes
cleanly. Skips entirely (cheap cached read) while Wave isn't connected.
Needs composite indexes `(status ASC, nextAttemptAt ASC)` and
`(status ASC, claimedAt ASC)` on `waveSyncQueue`.

### `waveScheduledImport` — `wave/callables.js`
Scheduled Wave → app auto-import, **every 24 hours**, single instance. Reads
`wave/connection` and re-runs `importCustomers` only when the configured
`importSchedule` cadence is due (`isImportDue` in `wave/import_schedule.js`, a
pure jest-testable helper — `off` or any unknown value never runs). Server-
triggered, so no App Check / rate limit. A due run stamps `lastAutoImportAt`; a
failed run leaves it unchanged so the next day retries. 300s timeout.

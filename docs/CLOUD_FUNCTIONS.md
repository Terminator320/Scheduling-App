# Cloud Functions Reference

Map of every Cloud Function in `functions/` — what it does, how it's
triggered, who calls it, and its security posture. Generated 2026-07-05,
refreshed 2026-07-13 by auditing the source against the app's call sites and
the live deployment (Places callables tightened to admin-only + the overdue
sweep given a 300s timeout; both Places proxies and the overdue prompt
redeployed with the rest of the set).
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
- **Deploy:** `firebase deploy --only functions,firestore:rules,storage`
  (run `cd functions && npm run lint` first).

## Deployment status

- **20 functions defined** in code; **all 20 deployed** — verified live against
  `schedulingapp-88727` on 2026-07-13 (v2, Node.js 24, 256 MB; `us-central1`
  except `validateUploadedImage` in `us-east1`).
- The 4 **push-notification functions** (`notifyAppointmentChanges`,
  `sendUpcomingJobReminders`, `sendDailyJobDigest`, `sendOverdueJobPrompts`)
  and the 2 **Wave auto-import cadence functions** (`waveSetImportSchedule`,
  `waveScheduledImport`) were **deployed 2026-07-11** together with the updated
  `firestore.rules`. Still outstanding: the one-time Firestore **TTL policy** on
  `expiresAt` for the `appointmentReminders` / `appointmentOverduePrompts`
  ledgers (console-enabled), plus on-device push verification. The iOS-native
  APNs key + Push/App-Groups entitlements were wired on the Mac 2026-07-11 (see
  `docs/plans/2026-07-08-push-notifications.md`).
- `backfillLegacyClientNames` (a one-time migration completed `2026-06-29`,
  `fixed: 0`) was removed from the codebase 2026-07-05 and is **no longer in the
  deployed set** (confirmed 2026-07-10) — it was pruned by a full
  `firebase deploy --only functions`.

## Summary

| Function | Type | Trigger / event | Module | Called by / fired on | Secret | Guard |
|---|---|---|---|---|---|---|
| `placesAutocomplete` | callable | `onCall` | `places.js` | `google_places_repository.dart` (address field typing) | `GOOGLE_MAP_API_KEY` | App Check ✓ · admin · in-mem 20/min·uid |
| `placesGetDetails` | callable | `onCall` | `places.js` | `google_places_repository.dart` (address selected) | `GOOGLE_MAP_API_KEY` | App Check ✓ · admin · durable 40/15min |
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
| `notifyAppointmentChanges` | trigger | `onDocumentWritten appointments/{id}` | `notifications.js` | any appointment write | — | no `retry` (dupe push worse than missed) |
| `purgeExpiredHistory` | scheduled | `every day 03:00` (Toronto) | `maintenance.js` | nightly | — | `maxInstances: 1` · 540s |
| `waveSyncWorker` | scheduled | `every 5 minutes` | `wave/callables.js` | timer | `WAVE_FULL_ACCESS_TOKEN` | `maxInstances: 1` · 540s |
| `waveScheduledImport` | scheduled | `every 24 hours` | `wave/callables.js` | timer | `WAVE_FULL_ACCESS_TOKEN` | `maxInstances: 1` · 300s |
| `sendUpcomingJobReminders` | scheduled | `every 5 minutes` (Toronto) | `notifications.js` | timer | — | `maxInstances: 1` · ledger |
| `sendDailyJobDigest` | scheduled | `0 18 * * *` (Toronto) | `notifications.js` | timer | — | `maxInstances: 1` |
| `sendOverdueJobPrompts` | scheduled | `every 15 minutes` (Toronto) | `notifications.js` | timer | — | `maxInstances: 1` · 300s · ledger |

## Auth & accounts

### `deleteAccount` — `account.js`
Self-service account deletion (Apple 5.1.1(v) / Google Play account-deletion
policy). Deletes the caller's `users/{docId}` doc via `recursiveDelete` (the
doc **plus all its subcollections** — `fcmTokens` today, `presence` when the
travel-time plan lands) and their Firebase Auth user; the `syncUsersByUid`
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
can't burn slots. Full flow: `docs/plans/INVITED_SIGNUP_REDESIGN.md`.

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

## Images

### `validateUploadedImage` — `maintenance.js`
Storage `onObjectFinalized` trigger. For every upload under
`appointments/{id}/images/`, reads the first 8 bytes and deletes the object
server-side unless it's real JPEG (`FF D8 FF`) or PNG (`89 50 4E 47`) — the
Storage rule trusts client `contentType`, so this closes that gap. Deployed to
`us-east1` (follows the Storage bucket region).

## Maintenance (scheduled)

### `purgeExpiredHistory` — `maintenance.js`
Nightly at 03:00 America/Toronto. Deletes `done`/`cancelled` appointments whose
`startTime` is older than 2 years, **and** their Storage images. Images are
deleted before the Firestore doc so a Storage failure keeps the doc for the next
night's retry rather than orphaning PII bytes. Non-terminal appointments are
never touched. 540s timeout; leftovers carry to the next run.

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
— see Deployment status. Design: `docs/plans/2026-07-08-push-notifications.md`.

### `notifyAppointmentChanges` — `notifications.js`
`appointments/{id}` write trigger → assignment / reschedule / cancel /
unassignment pushes. Diffs before/after (`diffAppointmentForNotifications`):
one event per employee, priority `cancelled > removed > rescheduled >
assigned`; past appointments skipped. Deliberately **no `retry: true`** — a
duplicate push is worse than a rare missed one.

### `sendUpcomingJobReminders` — `notifications.js`
Every 5 min (Toronto). Queries `status in [pending, confirmed]` (legacy alias)
with `startTime` in `(now, now+30min]` on the existing `(status, startTime)`
index, then fires one localized reminder per assignee. Exactly-once **per
recipient** via the Admin-SDK-only
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
daily; a rare crash-retry duplicate is accepted).

### `sendOverdueJobPrompts` — `notifications.js`
Every 15 min (Toronto). The "job finished?" nudge: pushes assignees of a job
whose `endTime` passed within the last 24 h while its status is still open
(`pending`/`in_progress`/legacy `confirmed` — server mirror of the app's
display-only `overdue` state; nothing is ever stored). Queries by `startTime`
over the last **48 h** (24 h eligibility + the <24 h max booking) so no new
index is needed, then filters `endTime ∈ (now-24h, now]` in code. At-most-once
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
reads the rules-locked `wave` collection directly. Details:
`docs/plans/WAVE_INTEGRATION_PLAN.md`.

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

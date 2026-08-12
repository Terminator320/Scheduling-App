# Cloud Functions Reference

Map of every Cloud Function in `functions/` — what it does, how it's
triggered, who calls it, and its security posture. Generated 2026-07-05,
refreshed 2026-08-11 by auditing the source against the app's call sites and
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
  `optionalString`, `requireNumberInRange`, `readSessionToken`,
  `enforceDurableRateLimit`, `assertAdmin`) live in `security.js` — put a new
  one there, never back in a feature module (`optionalString` was a private copy
  in the retired `invites.js` and was carried verbatim into
  `employee_accounts.js` before being hoisted).
- **Deploy:** `firebase deploy --only functions,firestore:rules,firestore:indexes,storage`
  (run `cd functions && npm run lint` first).

## Deployment status

> The authoritative record of what production runs is the **Deploy log** in
> `docs/DEPLOYMENT.md`, plus `functions_list_functions`. This section has been
> wrong before — verify against the live list rather than trusting it.


- **CLEARED 2026-08-11: the 2026-08-08 → 2026-08-11 gap has been deployed.**
  All 25 functions were updated together with `firestore.rules` and
  `storage.rules`, so prod now runs `changeEmployeeEmail`'s non-admin re-auth
  gate and its 20/hr → 5/hr budget, the travel-alert opt-out skipping the
  Routes call, the multi-day Live Activity skip and the crew-colour parse in
  `travel_utils.js`, the shared `day_slice_utils.js` day-scoping behind the
  widget payload and push text, the one `TERMINAL_STATUSES` owner in
  `time_utils.js`, plus the P5 self-service rules clause and
  `isValidAppointmentSpan`. Note the trap this gap illustrates: the function
  *count* never moved (25 throughout, `index.js` untouched), so a count check
  looked clean for three days while prod ran older bodies — check the deploy
  log, not the count.
- **25 functions defined** in code and **25 deployed**, verified against
  `functions_list_functions` on 2026-08-08 — an exact match, no orphans and no
  extras. The retirement deploy has now RUN. P4c added `createEmployeeAccount`,
  `completeEmployeeSetup` and `deleteEmployeeAccount` and kept
  `createEmployeeInvite` / `redeemSignupCode` as the `#compat-1.37.1` shim;
  `changeEmployeeEmail` landed 2026-08-04 (26 → 27); **the shim was retired
  2026-08-08 (27 → 25)** once every device was on 1.40+, deleting those two
  callables. `revokeInvite` and `previewInvite` DID exist in code — P4b added
  them (`461f84ba`) and P4c removed them (`ea375b1b`) — but they were never
  deployed to prod. (v2, Node.js 24, 256 MB; `us-central1`
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
  2026-07-20. **The `signupCodes` `fieldOverride` was removed from
  `firestore.indexes.json` on 2026-08-08** with the rest of the
  `#compat-1.37.1` shim, so the next `firestore:indexes` deploy DROPS that live
  TTL policy — which is intended here, and only safe because the collection was
  verified **empty in prod** first (a TTL policy is the only reaper for those
  docs; dropping it over a non-empty collection strands them forever). A
  `fieldOverride` for the `appointmentSeriesNotices` claim
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
- **Pending deploy (1.38.0, 2026-07-31):** personal jobs and all-day blocks
  change three functions' *behaviour* with no signature, trigger, guard or
  secret change, so the export set stays at 21. `sendUpcomingJobReminders` —
  `selectTravelCandidates` skips `isAllDay` records (a midnight start otherwise
  fell inside the 90-min window at ~23:30 the night before and pushed a "time
  to leave" for a block with nowhere to leave for); `sendOverdueJobPrompts` —
  `selectOverdueCandidates` skips `isPersonal` records, the server mirror of
  `AppointmentRecord.displayStatus`; and every push, digest and Live Activity
  card now names a job `clientName → title → generic`, since a personal job has
  no client. Nothing here needs a new index.
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
| `createEmployeeAccount` | callable | `onCall` | `employee_accounts.js` | `firebase_employees_repository.dart` (invite sheet, roster row Reset password) | — | App Check ✓ · admin · durable 20/hr·uid |
| `completeEmployeeSetup` | callable | `onCall` | `employee_accounts.js` | `firebase_employees_repository.dart` → `auth_service.dart` (account setup screen) | — | App Check ✓ · authed (own doc) · `email_verified` ✓ · durable 5/15min·uid |
| `deleteEmployeeAccount` | callable | `onCall` | `employee_accounts.js` | `firebase_employees_repository.dart` (pending-account row) | — | App Check ✓ · admin · durable 20/hr·uid |
| `changeEmployeeEmail` | callable | `onCall` | `employee_accounts.js` | `firebase_employees_repository.dart` (inside `updateEmployee`, when the email changed on a doc with a `uid`); `self_email_service.dart` (a person changing their own) | — | App Check ✓ · admin **or self** · non-admin also needs re-auth <5 min · durable 5/hr·uid |
| `waveBootstrap` | callable | `onCall` | `wave/callables.js` | `wave_service.dart` | `WAVE_FULL_ACCESS_TOKEN`, `WAVE_BUSINESS_NAME` | App Check ✓ · admin · durable 10/hr |
| `waveGetConnection` | callable | `onCall` | `wave/callables.js` | `wave_service.dart` (Settings mount) | — | App Check ✓ · admin |
| `waveSetImportSchedule` | callable | `onCall` | `wave/callables.js` | `wave_service.dart` (Settings cadence picker) | — | App Check ✓ · admin · durable 20/hr |
| `waveImportCustomers` | callable | `onCall` | `wave/callables.js` | `wave_service.dart` (`syncCustomers`, Settings "Sync with Wave") | `WAVE_FULL_ACCESS_TOKEN` | App Check ✓ · admin · durable 5/hr · 300s |
| `deleteClient` | callable | `onCall` | `clients.js` | `firebase_clients_repository.dart` | — | App Check ✓ · admin · durable 20/hr |
| `syncUsersByUid` | trigger | `onDocumentWritten users/{id}` | `bridge.js` | any `users` doc write | — | `retry: true` |
| `propagateClientEdits` | trigger | `onDocumentUpdated clients/{id}` | `client_propagation.js` | any `clients` doc edit | — | `retry: true` |
| `recountClientJobs` | trigger | `onDocumentWritten appointments/{id}` | `client_job_count.js` | a write that changes `clientId` | — | `retry: true` |
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

## Employee accounts (admin invites, employee sets up)

Rebuilt by **P4c, 2026-08-02**, replacing the one-time signup-code flow in the
APP — and as of **2026-08-08 the signup-code flow is gone from the backend too**:
`invites.js`, `signup_code_utils.js`, `createEmployeeInvite` and
`redeemSignupCode` were deleted with the rest of the `#compat-1.37.1` shim.
`revokeInvite` and `previewInvite` were never deployed, but they DID exist in
code between P4b (`461f84ba`) and P4c (`ea375b1b`).
**`redeemSignupCode` was the last unauthenticated callable in the
codebase**; every remaining one requires auth. All four callables
below share `APP_CHECK = {enforceAppCheck: true}`. Full design:
`docs/plans/redesign-subdocs/2026-08-02-p4c-HANDOFF.md`.

The shape: the admin creates the account and hands over an email + shared
starting password; the employee signs in, replaces the password, and activates
themselves. **The security posture is weaker than the codes it replaced, with
the owner's sign-off** — `Welcome123!` is known to everyone, so between creation
and first sign-in anyone who knows the email can sign in as that person and
complete setup. What holds instead is that `firestore.rules` grants an `invited`
user **nothing**, so the window is "can reach the setup screen as this person",
not "can read the business" — and that the admin controls the window by creating
the account when they hand the credentials over. That mitigation is operational,
not technical.

### `createEmployeeAccount` — `employee_accounts.js`
Admin-only. Mints a Firebase Auth account on the shared `DEFAULT_PASSWORD` plus
an `invited` `users` doc that **already carries the real `uid`**, and returns
`{email, password}` so the admin surface shows exactly what the server set
rather than a constant it hopes still matches (no `docId` — the client already
has the row it acted on). The duplicate lookup and the doc write share one
transaction, so two admins creating the same person can't both win.

Re-running it on a still-`invited` person **re-provisions**: it refreshes the
doc's editable fields and resets the password back to the default — that IS the
"never signed in / lost the password" path. It refuses `already-exists /
email-exists` once the person has finished setup, resolving the target **by
`uid`, not by email** (`users.email` is admin-editable and never synced back to
Auth, so an email-only check can clear a doc that is not the account Auth hands
back). The rotation itself is deferred to `resetProvisionedPassword`, which runs
only after the transaction has claimed the person as still-`invited` — that
**narrows** the window in which a concurrent setup gets its chosen password
reverted, but cannot close it, since the Auth call sits outside both
transactions.

If the Firestore write fails after the Auth account was created, the Auth
account is deleted — but only if *we* just minted it. **A rollback that itself
fails is `logger.error`-ed with the uid**, because the resulting Auth-account-
with-no-doc is invisible to every admin surface *and* permanently bricks that
email (the pre-flight refuses an Auth account no doc claims), so it can only be
cleared from the Firebase console.

Durable-rate-limited 20/hr per admin uid; the payload is validated
(`assertPayloadShape`/`requireString`, plus explicit `colorValue` and `jobTitle`
allowlists — this Admin SDK write bypasses rules, so those checks ARE the
enforcement) **before** the limiter, while `assertAdmin` stays above it.
Transactional core exported as `performCreateAccount` for jest.

### `completeEmployeeSetup` — `employee_accounts.js`
The employee's own activation — authed, but **not** admin: it resolves the
caller's doc by `where("uid", "==", req.auth.uid)` and can only ever touch that
one. Flips `status` to `active` and stamps the setup profile. Refuses
`failed-precondition / setup-not-pending` when the doc isn't `invited`, so a
replayed call (or two devices finishing at once) can't rewrite a consent record;
`not-found / account-not-found` when there's no doc for the uid.

**It refuses an unverified address** — `failed-precondition / email-not-verified`
unless `req.auth.token.email_verified` is true. That is what prices the shared
`Welcome123!` window: anyone who knows an employee's email can sign in as them
and reach the setup screen, but leaving `invited` now needs control of the
MAILBOX, and `firestore.rules` grants an `invited` user nothing. It is an
IDENTITY guard, so it sits **above** the rate limiter — an unverified caller
must not be able to burn the real employee's five slots. The client half is
`AuthService.refreshEmailVerified()`, which forces `getIdToken(true)`: the claim
is read off the token minted at sign-in, so a bare `reload()` leaves the server
refusing an address the person has already verified.

**The caller must have already changed the password.** The server cannot see a
password, so "you must replace the shared default" is true only because
`AuthService.completeAccountSetup` calls `User.updatePassword` first and this
callable is unreachable until that succeeds. Swap the order and an interrupted
setup leaves an *active* account still on the default.

The patch is built by the pure `buildActivationPatch`: it stamps
`termsAcceptedAt`/`locationConsentAt` **only when the flags are actually sent
`true`** (a consent record for someone who never saw the checkbox would be a
false one), and never writes an empty `name` — it composes from the submitted
halves falling back per-half to the stored ones, because `watchAllUsers` orders
by `name` and Firestore excludes docs missing the orderBy field. Rate-limited
5 per 15 min per uid: setup runs once per person, and a handful of retries
covers a fumbled password.

### `deleteEmployeeAccount` — `employee_accounts.js`
Admin-only. Removes an account that has never been set up — the `users` doc and
the Firebase Auth account both. **Transactional, and refuses once the person has
set up** (`failed-precondition / account-not-pending`): from that point the
account is theirs and the no-delete invariant applies, so disable is the only
removal. A setup that commits first therefore makes this refuse rather than
delete a just-activated account; a missing doc is `not-found /
account-not-found`.

Doc first, Auth second. `auth/user-not-found` is swallowed so a partial earlier
run converges, but **any other Auth failure is logged with the uid and then
rethrown**: the doc is already gone at that point, so it leaves an Auth account
no admin surface can see and whose email `createEmployeeAccount` will then
refuse — recoverable only from the Firebase console, which is why the log is
the difference between a findable leftover and a silent one. Guard
order is the standard one (auth → `assertAdmin` → payload →
`enforceDurableRateLimit` 20/hr per admin uid → work), and an id containing `/`
is rejected up front because `.doc()` throws synchronously on it and would
surface as an opaque `internal`. No rules change: the deletes are Admin SDK.
Note `allow delete` on `/users` is withdrawn from this build's code path AND
from `firestore.rules` — the `#compat-1.37.1` grant that kept a 1.37.1 client
able to delete a users doc (orphaning its crew links) was retired 2026-08-08;
see docs/DEPLOYMENT.md. Transactional core exported as `performDeleteAccount`
for jest.

### `changeEmployeeEmail` — `employee_accounts.js`
Admin **or the person themselves** (the `self` branch landed with P5,
2026-08-10). Moves an employee's **sign-in identity** in Firebase Auth and on
their `users` doc together. It exists because nothing else joined those two:
`updateEmployee` writes Firestore alone, so an admin's email edit left the
person signing in at the old address while every admin surface showed the new
one — and it desynced the two stores `createEmployeeAccount` resolves against.
Added 2026-08-04; it is what re-enabled the email field in `edit_person_sheet`.

Refuses `failed-precondition / account-has-no-auth` for a doc carrying no `uid`
— there is nothing to join, and that doc's email is written directly by the
client under the rules. An email equal to the stored one is a no-op `{ok:true}`.

**Order is Auth FIRST, Firestore second, with a revert.** Auth owns sign-in and
is the only store that can genuinely refuse a duplicate, so it must never be
the one left behind; a `auth/email-already-exists` becomes `already-exists /
email-exists`. If the doc write then fails, the Auth email is set back and a
**failed revert is `logger.error`-ed with the uid and docId — never the
addresses, which are PII**: that state is the exact desync this function
prevents and nothing in-app can find it.

A cheap doc-level uniqueness pre-flight runs before Auth so the common conflict
costs no Auth write plus rollback; `performChangeEmail`'s transaction is the
authoritative check and re-tests **both** halves — that the doc still holds the
email we read (`aborted / email-changed` otherwise, which the client surfaces as
"try again") and that no other doc holds the new one. Guard order is the
standard one (auth → payload → identity → freshness → `enforceDurableRateLimit`
**5/hr** per caller uid → work), with the same `/`-in-docId rejection as the
delete. The payload is validated before a slot is consumed so a burst of
malformed submissions can't exhaust a legitimate caller's window, and the
identity guard sits above the limiter so a non-entitled caller can't burn one
either. The budget is the same on both branches — this rewrites a sign-in
identity, so a compromised session must not be able to walk the roster.

**A NON-ADMIN caller additionally requires a fresh re-auth** —
`assertFreshReauth` (`security.js`, shared with `deleteAccount`) rejects a
caller whose `auth_time` is over **5 minutes** old, so a direct call cannot skip
`SelfEmailService`'s re-authenticate-then-call ordering. **The gate keys on
`isAdmin`, not on `isSelf`**, and the two are separate fields on
`resolveEmailChangeCaller`'s result for exactly this reason: an admin editing
their OWN roster row is `isSelf` but still arrives through `updateEmployee`,
which has no re-auth step — keyed on self-ness, that save was rejected whole
(name, phone, colour and availability with it, since `_changeAuthEmail` runs
before the Firestore write) as an opaque `stale-auth`. `isSelf` routes the
notification and nothing else. The **admin branch is deliberately not gated**,
so that residue is real and stated — an unattended admin session can still
rewrite a colleague's address, bounded by the identity guard and the budget
above; closing it needs a re-auth prompt on the admin save path first.

**The identity guard is `resolveEmailChangeCaller`, not `assertAdmin`** — it has
to tell an admin from a person editing their own row. Pure over the caller's
`usersByUid` bridge data, so it is jest-tested without Firestore. An **active
admin** may move any doc; an **active employee** may move their OWN; everything
else is refused `permission-denied / not-admin` — a disabled account (whose Auth
credential outlives the status flip until `syncUsersByUid` revokes it), an
invited account mid-setup, an unknown role, a missing bridge doc, or an employee
naming somebody else's docId. Widening this callable past admins must never
widen WHICH doc a caller can reach.

**Who gets notified depends on who acted.** `isSelf` reports whether the caller
IS the target, independent of role, so an admin editing their own row counts as
self. An admin edit pushes the EMPLOYEE (`notifyEmailChanged`); a self edit
pushes the ACTIVE ADMINS (`notifyAdminsOfSelfEmailChange` → the shared
`sendToActiveAdmins` in `notification_utils.js`, excluding the person who made
the change). **The admin notice carries the NAME, never the address** — it lands
on every admin's Lock Screen and an email is PII. Both are best-effort and run
after the commit: the change is already durable in both stores, so a push
failure must not hand the caller an error for something that worked.
Transactional core exported as `performChangeEmail` for jest.

On success it pushes the employee a `kind: "emailChanged"` notification naming
the new address, via `notifyEmailChanged` → the shared `sendToEmployee` (now
exported from `notification_utils.js`, so the token fetch, the role + active
gate and stale-token pruning keep one owner). It runs **after** the commit and
swallows every failure — the change is already durable in both stores, so a
push problem must not surface as a failed save. Recipients use
`TIMED_RECIPIENT_ROLES` so an admin whose own email is being changed is told
too. Tapping it just opens the calendar (`_handlePushTap` treats a missing
`appointmentId` as "no appointment to open"), and **it is a courtesy, not a
guarantee**: an employee with no live FCM token learns when their old address
stops signing them in, so the admin should still tell them directly.

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
**Its orchestration lives in `maintenance_policy.js`** (extracted 2026-08-04),
taking `db`/`deleteImages`/`now` injected: `maintenance.js` resolves a Storage
bucket at load and throws on `require()` outside the emulator, so the only
unattended irreversible deletion in the codebase had **no test at all** until
that split. `functions/__tests__/maintenance_policy.test.js` now pins the three
rules that destroy data if they regress — the status gate (live work is never
purged at any age), the images-before-doc ordering, and the loop's termination
on a page that made no progress.

## Push notifications (FCM)

All four live in `notifications.js` (thin trigger registrations); the logic —
diff/message/candidate helpers plus the injectable orchestration — is in
`notification_utils.js` (no admin/scheduler requires, so jest drives it with
mocked `{db, messaging, now, logger}`). Recipients are always filtered
server-side to `role == 'employee' && status == 'active'`; tokens live in
`users/{docId}/fcmTokens/{token}` (doc id = token, keyed by users **doc id**
so the send path needs no uid translation), and stale tokens are deleted on
send failure. Text is localized per token doc (`locale: 'en'|'fr'`) from an
inline EN/FR table; every message sets an APNs `sound` so delivery isn't
silent, plus a now-inert `android: {priority: 'high'}` (kept because it costs
nothing and FCM ignores it for an APNs-only fleet — the app has been iOS-only
since `android/` was deleted on 2026-08-05). **Deployed 2026-07-11**
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
in EN/FR (`live_activity_utils.js`). The marker also stores the sweep's
`leadMinutes`/`travelMinutes`, because only the sweep ever has a Routes
estimate: a later reschedule rebuilds `leaveAt` from the new start minus that
lead (`_withLeaveAt`), and with no recorded lead the card renders "Starts at"
rather than labelling the job's own start time as the departure time.

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
`(status, startTime)` index. **`selectTravelCandidates` skips `isAllDay`
records** — an all-day block stores a real midnight start, so it entered the
90-min window at ~23:30 the night before and fired a "time to leave" push for
something with no departure time. A *timed* personal job still gets its
reminder; only the all-day case is excluded (mirrors the `isPersonal` skip in
`selectOverdueCandidates`). Per (job, assignee) it picks a departure origin —
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
filter excludes only `cancelled`; the query and filter now agree. **Each
employee's send is wrapped individually** — the sends run through one
`Promise.all`, so before that a single transient token read rejected the whole
map and cost every *other* employee tomorrow's schedule.

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
can't abort the sweep. **That isolation now covers building the ledger ref
itself**, which is composed from the employee doc id: a `/` in an `employeeIds`
element makes an invalid document path, and constructing it outside the `try`
threw before any per-recipient handler could catch — one malformed id
permanently killed every overdue prompt for the whole fleet. The scheduler body
is also wrapped and logged like its two siblings, so a sweep that dies is
visible instead of silent. Candidates are processed serially, so it carries a **300s
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

### `recountClientJobs` — `client_job_count.js`
`appointments/{id}` write trigger that maintains the denormalized `jobCount` on
the client doc. Recomputes with a `count()` aggregate and writes the value
**absolutely** — never `FieldValue.increment`, because `retry: true` means a
retried event would double-count. Fires only when `clientId` actually changes
(create, delete, reassignment), so an ordinary title or time edit costs zero
reads; personal jobs carry no `clientId` and are skipped. Writes with `update()`
rather than `set({merge: true})` so a client removed out-of-band is never
resurrected as a count-only stub, and swallows Firestore `NOT_FOUND` for the same
case. The pure `clientsToRecount(before, after)` is exported for jest. Served by
the automatic single-field index on `clientId` — no composite index needed.
**Deployed 2026-08-01** (`d916b16`).

### `deleteClient` — `clients.js`
Admin-only callable, the **only** delete path for a client in this build.
`allow delete` on `/clients` is withdrawn from this build's code path AND from
`firestore.rules` — the `#compat-1.37.1` grant (kept for 1.37.1's ungated
Delete button) was retired 2026-08-08, closing the orphaning hole; see
docs/DEPLOYMENT.md. The callable exists because rules cannot express
"only when this client has
no appointments" — there is no cheap way to count a foreign collection there.
Refuses with `failed-precondition / client-has-history` when a **live `count()`
aggregate** over `appointments where clientId == …` returns non-zero, and with
`not-found` when the doc is already gone. The count is deliberately NOT the
denormalized `jobCount`: that field is lazily backfilled by `recountClientJobs`,
so it can be stale, missing, or wrong on a client whose appointments were
reassigned out-of-band — deleting on a stale zero is exactly the orphaned-history
bug this gate exists to prevent. Guard order is auth → `assertAdmin` →
`assertPayloadShape`/`requireString` (plus a `/`-in-id reject, since `.doc()`
throws synchronously on one) → `enforceDurableRateLimit` (20/hr per admin uid) →
work. The pure `performDeleteClient(db, clientId)` is exported for jest.
Archive — not delete — is the normal way a client leaves the roster.
**Deployed 2026-08-03** (`1c6a949`), verified ACTIVE.

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
connection. No secret. **Durably rate-limited at 20/hour per admin uid** (added
2026-08-04) — every other admin write callable is, and the audit flagged this as
the lone exception. The limiter sits AFTER the payload validation so a burst of
malformed submissions can't exhaust a legitimate caller's window.

### `waveImportCustomers` — `wave/callables.js`
Admin **two-way** sync behind Settings › "Sync with Wave" (2026-08-04). The
callable keeps its original, now-inaccurate name because renaming a deployed
callable deletes the one **every** shipped build calls — a constraint that
outlived the `#compat-1.37.1` shim it was first tagged with, and that any
future rename still has to solve (deploy both names, then drop the old one
once no build calls it).

**Push, then pull, in that order.** `drainForSync` first drains pending
`waveSyncQueue` jobs to Wave, then `importCustomers` pulls Wave customers back
(paginates ~650 customers over ~7 Wave pages). The order is the correctness
rule: the outbox holds edits the app already accepted, so importing first would
overwrite them with the Wave rows they are on their way to replace.

**Ordering is not sufficient on its own.** The import overwrites every mapped
field of a linked client with Wave's values *and* stamps `wave.lastSyncedHash`
from them, so a client edit still in the outbox is not just overwritten — it is
marked synced, and the pending job then hashes the clobbered doc, matches, and
no-ops. The drain is bounded and its query only takes jobs already due, so a job
backed off after a transient Wave error survives it. Both this callable and
`waveScheduledImport` therefore pass `importCustomers` a `skipClientIds` set
from `listOutstandingClientIds` (`wave/worker.js`, covering `queued` and
`inflight`); skipped clients are counted as `skippedPending`.

The push half is **best-effort and bounded** — `SYNC_PUSH_BATCH_LIMIT` (20) and
`SYNC_PUSH_BUDGET_MS` (20 s), with `waveSyncWorker` mopping up the rest every 5
minutes — so a drain failure is logged and swallowed rather than failing the
import the admin actually pressed the button for. Both bounds are sized against
the *client's* deadline (`kWaveSyncTimeoutSeconds`, 120 s, in
`wave_service.dart`), not the 300 s function timeout: a callable can't be
cancelled, so past that deadline the admin has already been told the sync failed
and will tap again.

Response adds `pushedCreated` / `pushedUpdated` / `pushedPending` /
`pushedFailed` / `pushIncomplete` to the existing import summary — **additive
only**, since 1.37.1 parses the import half by name and ignores the rest. The
last three exist because a bounded push, a dead-lettered job and a thrown drain
all leave the counts at zero, which the app would otherwise render as "already
up to date": `pushedPending` is a `count()` of still-queued jobs taken AFTER the
drain, `pushedFailed` is `drained.dead` (dead-lettered jobs aren't `queued`, so
the pending count misses them and they never retry), and `pushIncomplete` flags
a drain or count that threw. The two success counts come from `drainQueue`'s
`created`/`updated`, which `tallyUpsert` (`wave/worker.js`) folds from each
`upsertCustomer` status; `linked` counts as an update, not a create, because
that path patches a customer a crashed earlier attempt had already created.

**The import is hash-gated.** A linked client whose stored
`wave.lastSyncedHash` already equals `mappedFieldsHash(fromWaveCustomer(node))`
is skipped (`skippedUnchanged`), so `updated` counts only real changes. The
equality is exact — both sides hash the same `toWaveCustomerInput` projection,
the identity `shouldEnqueueClientWrite`'s Rule 2 already relies on. Before the
gate, every run re-wrote all ~650 clients: ~650 writes plus ~650
`waveUpsertCustomer` invocations that each concluded "nothing to do", and the
app's notice read "650 clients updated in the app" after a sync that changed
nothing. The `hasCreatedAt` half of the condition is load-bearing — the update
branch is the only `createdAt` backfill, and the clients list orders by it.

Writes `createdAt`/`updatedAt` on every client doc it does write (the
list/search order by `createdAt`, and Firestore excludes docs missing the
orderBy field). Rate-limited 5/hr; 300s timeout.

**Delta import (2026-08-04).** Introspection against the live API
(`functions/scripts/wave-introspect-customer-sort.js`) established that
`business.customers` accepts `modifiedAtAfter: DateTime` /
`modifiedAtBefore`, and that `CustomerSort` offers `MODIFIED_AT_ASC/DESC`
alongside `CREATED_AT_*` and `NAME_*`. The filter is the better lever than the
sort — it runs server-side, so Wave returns only what changed instead of us
paging everything and stopping early.

`importCustomers` therefore takes an optional `since` (ISO-8601). Present → the
`LIST_CUSTOMERS_SINCE` document; absent → the full `LIST_CUSTOMERS`. These are
**two separate documents on purpose**: omitting a variable to make an argument
"not present" is valid GraphQL, but relying on that against a third-party
server risks it being read as `modifiedAtAfter: null` — a full import that
imports nothing and reports success. Both must keep passing strings as
variables; Wave refuses inline `String` arguments (see `functions/CLAUDE.md`).

The watermark lives on `wave/connection` (`customerDeltaSince`,
`lastFullImportAt`) and `importCustomers` stays stateless about it. The whole
read → decide → import → advance sequence has **one owner**,
`importWithWatermark` in `wave/callables.js`, used by both the interactive sync
and `waveScheduledImport`; the decisions are the pure `resolveImportWindow` /
`watermarkPatch` in `wave/import_schedule.js`, placed beside `isImportDue`
because the two cadences interact.

- **The watermark is the run's START minus `DELTA_OVERLAP_MS` (5 min).** From
  the end, it would drop anything edited mid-run; without the overlap, anything
  edited in the same second the query went out, and no slack for clock skew
  against Wave.
- **It advances only over a window that was fully covered.** A throw leaves
  both stamps (the next run redoes an idempotent window). So does a run that
  reported `skippedPending > 0`: those clients were deliberately protected from
  the clobber and therefore not imported, so advancing would hide any Wave-side
  change to them until the next full pass. An *unknown* `skippedPending` is
  treated as not-covered for the same reason — holding is free, advancing
  wrongly loses data.
- **A delta-only failure retries once as a full import.** Otherwise a bad
  `modifiedAtAfter` is sticky: the watermark stays put, every interactive sync
  rebuilds the same failing query, and nothing self-heals until the 7-day
  resync ages the window out — while the scheduled path keeps working, so the
  breakage is admin-facing only.
- **A failed watermark WRITE is logged, not thrown.** The import already
  committed; failing there would report a successful sync as an error and throw
  away the push counts the notice exists to surface.
- **A full pass is forced every `FULL_RESYNC_INTERVAL_MS` (7 days).** Not for
  deletes — the import has never deleted a local client and still doesn't, so a
  customer removed in Wave keeps its doc either way. It is a backstop for
  `modifiedAt` itself: we are trusting Wave to bump it for every field we map
  and cannot verify that. Note this interval is shorter than both import
  cadences, so a scheduled run whose last full pass was a cadence ago goes full
  — in practice the delta mostly benefits the interactive sync, which is
  accepted.
- **A watermark ahead of now is refused**, not honoured — otherwise a clock or
  data fault makes every subsequent run import nothing, forever.

`buildWaveIdIndex` is now built **lazily**, so a delta run that finds nothing
changed costs one Wave call and zero Firestore reads instead of ~650 document
reads to resolve nothing. When a delta does have work, it still reads the whole
`clients` collection — a targeted `whereIn` lookup over just the changed wave
ids would avoid that, and is the remaining optimisation here.

**`totalCount` on a delta summary is the size of the queried set** — the number
of changed customers, not the roster size. Don't render it as "you have N
clients".

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

It passes the same `skipClientIds` protect-list as `waveImportCustomers` (see
that entry) — and needs it more, since it runs unattended: a client edit this
overwrote before the guard existed was lost with nobody watching. It does not
push first; `waveSyncWorker` owns that half.

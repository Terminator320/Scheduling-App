# Cloud Functions (functions/)

Loaded when working under `functions/`. Root context: `../CLAUDE.md`.

Functions live in `functions/` (project `schedulingapp-88727`, region
`us-central1`). `index.js` is now a thin wiring surface that re-exports all 25
functions under their original names — the implementations are split into
domain modules: `security.js` (shared callable guards — `assertPayloadShape`,
`requireString`, `optionalString` (same trim/length/control-char checks but
allows absent-or-empty; it lived as a private copy in `invites.js` and was
carried verbatim into `employee_accounts.js`, which is why it now sits here),
`requireNumberInRange` (finite number in `[min,max]`; rejects
`NaN`/`Infinity`), **`requireDocId`** (a required id ≤128 chars carrying no
`/` — the callable-side owner of `isValidDocIdField` in `firestore.rules`,
which was restated at three call sites, two byte-identical down to the
comment; the slash half is load-bearing, since `.doc()` throws SYNCHRONOUSLY
on one and would reach the caller as an opaque `internal`. It throws
`invalid-<key>`, so each call site keeps its own error code.
`notification_policy.js`'s `toIdList` deliberately does NOT use it — that one
FILTERS a list rather than throwing, and the policy module must stay free of
firebase-functions/admin),
`readSessionToken`, `enforceDurableRateLimit`, `assertAdmin`, `hasControlChar`,
`isReauthStale` and **`assertFreshReauth`** — the last being the guard
`.claude/rules/security.md` holds up as *the shape to copy* for failing closed
on missing input, and all three were missing from this list),
`bridge.js` (`syncUsersByUid`), `client_propagation.js`
(`propagateClientEdits`), `client_job_count.js` (`recountClientJobs`, backed by
the pure `clientsToRecount`), `clients.js` (`deleteClient` — admin-only, the
ONLY client-delete path now that `allow delete` on `/clients` is withdrawn;
refuses `client-has-history` on a **live `count()` aggregate**, deliberately not
the lazily-backfilled `jobCount`, since deleting on a stale zero orphans the
visits this gate exists to protect; pure `performDeleteClient` exported for
jest), `places.js`, `account.js`,
`employee_accounts.js` (the whole employee-account lifecycle, P4c 2026-08-02 —
`createEmployeeAccount` (admin-only: mints the Firebase Auth account on the
shared `DEFAULT_PASSWORD` and the `invited` `users` doc carrying its real
`uid`, rolls the Auth account back if the Firestore write fails, and refuses
`email-exists` for an email that has already finished setup. **That refusal
resolves the target by `uid`, not by email** — `users.email` is admin-editable
and any doc edited before `changeEmployeeEmail` existed can still disagree with
Auth (nothing back-fills those), so an email-only check could clear one doc
while `provisionAuthAccount` reset a different person's account. **And the
rotation itself is deferred:** `provisionAuthAccount` only RESOLVES the uid for
an existing account; `resetProvisionedPassword` runs after
`performCreateAccount`'s transaction has claimed the person as still-`invited`
— which NARROWS the window in which a setup committing mid-call has its chosen
password reverted, but does not close it: the Auth call is outside both
transactions, so a `completeEmployeeSetup` landing between the commit and the
rotation still leaves an `active` employee on the shared default. Auth is not
transactional; don't record this as fixed.
The transaction additionally refuses when the uid already belongs to another
doc — without that, a second doc carrying a live employee's uid made
`syncUsersByUid` delete their `usersByUid` bridge and locked them out.
**Both orphan paths must LOG, loudly.** An Auth account with no `users` doc is
invisible to every admin surface AND permanently bricks that email, because
the pre-flight refuses an Auth account whose uid no doc claims — so it is
unrecoverable in-app and needs the Firebase console. It arises two ways: the
create's own rollback `deleteUser` failing, and `deleteEmployeeAccount`
deleting the doc and then failing on Auth. Both now `logger.error` the uid;
never restore a bare `.catch(() => {})` on either),
`completeEmployeeSetup` (the person's own activation: transactional, refuses
`setup-not-pending` on a replay, and stamps the consent timestamps only when
the flags are actually `true`), `deleteEmployeeAccount` (admin-only, and
only while `invited` — doc first, Auth second, so a partial run converges)
and `changeEmployeeEmail` (admin **or self** — the `self` branch landed with P5
on 2026-08-10; the ONLY thing that joins
the two stores on an email edit, and the reason
`edit_person_sheet.dart`'s email field is editable again. **Auth FIRST,
Firestore second, with a revert**: Auth owns sign-in and is the only store that
can truly refuse a duplicate, so it must never be the one left behind; if
`performChangeEmail`'s transaction then fails, the Auth email is put back and a
failed revert `logger.error`s the uid + docId — **never the addresses, which
are PII**. The transaction re-checks both the previous email and uniqueness,
raising `email-changed` on a concurrent edit. Refuses
`account-has-no-auth` for a doc with no `uid`: nothing to join there, and the
client writes that email directly under the rules.
**The identity guard is the pure `resolveEmailChangeCaller`, not
`assertAdmin`** — it has to tell an admin from a person editing their own row.
An active admin may move any doc, an active employee may move their OWN, and
nothing else gets through: disabled (whose Auth credential outlives the status
flip), invited, unknown role, missing bridge doc, or an employee naming another
docId. **Widening this callable past admins must never widen WHICH doc a caller
can reach** — that function exists to make the mistake hard to write. Guard
order is FIVE, not four: auth → payload → identity → **`assertFreshReauth`**
→ rate limit → work (`employee_accounts.js:509-511` spells it out in its own
comment). The re-auth step sits between identity and the limiter and is keyed on
ROLE, not on `isSelf`: a valid ID token alone must not let an EMPLOYEE move
their own sign-in address, while every ADMIN call arrives through `updateEmployee`,
which has no re-auth step to satisfy it — gating on self-ness rejected an admin
editing their own roster row as an opaque `stale-auth`.
**Who is notified depends on who acted**, and `isSelf` reports whether the
caller IS the target independent of role, so an admin editing their own row is a
self change. A self edit pushes the ACTIVE ADMINS instead
(`notifyAdminsOfSelfEmailChange` → **`sendToActiveAdmins`**, the shared fan-out
beside `sendToEmployee` that P6's time-off requests will reuse — build a new
admin fan-out on it rather than inlining the role/status query. It is bounded
by `ADMIN_FANOUT_MAX` (100) with the warn-at-cap posture the sweep ceilings
use — it was the last unbounded collection query in the push stack — and it
seeds `sendToEmployee`'s recipient `cache` from the docs it just read, so
`_loadRecipient` no longer re-`get()`s a users doc already in hand). It carries the
NAME, never the address: it reaches every admin's Lock Screen and an email is
PII. An admin edit instead
**pushes the person a `kind:"emailChanged"` notice naming the new
address** (`notifyEmailChanged` → the shared `sendToEmployee`, now exported
from `notification_utils.js` — never re-derive the token fetch, the role/active
gate or stale-token pruning). It runs AFTER the commit and swallows everything:
the change is already durable in both stores, so a push failure must not hand
the admin an error for something that worked. Roles are `TIMED_RECIPIENT_ROLES`,
not the change set — the change set is employees-only because an admin normally
makes those edits themselves, and here the admin is a *different* person from
the one whose sign-in is moving. It is a courtesy, **not** a guarantee: no live
FCM token means no notice, so the admin still has to tell them).
Pure helpers `performCreateAccount`, `performDeleteAccount`,
`performChangeEmail` and
`buildActivationPatch` are exported for unit tests; the last one owns the
never-empty-`name` contract that keeps a person inside `watchAllUsers`'
`orderBy('name')`. **The whole one-time signup-code flow is GONE** — P4c
replaced it in the app 2026-08-02, and the backend half it left behind as the
`#compat-1.37.1` shim was deleted 2026-08-08 once every device was on 1.40+:
`revokeInvite` and `previewInvite` (never deployed), then `invites.js`,
`signup_code_utils.js`, `createEmployeeInvite` and `redeemSignupCode`, together
with the `/signupCodes` rules block and its `firestore.indexes.json` TTL entry,
the fourth `/users` read clause and the `allow delete` grants on `/users` and
`/clients`. **There is no longer any unauthenticated callable** — that was
`redeemSignupCode`, and it was the last one. Don't reintroduce a code-based
invite; the shipping flow is admin-creates-account →
employee-completes-setup),
`maintenance.js`
(image validation + history purge; the pure JPEG/PNG magic-byte check lives in
`image_magic.js`), `notifications.js` (FCM push triggers, backed by
`notification_utils.js` and — for the travel-time reminder sweep —
`travel_utils.js`. **The pure decisions behind push live one level down in
`notification_policy.js`** (2026-08-02): the clock/data rules
(`diffAppointmentForNotifications`, `selectOverdueCandidates`,
`groupTomorrowsJobsByEmployee`, `tomorrowWindowToronto`, `ledgerBody`,
`overduePromptLedgerId`, `recordOf`, `contextFor`, the kind-priority and
recipient-role tables) with **no `deps`, no db, no messaging**. That is the
boundary: a helper that needs `deps` stays in `notification_utils.js`.
`notification_utils.js` **re-exports every one of them under its original
name**, so `notifications.js` and the existing jest tests are unchanged — add
new pure rules to the policy module and re-export, rather than growing the
orchestration file back), the Live Activity stack (`apns_client.js`,
`live_activity_utils.js`, `live_activity_registry.js`,
`live_activity_dispatch.js` — see the Live Activities bullet below), and
the Wave stack — `wave/callables.js` (the admin callables only),
`wave/triggers.js` (`waveUpsertCustomer` + the `runWaveDaily` rider — neither
is a callable, which is why they no longer sit in the file named for them),
`wave/sync_run.js` (the ONE owner of `importWithWatermark`/`drainForSync`/
`readWaveBusinessIdCached`), `wave/customers.js` (the App → Wave PUSH half),
`wave/customers_import.js` (the Wave → App PULL half — `importCustomers`,
`importOneCustomer`, `buildWaveIdIndex`, `BATCH_LIMIT`; `customers.js`
re-exports `importCustomers`, so no call site changed),
`wave/customer_queries.js` (the LEAF both halves require at module scope —
`readBusinessId` plus the `LIST_CUSTOMERS`/`LIST_CUSTOMERS_SINCE` documents; it
requires nothing, which is what keeps the pair acyclic without a lazy
require-back) and the pure `wave/retry_policy.js` (the dead-letter taxonomy,
`deps`-free like `notification_policy.js`).
Instant + business-time-zone primitives (`toMillis`,
`formatBusinessTime`/`formatTimeOfDay`, `businessYmd`/`businessOffsetMs`/
`businessMidnight`/`businessDayStartMs`, `BUSINESS_TIME_ZONE`) live in
`time_utils.js` and are shared
by `notification_utils.js`, `live_activity_utils.js`, and
`widget_payload_utils.js` — so a push and the Live Activity card can't drift on
how they render the same instant. It must stay **dependency-free**: those three
consumers sit on a `notification_utils` → `live_activity_dispatch` →
`live_activity_utils` require chain, and any require here would close a cycle.
Never re-inline a local `toMillis` or a bare `timeZone: "America/Toronto"`.
**`businessDayStartMs(instant, offsetDays)` is the one owner of the
"business-local midnight, n days out" composition** — the
`businessMidnight(...businessYmd(x), d + n)` spelling was written out at four
sites (`day_slice_utils` twice, `widget_payload_utils`, `notification_policy`)
and is the same shape that produced the documented DST bug: the offset must be
applied as a CALENDAR day and the zone offset re-resolved, never added as
`n * 86400000`, or a shift day comes out an hour wrong. Its jest cases pin the
23-hour and 25-hour days.
**`businessYmd`/`businessOffsetMs` read HOISTED module-scope
`Intl.DateTimeFormat`s (`YMD_FORMAT`/`OFFSET_FORMAT`), and that is a
performance invariant, not tidiness** — both take constant options, and
constructing an `Intl.DateTimeFormat` costs ~100x a `.format()` on an existing
one. Nothing called them in a loop until `day_slice_utils.js` existed; it
reaches them ~18 times per `sliceForDay`, and `buildWidgetPayload` probes every
record against every day, so a busy tech's 200-doc window was paying about a
second of pure CPU per push. Never move a formatter back inside one of these
functions, and add a new constant-options formatter at module scope beside
them.
**`day_slice_utils.js` sits one level above it** — the pure hand-mirror of
`lib/features/calendar/domain/appointment_day_slice.dart`, dependency-free
apart from `time_utils.js`, so it is a leaf too and `widget_payload_utils.js` /
`notification_messages.js` can both require it without closing a cycle. It owns
`sliceForDay`/`dayCountOf`/`lastWorkDayMs`/`calendarDaysBetween` and the 14-day
clamp; it **re-exports** `MAX_APPOINTMENT_SPAN_DAYS` rather than restating a
third copy of the Dart constant. Its jest cases reuse the Dart suite's worked
examples on purpose — a divergence between the two implementations fails a
test rather than shipping, so change both together.
**Its internals thread an already-resolved window** —
`lastWorkDayOfWindow(w)` / `dayCountOfWindow(w)` are the real bodies and the
record-taking `lastWorkDayMs`/`dayCountOf` are thin wrappers. `resolveWindow`
runs `businessMinutesOfDay` twice and each of those formats through `Intl`, so
the obvious record-taking chain (`sliceForDay` → `dayCountOf` →
`lastWorkDayMs`) resolved the SAME window three times on every probe. Keep new
internals on the window-taking form. For the same reason `travel_utils.js`
asks `dayCountOf(c)` LAST in its Live-Activity condition
(`kind === "leaveNow" && delivered > 0 && dayCountOf(c) <= 1`) — hoisted into a
local, every reminder-only and undelivered candidate paid for a value it
discards.
**Three more shared leaves, each extracted from copies that had already
drifted** (2026-08-22): `admin_firestore.js` (`adminFirestore()` — the lazy
`require("firebase-admin/firestore")` that keeps a module `require`-able from
jest; four modules carried a byte-identical private copy and their JSDocs had
already diverged on whether `Timestamp` came with it), `appointment_scan.js`
(`scanAppointmentWindow(db, {...})` — the status-`in` + two range `where`s +
`orderBy` + `limit` + warn-at-cap + map that all three scheduled sweeps spell
out; each caller keeps its own cap, status set and CONSEQUENCE sentence, and
`travel_utils.js` had re-spelled the record mapper inline TWICE rather than
using `recordOf`. The ORDERING argument is the reason it takes `descending`
explicitly: the overdue and digest sweeps look BACKWARD and must keep the
newest, the travel sweep looks FORWARD and must keep the soonest, and getting
it wrong silently spends the cap on the wrong jobs), and `wave/retry_policy.js`'s
`reclaimDecision` (the lease-expiry retry-or-dead-letter call, moved out of
`worker.js`'s `runTransaction` closure — all three of its outcomes destroy
something, and a decision reachable only through a Firestore-transaction mock
is one nobody re-reads).
Shared `defineSecret` params live
in `params.js` (`GOOGLE_MAP_API_KEY`, `APNS_AUTH_KEY`, `APNS_KEY_ID`,
`APNS_TEAM_ID`), imported by every consumer — a secret
may only be defined once, so never re-`defineSecret` it or re-export it from a
feature module. Full per-function reference: `docs/CLOUD_FUNCTIONS.md`.
Add a new function to its domain module and re-export it from `index.js`; put
shared guards in `security.js` and shared secrets in `params.js`, not back in
`index.js` or a feature module.
**Unit-testing trigger logic:** `onObjectFinalized`/`onSchedule` modules resolve
a Storage bucket at load, so a jest test can't `require()` them (throws "Missing
bucket name"). The resolution is the **trigger registration's**, in
`firebase-functions/lib/v2/providers/storage.js` — it fires as the module is
evaluated, not from any admin `getStorage()` handle in the module itself
(`maintenance.js`'s two are both lazy, inside the function bodies), so making
the handles lazier does not make the module requirable. Extract the pure logic into a plain sibling module
(`image_magic.js`, `notification_utils.js`) and test
that; `onCall`/`onDocument*` modules load lazily and are safe to `require`
directly. Jest tests live in **`functions/__tests__/` only** — the parallel
`functions/test/` directory was merged away 2026-07-19; don't recreate it.
- `syncUsersByUid` — Firestore trigger: mirrors `users/{id}` into `usersByUid/{uid}` bridge collection so security rules can resolve roles from auth UID alone. **It also owns deactivation:** on `active` → anything else it disables the Firebase Auth account + `revokeRefreshTokens` and purges every delivery artifact (`presence/location`, `fcmTokens`, `liveActivityTokens` via `recursiveDelete`, and the `liveActivityCards` marker); `→ active` symmetrically re-enables the account. This is load-bearing, not cleanup — the rules gates below assume a *live* status check can't be reached with a stale credential, and `deactivateEmployee` only flips the Firestore field. All of it runs AFTER the auth-critical bridge write and is idempotent (`retry: true`; `auth/user-not-found` is swallowed so the delete-account ordering converges). **Deactivation used to also ROTATE the Storage download tokens on that person's job photos** (`rotateAssignedImageTokens`, `appointment_image_tokens.js`) — that module, its trigger's raised `timeoutSeconds`, and the `(employeeIds CONTAINS, endTime DESC)` composite it needed were all **deleted at the photo-subcollection CONTRACT step**, which is what it was always scheduled to retire with. It existed because `ImageStorageService.uploadImage` minted a `getDownloadURL()` link per photo and persisted it into `pictures[]`: that link's `firebaseStorageDownloadTokens` value is stable per object, never expires and is served with no auth and NO `storage.rules` evaluation, so every assigned device held permanent rules-free copies that revoking the credential did not reach. **The app no longer mints or stores one**, so no NEW photo carries such a link — those are fetched through the SDK against `storage.rules`, which this branch's status flip already answers. **That is not the same as "nothing is left to invalidate", and this bullet used to claim it was:** legacy `appointments/*/images` rows with a `url` and no `storagePath` still exist (the backfill keeps them on purpose, the rules still accept the field, the client fallback is permanent), and those strings stay live after deactivation with nothing rotating them. Closing it needs a prod count of exactly those rows first — see `.claude/rules/images.md`. Don't reintroduce a broad rotation pass without first reintroducing the write that made one necessary; a scoped one over just those legacy objects is the open option. Two things it taught, worth keeping: a `deps` field resolved after entry is a branch no test can reach (the resolved bucket landed in a local while the callee read `deps.bucket`, so the control reported "nothing rotated" while rotating nothing, 2026-08-16); and a per-appointment parent write fans out to `notifyAppointmentChanges`, which stays a genuine no-op only because `diffAppointmentForNotifications` emits nothing for a photo-only diff — pinned by "a pictures-only rewrite emits nothing" in `notification_utils.test.js`.
**The bridge's pure rules moved to `bridge_policy.js`** — `shouldHaveBridge`, `bridgeBody`, `bridgeMatches` and `classifyBridgeRow` — shared with `scripts/backfill.js`, which repairs the same collection and had byte-identical copies of the first three under a comment claiming the duplication was deliberate (its stated reason, folding the role check in up front, stopped being a difference once this trigger gained the same check). `classifyBridgeRow` is the three-way decision guarding that script's `--prune-orphans` delete: `current` / `retained` (a uid claimed by a users doc the run SKIPPED — deleting it locks a live employee out of everything) / `orphan`. It was the only script here that deletes and the only one with no test.
- **Disabled employees must not read their old jobs.** `isAssignedEmployee` (`firestore.rules`) and `isAssignedToAppointment` (`storage.rules`) both gate on `status == 'active'`, NOT on bridge-doc existence — the bridge doc is deliberately retained for `disabled` users, so an existence-only check leaves a terminated tech reading client PII and job photos indefinitely. Keep the two helpers in lockstep.
- **`cascadeDeleteAppointmentImages` + `recountAppointmentPictures`** — see
  `.claude/rules/images.md` (moved 2026-08-19), which loads for
  `functions/appointment_image*.js` alongside the Dart image pipeline. Since
  the CONTRACT step the cascade deletes the Storage BYTES as well as the photo
  documents, and it is the only thing that does: the client used to enumerate
  `appointment.pictures` to know which objects to remove, and that array no
  longer exists.
- `placesAutocomplete` — proxies Google Places API (New) autocomplete. Requires App Check + auth + `assertAdmin` (address autocomplete is only surfaced on the admin-only appointment form, so gating on admin keeps a non-admin from scripting the billable API). Key in Secret Manager (`GOOGLE_MAP_API_KEY`).
- `placesGetDetails` — proxies Google Places API (New) place details. Same guards (App Check + auth + `assertAdmin`).
- `placesReverseGeocode` — proxies Google Geocoding API to convert a staff member's coordinates into a street address for the admin-only live staff map. Requires App Check + auth + `assertAdmin` + durable rate limit; returns only the top `formatted_address`; coordinates are never logged. Key in Secret Manager (`GOOGLE_MAP_API_KEY`).
- `validateUploadedImage` — Storage trigger: validates JPEG/PNG magic bytes for `appointments/*/images/*` uploads; deletes non-conforming files server-side.
- `propagateClientEdits` — Firestore `clients/{id}` update trigger: fans a client's name/phone/address edit onto that client's FUTURE appointments (the denormalized `clientName`/`clientPhone`/`address` copies). Per-appointment custom addresses (stored address ≠ client's previous address) and past/history visits are left untouched. Idempotent (absolute writes, `retry: true`); needs the `(clientId ASC, startTime ASC)` composite index. Pure helpers (`relevantClientChange`/`buildAppointmentPatch`) exported for unit tests.
- **Push, presence, the home-screen widget, Live Activities and Siri** live in
  `.claude/rules/notifications.md` (moved 2026-08-19) — the sweep and its
  policy split, `wantsTravelAlerts`, the widget window OVERLAP rule, the
  push-to-start token lifecycle, and the Siri snapshot schema. They span JS,
  Dart and Swift, so that rule is scoped across all three rather than living
  here. Modules: `notifications.js`, `notification_utils.js`,
  `notification_policy.js`, `travel_utils.js`, `live_activity*.js`,
  `widget_payload_utils.js`.
- **Wave Accounting** (`functions/wave/*`) lives in `.claude/rules/wave.md`
  (moved 2026-08-19) — the callables, the outbox/worker model and its inline
  drain, `mappedFieldsHash` and `shouldEnqueueClientWrite`, `healSyncState`,
  the import caps, and the dead-letter behaviour. Loads for `functions/wave/**`
  and the Settings UI that drives it.

**Firestore TTL policies and single-field index exemptions** are in
`.claude/rules/firestore-indexes.md` (moved 2026-08-19) — including the
never-`--force` reason and the expiration-offset-`0` rule. It is scoped to
`firestore.indexes.json` and `firestore.rules`, which this file does not cover:
editing that JSON at the repo root never loaded `functions/CLAUDE.md`.
Release runbook (ordering, old-build compatibility, rollback, deploy log):
`docs/DEPLOYMENT.md`.

Deploy: `firebase deploy --only functions,firestore:rules,firestore:indexes,storage`
(clear `AI_AGENT`/`CLAUDECODE`/`CLAUDE_CODE` in the shell first, or the CLI
stamps `agent-name/claude_code` into the audit log — see `docs/DEPLOYMENT.md` §5.)
(drop `firestore:indexes` only when `firestore.indexes.json` is unchanged — a
query whose index is missing fails `FAILED_PRECONDITION`, which best-effort
callers swallow into a silent no-op.)
(`storage:rules` is **not** a valid deploy target — use `storage`.)
Always run `cd functions && npm run lint` before deploying (Google ESLint, 80-char line limit).

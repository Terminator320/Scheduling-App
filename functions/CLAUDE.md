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
`readSessionToken`, `enforceDurableRateLimit`, `assertAdmin`),
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
order is auth → payload → identity → rate limit → work.
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
`readWaveBusinessIdCached`) and the pure `wave/retry_policy.js` (the
dead-letter taxonomy, `deps`-free like `notification_policy.js`).
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
Shared `defineSecret` params live
in `params.js` (`GOOGLE_MAP_API_KEY`, `APNS_AUTH_KEY`, `APNS_KEY_ID`,
`APNS_TEAM_ID`), imported by every consumer — a secret
may only be defined once, so never re-`defineSecret` it or re-export it from a
feature module. Full per-function reference: `docs/CLOUD_FUNCTIONS.md`.
Add a new function to its domain module and re-export it from `index.js`; put
shared guards in `security.js` and shared secrets in `params.js`, not back in
`index.js` or a feature module.
**Unit-testing trigger logic:** `onObjectFinalized`/`onSchedule` modules eagerly
resolve a Storage bucket at load, so a jest test can't `require()` them (throws
"Missing bucket name"). Extract the pure logic into a plain sibling module
(`image_magic.js`, `notification_utils.js`) and test
that; `onCall`/`onDocument*` modules load lazily and are safe to `require`
directly. Jest tests live in **`functions/__tests__/` only** — the parallel
`functions/test/` directory was merged away 2026-07-19; don't recreate it.
- `syncUsersByUid` — Firestore trigger: mirrors `users/{id}` into `usersByUid/{uid}` bridge collection so security rules can resolve roles from auth UID alone. **It also owns deactivation:** on `active` → anything else it disables the Firebase Auth account + `revokeRefreshTokens` and purges every delivery artifact (`presence/location`, `fcmTokens`, `liveActivityTokens` via `recursiveDelete`, and the `liveActivityCards` marker); `→ active` symmetrically re-enables the account. This is load-bearing, not cleanup — the rules gates below assume a *live* status check can't be reached with a stale credential, and `deactivateEmployee` only flips the Firestore field. All of it runs AFTER the auth-critical bridge write and is idempotent (`retry: true`; `auth/user-not-found` is swallowed so the delete-account ordering converges). **Deactivation also ROTATES the Storage download tokens on that person's job photos** (`rotateAssignedImageTokens`, `appointment_image_tokens.js`). `ImageStorageService.uploadImage` still persists a `getDownloadURL()` link per photo into `pictures[]`, and its `firebaseStorageDownloadTokens` value is stable per object and never expires — served over plain HTTPS with no auth and NO `storage.rules` evaluation — so every assigned employee's device holds permanent, rules-free links that revoking the credential does not reach. Rotating the object metadata is the only thing that can invalidate one, and nothing client-side can do it. It rewrites the stored `url` in the same pass, deliberately: rotating alone blanks those photos on exactly the old builds the `url` write exists for, and a deactivated employee can no longer read the document to see the replacement. Bounded at `ROTATE_APPOINTMENT_MAX` (500), newest first on the **new `(employeeIds CONTAINS, endTime DESC)` composite** — declared explicitly rather than leaning on index reversal, because every other DESC query here has its own entry and a missing index would fail `FAILED_PRECONDITION` straight into this module's swallow, i.e. a security control that silently stops running. **Deploy `firestore:indexes` with it.** Warn-at-cap, and it **NEVER throws**: a rethrow inside `retry: true` would re-run the whole handler and re-rotate everything already done for something a retry cannot fix. It resolves the bucket LAZILY, so the module stays jest-requirable — the split `maintenance_policy.js` exists to enforce. **That lazy branch is the ONLY one production takes and was therefore the only one no test could enter, which is exactly how it shipped broken** (fixed 2026-08-16): the resolved bucket landed in a local while `rotatePictures` reads `deps.bucket`, so every object rotation threw into this module's own swallow and the control reported "nothing rotated" while rotating nothing. It now threads the resolved bucket into the deps it passes down, and takes an injectable `resolveBucket` purely so jest can reach that branch. Treat any `deps` field resolved after entry the same way. **It runs LAST in the handler, after the Auth disable + `revokeRefreshTokens`** — it is the only step here that can run for minutes, so ordered ahead of them the revocation this whole branch exists to perform waited on 500 appointments' worth of Storage writes, and a timeout at the ceiling meant it never happened at all that pass. Its two concurrency bounds MULTIPLY (`ROTATE_CONCURRENCY` appointments × `ROTATE_PHOTO_CONCURRENCY` photos), so the real ceiling on in-flight GCS chains is the product — never leave the inner loop unbounded on the reasoning that the outer one is capped. **Its trigger fan-out is bounded and cheap, and the reason is worth knowing before you "optimize" it.** Each rotated appointment takes a parent `pictures` write, so one deactivation fires up to 500 `notifyAppointmentChanges` invocations. Every one is a genuine no-op: `endCardOnTerminal` finds no targets in memory and `diffAppointmentForNotifications` returns no events for a `pictures`-only diff, so `handleAppointmentWrite` returns **before any Firestore read** — 500 empty invocations, zero reads, zero writes, no pushes. `recountAppointmentPictures` is NOT fired by these writes at all: it triggers on `appointments/{id}/images/{imageId}`, the subcollection, not the parent. Pinned by "a pictures-only rewrite emits nothing" in `notification_utils.test.js` — make the differ sensitive to `pictures` and this becomes 500 recipient lookups and widget-window queries instead.
**It reaches an appointment with NO `endTime` through a second, UNORDERED backstop pass** (2026-08-16). The ordered pass structurally cannot see one — Firestore omits documents missing the field it orders by — and such docs reach the server from legacy and console writes (`day_slice_utils.js` carries its own branch for them), so their photos kept permanent tokens forever with nothing logging it. The backstop is bounded by the same `ROTATE_APPOINTMENT_MAX`, is served by the automatic `employeeIds` array index (no new composite), filters to `endTime == null`, and dedupes by doc id so a dated job is never rotated twice. Don't fold the two passes into one unordered query to "simplify": that trades a closed hole for an arbitrary `__name__`-ordered slice and loses the newest-first property the cap rests on. It is defence-in-depth behind the rules' status gate, never the gate itself, and it retires with the `url` write at the photo-subcollection CONTRACT step. `timeoutSeconds` on this trigger is raised to 300 for it; that is a ceiling, not a cost. **The bridge's pure rules moved to `bridge_policy.js`** — `shouldHaveBridge`, `bridgeBody`, `bridgeMatches` and `classifyBridgeRow` — shared with `scripts/backfill.js`, which repairs the same collection and had byte-identical copies of the first three under a comment claiming the duplication was deliberate (its stated reason, folding the role check in up front, stopped being a difference once this trigger gained the same check). `classifyBridgeRow` is the three-way decision guarding that script's `--prune-orphans` delete: `current` / `retained` (a uid claimed by a users doc the run SKIPPED — deleting it locks a live employee out of everything) / `orphan`. It was the only script here that deletes and the only one with no test.
- **Disabled employees must not read their old jobs.** `isAssignedEmployee` (`firestore.rules`) and `isAssignedToAppointment` (`storage.rules`) both gate on `status == 'active'`, NOT on bridge-doc existence — the bridge doc is deliberately retained for `disabled` users, so an existence-only check leaves a terminated tech reading client PII and job photos indefinitely. Keep the two helpers in lockstep.
- **`cascadeDeleteAppointmentImages` + `recountAppointmentPictures`** (`appointment_images.js`, added 2026-08-13 with the photo-subcollection move; +2 exports). **The cascade is not cleanup — it is the reason this feature needs a server component at all: Firestore does NOT delete a subcollection when its parent document is deleted.** Without it every appointment delete leaves `appointments/{id}/images/*` orphaned under a parent that no longer exists: invisible in the console, unreachable by every query the app makes, and with nothing anywhere reporting it. It must cover all three delete paths — the client's single delete, its series delete, and `purgeExpiredHistory` (Admin SDK deletes fire triggers too). It uses `recursiveDelete` (the same Admin-SDK bulk writer `syncUsersByUid` already uses for `liveActivityTokens`) and **RETHROWS**, deliberately unlike the best-effort cleanup elsewhere here — a swallowed error leaves exactly the permanent invisible orphans it exists to prevent, and rethrowing is what makes `retry: true` mean anything. `recountAppointmentPictures` maintains the denormalized `pictureCount` on the parent that `AppointmentCard`'s photo indicator reads (the card renders on every range-query surface and cannot afford a subcollection read each): an **absolute `count()` aggregate, never an increment**, same rule and same reason as `recountClientJobs` under `retry: true`, written with `update()` so an appointment deleted in the window is never resurrected as a count-only stub (a `NOT_FOUND` there is the normal path, not an error — the cascade has just removed the photos). **It recounts on EVERY write, including an update that cannot have moved the count, and that is deliberate.** An `if (before.exists && after.exists) return` guard was written and then removed: the only paths it skips are the offline queue replaying `set(..., {merge: true})` on the DERIVED doc id and a backfill re-run, and those two are the ONLY self-heal this counter has — a recount whose parent `update()` keeps failing exhausts its retry window and leaves `pictureCount` wrong forever, where an idempotent replay repairs it silently. It also buys nothing against the real write amplification: `appendAppointmentPictures` writes N image docs in ONE batch, so N recounts hit the SAME parent within milliseconds (against Firestore's ~1 write/sec/document guidance), but those are genuine CREATES that any such guard must let through. **That bit, and the fix was to DEBOUNCE the recount, never to suppress the replay** (2026-08-15): `debouncedRecountPictures` claims the parent in the Admin-SDK-only `appointmentRecountClaims/{appointmentId}` ledger (`create()`-fails-if-exists, same shape as `claimSeriesNotice`), so the first trigger of a batch does the one recount and the other N−1 return having written nothing — which also collapses the second-order fan-out, since every parent write re-fires `notifyAppointmentChanges` (10 photos was 10 recounts AND 11 notification invocations for one user action). **The ORDER is the whole safety argument: the claim is released BEFORE the aggregate runs.** A suppressed sibling's photo was committed before its trigger fired, and its trigger fired before the release, so a strongly-consistent `count()` after the release necessarily sees it — nothing a debounce suppressed can be missed. Count first and release after and a photo written in that gap is both suppressed and uncounted, which is the one way this optimization could corrupt the number it maintains. **The replay self-heal survives because the claim never outlives its batch**: it is deleted on the normal path, `RECOUNT_CLAIM_STALE_MS` (15 s) takes over one abandoned by a killed invocation, and the `expiresAt` TTL policy (`firestore.indexes.json`, offset 0) is housekeeping behind both — so a later, separate write (the offline queue's replay, a backfill re-run) always claims afresh and always recounts. The claim path FAILS OPEN on any ledger error: an extra parent write is exactly the old behaviour, where a skipped recount is a wrong count with nothing left to notice it. Releasing first is also what lets a `retry: true` retry of a failed parent `update()` re-claim instead of suppressing itself. Both bodies (`purgeAppointmentImages`, `recountPictures`) take an injected `db` and are jest-tested. `IMAGES_SUBCOLLECTION` is hand-mirrored by `AppointmentImagesStore.imagesSubcollection` (`calendar/data/appointment_images_store.dart` — the phase-1 photo surface split out of `firebase_appointments_repository.dart` so the CONTRACT step is a file rather than a diff through a 900-line class) AND by the literal `match /images/{imageId}` in `firestore.rules`; renaming one alone points the trigger at a collection nothing writes and the cascade silently stops cascading. The doc-id helper lives in the dependency-free `appointment_image_ids.js`, hand-mirrored from `appointment_image_doc_id.dart` and sharing its worked examples so a divergence fails a test rather than putting one photo at two ids.
- `placesAutocomplete` — proxies Google Places API (New) autocomplete. Requires App Check + auth + `assertAdmin` (address autocomplete is only surfaced on the admin-only appointment form, so gating on admin keeps a non-admin from scripting the billable API). Key in Secret Manager (`GOOGLE_MAP_API_KEY`).
- `placesGetDetails` — proxies Google Places API (New) place details. Same guards (App Check + auth + `assertAdmin`).
- `placesReverseGeocode` — proxies Google Geocoding API to convert a staff member's coordinates into a street address for the admin-only live staff map. Requires App Check + auth + `assertAdmin` + durable rate limit; returns only the top `formatted_address`; coordinates are never logged. Key in Secret Manager (`GOOGLE_MAP_API_KEY`).
- `validateUploadedImage` — Storage trigger: validates JPEG/PNG magic bytes for `appointments/*/images/*` uploads; deletes non-conforming files server-side.
- `propagateClientEdits` — Firestore `clients/{id}` update trigger: fans a client's name/phone/address edit onto that client's FUTURE appointments (the denormalized `clientName`/`clientPhone`/`address` copies). Per-appointment custom addresses (stored address ≠ client's previous address) and past/history visits are left untouched. Idempotent (absolute writes, `retry: true`); needs the `(clientId ASC, startTime ASC)` composite index. Pure helpers (`relevantClientChange`/`buildAppointmentPatch`) exported for unit tests.
- **Push notifications** (`notifications.js` + jest-testable `notification_utils.js`; functions + rules **deployed to prod 2026-07-11**; iOS-native APNs key + Push/App-Groups entitlements wired on the Mac 2026-07-11; the two ledger collections' Firestore **TTL policies were enabled 2026-07-11** — on-device verify is the only push item still pending; see the archived push-notifications plan): `notifyAppointmentChanges` (appointment write trigger → assignment/reschedule/cancel/unassign pushes; deliberately no `retry` — a duplicate push is worse than a missed one. **Repeat series are collapsed to ONE push per (employee, kind)**: a "this and all future" edit writes up to ~15 sibling docs in one client batch and each fires this trigger, which used to mean ~15 pushes and ~15× the reads for a single user action. The differ's anchor rule (`id === seriesId`) handles CREATE only — delete/cancel/reschedule batches often start partway through a series, so the anchor doc is frequently absent and an anchor-only rule would suppress *every* notification. Hence the `appointmentSeriesNotices/{seriesId}_{kind}_{employeeDocId}` claim ledger (`claimSeriesNotice`, Admin-SDK-only). It **fails OPEN** everywhere — any claim error (and, in the delete fallback, a claim with no readable `createdAt`) sends anyway; degrading to the old one-push-per-sibling behavior beats risking a dropped cancellation for a tech already driving to the job. **Two keying modes.** WRITES (create/update — after present) carry a fresh **`seriesOpId`** stamped by `_newSeriesOpId()` in `firebase_appointments_repository.dart`: one uuid per write operation, shared by every doc that operation touches and reused by no other, so an `op_<opId>_<kind>_<emp>` claim collision is DEFINITIVE (same batch) and needs **no time window** — two separate actions get different op-ids and both notify, even back-to-back. That is what fixed the "cancel Tuesday then Thursday of the same series → second push dropped" bug. DELETES have no `after`, so `before.seriesOpId` is stale (minted at the doc's last write, shared by every future delete of the series) — the call site passes `""` for a delete, routing it to the fallback `(seriesId, kind, employee)` + `SERIES_CLAIM_WINDOW_MS` (45 s, keep in seconds) + stale-takeover. **`updateAppointmentStatus` stamps `seriesOpId` ONLY on `cancelled`, never on `done`** — the employee mark-done rule is `affectedKeys().hasOnly(['status','updatedAt'])`, so a stray field there is `permission-denied`; cancel is admin-only. `seriesOpId` is write metadata, NOT on `AppointmentRecord`. Build the claim's `.doc()` ref INSIDE the try — `.doc()` throws synchronously on an id containing `/`, and an escape here would kill every push for the write instead of degrading), `sendUpcomingJobReminders` (every 5 min, **travel-aware "time to leave" reminder** — `runTravelAwareReminderSweep` in `travel_utils.js`; per (job, assignee) it decides an origin [intervening job's address → fresh background-GPS presence ≤25 min → recently-ended job's address ≤4h → none], calls Google Routes API `computeRoutes` with `TRAFFIC_AWARE`, and fires at `startTime − driveTime − 10min`; **every failure path — no origin, empty address, any Routes error — degrades to the fixed 30-min `reminder` kind**, so it never regresses below the old behavior; `leaveNow` kind sets APNs `interruption-level: time-sensitive`. Reuses the existing `appointmentReminders/{id}_{startMs}_{employeeDocId}` ledger and key format, so claims from before the upgrade stay honored. The per-employee origin-context read is bounded by `CONTEXT_QUERY_MAX` (`travel_utils.js`), ordered `endTime` ASC so the cap keeps the just-ended/imminent jobs `decideOrigin` actually uses — don't remove the `.limit()` or the query re-reads every future appointment each sweep. **The CANDIDATE query is bounded too, by `TRAVEL_SWEEP_MAX` (500, added 2026-08-13), ordered `startTime` ASC** — at the time it was the only sweep in the repo with no ceiling; the nightly digest gained the same treatment two days later (`DIGEST_SWEEP_MAX`, 1000, `notification_policy.js`), so `TRAVEL_SWEEP_MAX`, `OVERDUE_SWEEP_MAX` and `DIGEST_SWEEP_MAX` are now the three warn-at-cap sweep ceilings in the repo. The 90-minute window keeps it small in practice, so this is a tail guard rather than a steady-state bound: a bulk import or a wide repeat series landing in one window is otherwise an unbounded fan-out that then makes a BILLABLE Routes call per candidate assignee. The ordering is what makes the cap safe — `startTime` ASC is already the order Firestore returns for this query (it is the inequality field), so the cap keeps the most IMMINENT departures, and anything deferred self-heals on the next 5-minute run under its existing ledger claim. It warns at the cap, like the overdue and digest sweeps beside it. No new index — the existing `(status, startTime ASC)` composite serves it. Its `endTime` upper bound is `TRAVEL_WINDOW_MS + MAX_BOOKING_MS`, **not** the travel window: an intervening job can start inside the window and still run a full day longer, and narrowing the bound to the window silently drops it from `decideOrigin`'s first prong. The sweep also memoizes drive-time estimates per (job, assignee) for `ESTIMATE_TTL_MS` so a job sitting in the 90-min window isn't re-priced ~18 times to fire once — a cached estimate may only ever DEFER a Routes call (by `SKIP_MARGIN_MS`), never trigger a send; the fire decision is always made against a fresh response. Needs the Routes API enabled + added to the `GOOGLE_MAP_API_KEY` restriction), `sendDailyJobDigest` (18:00 Toronto, which **also calls `runWaveDaily()`** — the Wave drain + due-import, folded in when `waveScheduledImport` was deleted. **Its candidate query orders `startTime` DESC, and the DIRECTION is the whole point of `DIGEST_SWEEP_MAX`** (fixed 2026-08-16): the floor is `tomorrowStart − MAX_APPOINTMENT_SPAN_MS`, i.e. 15 days in the PAST, so ascending made the cap keep the OLDEST still-open jobs and discard the newest — tomorrow's, the only ones the digest is about. Once a growing tail of unclosed jobs exceeded 1000, the 18:00 run read 1000 documents that had all started a week ago, `groupTomorrowsJobsByEmployee` found no overlap, and **every crew silently got no digest at all** — the exact omission the cap exists to prevent, inverted. The comment above it had justified ascending with reasoning imported from `runTravelAwareReminderSweep`, whose window starts at `now`; `runOverduePromptSweep` already ordered `endTime` DESC for this reason. Served by the existing `(status, startTime DESC)` composite — no new index — and the list is reversed in memory before grouping so the digest text stays chronological), and the overdue "job finished?" nudge for jobs past `endTime` but still open — a server mirror of the display-only `overdue` state, keep in sync with `AppointmentRecord.displayStatus`. **That nudge is no longer its own export**: `sendOverdueJobPrompts` (`every 15 minutes`) was deleted 2026-08-13 and merged into `sendUpcomingJobReminders`, which now runs it three times as often. That is safe because the per-recipient ledger (`appointmentOverduePrompts/{id}_{endMs}_{employeeDocId}`, create-fails-if-exists), never the cadence, is what guarantees at-most-once delivery. **The merge was a COST change**: Cloud Scheduler bills per job beyond the first three, and this repo had six — folding the overdue sweep here and the Wave daily into the digest, plus deleting `waveSyncWorker`, is what brings it to exactly three. Adding a fourth scheduled function starts costing money, so reach for an existing sweep before defining one. Recipients always filtered to active employees; tokens in `users/{docId}/fcmTokens/{token}` (per-device `locale` drives EN/FR text). **REACHABILITY IS ASKED BEFORE THE WORK, everywhere** — `_loadRecipient` + `_canReachRecipient` run above `fetchEmployeeWidgetWindow` in the digest and above the ledger `create()` in `_deliverRecipientOnce`, the order `handleAppointmentWrite` established and documented. Both reads land in the same per-sweep `cache`, so asking costs nothing the send would not already pay. Claiming first cost 2 writes + 2 reads per unreachable (job, assignee) pair on EVERY run — ~48 of each across the overdue window's 2 h at a 5-minute cadence — and the digest paid a 200-doc read plus a whole payload build per unreachable employee, daily, for a send that returns 0. Semantics are unchanged: "no ledger written" is indistinguishable from "written then released", so the late-token retry the release exists for still works. Idempotency via Admin-SDK-only **per-recipient** ledgers `appointmentReminders/{id}_{startMs}_{employeeDocId}` and `appointmentOverduePrompts/{id}_{endMs}_{employeeDocId}` (create()-fails-if-exists; any claim — reminder OR overdue — with zero delivered pushes is released for retry, keyed per assignee so a late-registering token is retried without re-notifying an already-delivered assignee; both write `expiresAt` +7d for a console-enabled Firestore TTL — see the TTL-offset rule under Cloud Functions). The overdue sweep queries **`endTime` over `OVERDUE_LOOKBACK_MS` (2 h — reduced from 24 h on 2026-08-13 when the sweep was folded into the 5-minute reminder timer, so it is sized against that cadence, not against an outage)**, with bounds (`> floor`, `<= now`) that mirror `selectOverdueCandidates` exactly, so the scan is the width of the rule rather than a superset of it — **ordered `endTime` DESC**, on the `(status, endTime DESC)` composite index added 2026-08-13, so the `OVERDUE_SWEEP_MAX` cap keeps the newest-overdue jobs, not the ones closest to aging out. **Deploy `firestore:indexes` with this or the sweep fails `FAILED_PRECONDITION` and prompts nobody**, and don't drop the `orderBy`. It queried `startTime` until then, which forced a floor of 24h PLUS the longest bookable span — about 15 days — because a job that STARTED a fortnight ago can still have just ended; that meant re-reading every open job of the last two weeks 96 times a day to prompt the few that had ended, and it silently lost any run longer than `MAX_APPOINTMENT_SPAN_DAYS` (reachable by a console or Admin-SDK write, which bypass the rules' span bound). `OVERDUE_QUERY_WINDOW_MS` is gone; `OVERDUE_LOOKBACK_MS` is now both the eligibility window and the query floor. A doc with **no `endTime`** is excluded by the filter instead of read and then dropped in code — same outcome, one less read. (Travel-aware sweep + audit hardening **deployed to prod 2026-07-18**.)
  - **Client side:** `PushRegistrationController` (`features/notifications`) registers this device's FCM token for active employees AND admins (`shouldRegisterPush` — admins register only for the timed nudges; the server withholds change-driven pushes from them), keyed by the users-doc id at `users/{docId}/fcmTokens/{token}`; `AppSyncListeners` (`core/app/app_sync_listeners.dart`, registered from `main.dart`) drives `sync()` on every account-doc emission + on language change (re-upserts `locale`). A notification tap AND an iOS home-screen widget tap both deep-link to the appointment detail sheet.
  - **Live-location presence** (`features/presence`, `geolocator`, backs the travel-time reminders): `PresenceSyncController` mirrors `PushRegistrationController` (provider + `main.dart`-driven `sync()` on every account-doc emission; both — and the Live Activity registration controller — get their coalesce-not-drop reentrancy from the shared `ReentrantSync` mixin (`core/utils/reentrant_sync.dart`), so `sync()` sets the guard synchronously before its first await and a concurrent call re-runs exactly once with the latest state; don't re-inline `_busy`/`_pendingResync`) and owns a **foreground-only** `getPositionStream` for active employees AND admins (`shouldTrackPresence` **delegates to** `shouldRegisterPush`, so the presence audience can't drift from the push audience — never re-inline the predicate body). **The `location` UIBackgroundModes entry was REMOVED 2026-07-27 after an App Store rejection under guideline 2.5.4** ("using the location background mode for the sole purpose of tracking employees is not appropriate") — iOS now suspends the stream whenever the app is backgrounded, and that is intended. **Never re-add `location` to `UIBackgroundModes`, and never request an Always upgrade** (`LocationPermissionService.ensureLocation` deliberately issues exactly ONE prompt — the second, escalating `requestPermission()` call was removed; a pre-existing Always grant is still honored, we just never ask). **`NSLocationAlwaysAndWhenInUseUsageDescription` is a separate matter and is NOT covered by this — see `ios/CLAUDE.md` for why that key stays declared on purpose** (it satisfies App Store Connect's static-scan ITMS-90683 check, which fires on `geolocator_apple` compiling `requestAlwaysAuthorization` into the binary regardless of whether the app calls it; the key cannot itself trigger an Always prompt, since the plugin checks `NSLocationWhenInUseUsageDescription` first). An earlier version of this bullet told you to remove that key too, directly contradicting `ios/CLAUDE.md` — which once cost a security reviewer a false finding for "cleaning up" a plist key this file wrongly said was dead. `AppleSettings.showBackgroundLocationIndicator` was dropped for the same reason: it only means anything for a stream that survives backgrounding. `geolocator` gates `allowsBackgroundLocationUpdates` on the Info.plist key itself (`GeolocationHandler.shouldEnableBackgroundLocationUpdates`), so the removal degrades cleanly instead of throwing. It writes `users/{docId}/presence/location` (`{lat, lng, uid, updatedAt: serverTimestamp()}`, self-only rules, `updatedAt == request.time` so freshness can't be spoofed) throttled to 250 m of movement / ≥2 min per write, plus a 10-min heartbeat re-upsert so a *stationary* tracker stays fresh (server staleness window is `PRESENCE_STALE_MINUTES = 25` in `travel_utils.js` — a live heartbeat sits well inside it). A *failed* write rolls the throttle clock back (`upsertLocation` returns `PresenceWriteResult.ok/failed/denied`) so a dropped write can't suppress the next fix and let the doc drift toward the staleness window; a **`denied`** result additionally calls `_stop()` — the rules gate presence on an active account, so a deactivated user's background stream would otherwise log a denied write every heartbeat until the app is killed (the 11-event Crashlytics spam of 1.32.0; next `sync()` on resume/account-emission re-runs the gate). Expected stream deaths (permission revoked / Location Services off, incl. the iOS `kCLErrorDomain error 1` surfaced as `PositionUpdateException`) are classified by `_isExpectedLocationLoss` and logged WITHOUT a Crashlytics error record. OS location permission is the only switch: a denial degrades silently (server falls through its address→30-min chain). **Because presence is now foreground-only, a backgrounded device's doc goes stale within `PRESENCE_STALE_MINUTES` and the travel-aware sweep routinely falls back to the intervening/recent job address, or to the fixed 30-min `reminder` kind — that fallback is the normal path now, not an error case.** `decideOrigin`'s presence prong still fires whenever a tech has the app open (the common case while reviewing the day's route), so keep it. Torn down + presence doc deleted on sign-out/delete (beside `unregisterCurrentDevice`). The position stream is **device-only** verification (no geolocator channel tests). iOS needs only `NSLocationWhenInUseUsageDescription` in `Info.plist`; the Time Sensitive Notifications entitlement (for `leaveNow`) is Mac-side. **Admin live staff map read path:** admins read ALL presence via a collection-group rule (`match /{path=**}/presence/{presenceId}` read if `isAdmin()`; the wildcard reserves the subcollection name `presence`); the client joins `collectionGroup('presence')` to `watchAllUsers()` on the admin-only Live map hub tab; `presenceStaleAfter` (Dart, `lib/features/presence/domain/live_map_aggregator.dart`, 25 min) must stay in sync with `PRESENCE_STALE_MINUTES` in `functions/travel_utils.js`. **Staleness is surfaced as TEXT only** — the freshness labels in the info card + roster (`LiveMapAggregator.isStale`/`freshnessOf`); the **map marker itself is never dimmed/greyed** (the `staleDocIdsProvider` + marker-dimming path was removed 2026-07-19, and `StaffMarkerIconRenderer` has no `stale` param), so don't reintroduce pin greying. Presence docs are server-purged by `syncUsersByUid` (`functions/bridge.js`) when a user doc is deleted or status leaves `'active'` (purge runs AFTER the auth-critical bridge write, isolated try/catch) — see the deactivation invariant under Cloud Functions for the rest of that purge. The map's **staff roster sheet** (`staff_roster_sheet.dart`) lists everyone sharing location; ordering, haversine distance, and nearest-city parsing are pure functions on `LiveMapAggregator` (`sortedByProximity`/`distanceMeters`/`cityFromAddress` — self row leads, rest nearest-first) so they test without the geolocator/Maps plugins. Location permission is gated by `LocationPermissionService` (`core/permissions`, `geolocator`; `whileInUse`/`always` both count as granted).
  - **iOS home-screen widget** (`features/home_widget` + `ios/ScheduleWidget`, `home_widget` package, iOS-only): `WidgetSyncService` writes a **two-day** payload into the App Group `group.net.vogas.scheduling` — `todayJobs` (remaining, non-terminal), `tomorrowJobs`, and a `rolloverAt` instant so WidgetKit flips today→tomorrow on-device with no app run (set only once today has no incomplete job left). The widget payload's `startTime` MUST be an absolute UTC instant (`toUtc().toIso8601String()`, …Z) — a bare local `toIso8601String()` has no zone designator and the Swift `ISO8601DateFormatter` can't parse it. The Dart builder (`buildWidgetPayload`, `widget_sync_service.dart`) and the server builder (`functions/widget_payload_utils.js`) are hand-mirrored — keep them and the Swift decoder in lockstep. **Known divergence:** the server resolves day boundaries in `America/Toronto`; the Dart mirror uses device-local midnight — harmless for this single-timezone (Quebec) business, but on an off-Toronto device the app-written and push-written payloads can disagree on which day a job is "today". **All-day blocks narrow that margin to zero:** a timed 2 p.m. job needs a ~10 h offset to change days, but an all-day block starts *at* midnight, so any westward device offset flips its bucket and the widget's contents depend on which writer went last. Still accepted (single-timezone business) — but this is the first thing to fix if the app ever ships outside Quebec. Widget/notification taps use the `esproschedule://appointment?id=…` deep link.
  - **The server-side widget window asks for an OVERLAP, not a back-scan** (2026-08-13). `fetchEmployeeWidgetWindow` (`notification_utils.js`) reads the jobs overlapping `[today 00:00 Toronto, +WIDGET_LOOKAHEAD_DAYS)` as `endTime >= todayStart AND startTime < end`, on the existing `(employeeIds CONTAINS, endTime ASC, startTime ASC)` composite. It used to floor `startTime` at `todayStart − MAX_APPOINTMENT_SPAN_MS` and let `buildWidgetPayload` drop the rest, because a query on `startTime` alone cannot see a multi-day run that began earlier but still WORKS today — so it read ~17 days of that employee's appointments to render 3, **once per notified assignee on every appointment write**. Firestore has supported two inequality fields since 2023, so the overlap is now the query rather than a superset of it. Two consequences, both fine and both pinned by a test: results arrive ordered by `endTime` (the first inequality field) rather than `startTime`, which `buildWidgetPayload` never depended on since it sorts every bucket by window start itself; and a doc missing EITHER instant is absent from a composite index where the old form only required `startTime` — such a record has no parseable window, so `sliceForDay` already dropped it one step later. Don't re-widen the floor: the test asserts the two bounds are exactly `WIDGET_LOOKAHEAD_DAYS` apart. It is `.limit`ed at `WIDGET_WINDOW_MAX` (200) and **warns at the cap** — it was the one sweep read left without a ceiling after the travel/overdue/digest sweeps gained theirs, and it runs once per assignee on every notified write, so a bulk import landing in the window is an unbounded fan-out that ships a PARTIAL widget payload in silence.
  - **Widget refresh while the app is closed:** change-driven pushes carry a fresh `widgetPayload` + APNs `content-available`, so `firebaseMessagingBackgroundHandler` (`core/notifications/fcm_background_handler.dart`, registered via `FirebaseMessaging.onBackgroundMessage` in `main()`) rewrites the widget in a fresh OS-spawned isolate — without it the widget only updated while the app ran. It MUST stay a top-level `@pragma('vm:entry-point')` function, iOS-gated, and dependency-light (only the `home_widget` channel after `WidgetsFlutterBinding.ensureInitialized()`; NO `Firebase.initializeApp`/Firestore/Riverpod in the isolate).
  - **iOS Live Activities — "time to leave" card** (`features/live_activity` + `ios/ScheduleWidget/JobLiveActivity.swift`, `live_activities` package, iOS 17.2+, **built 2026-07-19; DEPLOYED to prod + on-device card-start VERIFIED on real hardware 2026-07-20. The Lock Screen card renders and is started by the `leaveNow` sweep end-to-end; the Dynamic Island presentation is still unverified — the test device is a base iPhone 14, which has no Dynamic Island (Pro-only hardware)**): a Lock Screen / Dynamic Island card started by the travel-aware `leaveNow` sweep and ended when the job completes. **FCM cannot send Live Activity pushes** (they need `apns-push-type: liveactivity` on topic `net.vogas.scheduling.push-type.liveactivity`), so this is the one path with a **direct APNs HTTP/2 client** (`apns_client.js`, ES256 provider JWT cached and re-minted at 50 min; secrets `APNS_AUTH_KEY`/`APNS_KEY_ID`/`APNS_TEAM_ID`). **APNs environment: `sendLiveActivityPush` tries the PRODUCTION host, then retries the SANDBOX host on a `BadDeviceToken` response** (added 2026-07-20). This is load-bearing for *any* dev-signed build: a `flutter run` build ships an `aps-environment: development` provisioning profile, so its push-to-start token is a SANDBOX token that the production host rejects with `BadDeviceToken` → the card would never start (the plain `leaveNow` push still works because FCM auto-routes APNs environments; the direct client does not). The retry only fires when the production push did NOT deliver, so a production (TestFlight/App Store) token that succeeds on the first host is never re-sent — no duplicate-card risk. Don't remove the sandbox fallback thinking "prod only." **Every Live Activity path is additive and best-effort** — no token, no secrets, iOS < 17.2, Live Activities disabled, or any APNs failure all degrade to the existing `leaveNow` push, which fires independently and is unchanged; nothing in the reminder pipeline gains a new way to fail. Keep it that way. The start hangs off `deliverRecipientOnce`'s **return value** (`kind === 'leaveNow' && delivered > 0`) so it inherits that ledger's exactly-once claim — a start placed before the claim double-fires on a collision. **`liveActivityCards/{employeeDocId}` (Admin-SDK-only) is load-bearing, not a convenience:** a push-*started* activity's id is minted by ActivityKit and its attributes can't be read back, so the device physically cannot stamp `appointmentId` on its own token row — the server owns that association, and update/end resolve through the marker (resolving by employee alone would let a cancel on next week's job kill the card for the job the tech is driving to). The travel→on-site flip is **clock-derived on both sides** (mirrors `AppointmentRecord.displayStatus`); **no `markInProgress` write path exists or should be added**. Both the flip and the end are **server-owned**: `runOnSiteFlipPass` must run on every sweep — not only when there are travel candidates, since a tech whose job already started is by definition no longer a candidate — and **every terminal transition ends the card via `endCardOnTerminal` in the appointment write trigger: done, cancelled, DELETED, and unassigned, deliberately UNCONDITIONAL on the job's start time** (generalized from done-only `endCardOnCompletion` 2026-07-21; the notification diff suppresses events for past-start jobs via `notPast`, which is exactly when a live card exists — riding the diff left a deleted/cancelled started job's card stuck on the Lock Screen). `runOnSiteFlipPass` is the backstop for the same bug: a marker whose appointment is deleted/terminal must END the on-device card (`endLiveActivity`), never just clear the marker — the card outlives the Firestore doc. Keep the explicit `clearCardMarker` after that backstop end: `endLiveActivity` returns before clearing the marker when no token rows remain. The client must never end cards off its own status write (`endAllActivities()` is device-wide, so completing job B would kill the card for job A). "Complete" is a **deep link** into the appointment sheet, never a new authenticated write surface in the extension. Card text is built server-side in EN/FR from the `_MESSAGES`-shaped table in `live_activity_utils.js` — never `NSLocalizedString` in Swift, which would fork translations outside the ARBs. `buildContentState`/`buildAttributes` and `ios/ScheduleWidget/LiveActivitiesAppAttributes.swift` are hand-mirrored — the content state carries `endTime` (added 2026-07-21) so the on-site card counts DOWN the remaining booked time to the scheduled end (`Text(timerInterval:countsDown:true)`, a live system timer that ticks without pushes); past the end — or on a payload with no `endTime` — it falls back to the elapsed count-up from the start, which honestly signals the overrun. Thread `endTime` through every dispatch `ctx` (sweep candidate, on-site flip, reschedule update) or the next update push silently drops the countdown. **A travel-phase card with no known `leaveAt` must NEVER label the job's own `startTime` as "Leave at"** — `buildContentState` renders the `startsAt` string ("Starts at" / "Débute à") in that case. The old fallback silently presented the appointment time as the departure time, so a rescheduled job told the tech to leave exactly when they were due to arrive (fixed 2026-07-27). Only the sweep knows a real lead, so `writeCardMarker` persists `leadMinutes`/`travelMinutes` on `liveActivityCards/{employeeDocId}` at card start and `updateLiveActivity` rebuilds `leaveAt = newStart − leadMinutes` from the marker (`_withLeaveAt`) — that's why the reschedule hook can pass `leaveAt: null` and still render a correct departure time. `setCardStart` merges, so it must never overwrite those two fields. `_liveRowsFor` returns `{rows, marker}` (not a bare array) to feed that rebuild without a second marker read. Note `live_activity_dispatch.js` defines its own `MINUTE_MS` rather than importing it from `travel_utils.js` — that module requires this one, so reaching back would close a cycle. **The on-site backstop (`listCardsDueForOnSite`) keys the flip off `marker.startTime`, so `updateLiveActivity` must refresh it via `setCardStart` (merge start+phase) on EVERY update, not just the flip** — a reschedule that left the stale start flipped a job moved earlier past the tech's real arrival and re-pushed a travel update every sweep for a job moved later (the old `setCardPhase` wrote phase only; don't reintroduce it). **The reschedule card refresh runs per-occurrence, ABOVE the series-claim gate** in `handleAppointmentWrite` (unlike the push): the claim collapses an "all future" reschedule to one push per (employee, kind) and which sibling wins is nondeterministic, but the card is per-occurrence, so each sibling's own trigger must refresh its own card — `updateLiveActivity` is a cheap marker-read no-op for any occurrence that isn't the live card, and a deactivated employee has no marker/tokens so it can't resurrect a card (no `delivered > 0` guard needed there). **The ActivityAttributes type MUST be named exactly `LiveActivitiesAppAttributes`** (renamed from `JobActivityAttributes` 2026-07-19): the `live_activities` Flutter plugin registers the push-to-start AND per-activity update-token streams against `Activity<LiveActivitiesAppAttributes>` — a type of that exact name — so the device token the server pushes to only resolves when the name agrees in three places: the widget struct, the widget's `ActivityConfiguration(for:)`, and the server's `ATTRIBUTES_TYPE` (`live_activity_utils.js`). Rename any one and every push-to-start/update/end fails silently (degrades to the plain `leaveNow` push). Because the plugin (linked into Runner) owns token observation against its own copy of that type, the widget's `LiveActivitiesAppAttributes.swift` lives ONLY in the ScheduleWidget extension target — **do NOT add it to the Runner target** (the plugin, not app-native code, drives `pushToStartTokenUpdates`). **Xcode integration landed 2026-07-19** — the `WidgetBundle` `@main` hosts `JobLiveActivity` and the whole `ios/ScheduleWidget/` group builds clean at the new iOS 18.0 floor (the earlier "stay at 15.0, no bump" plan was superseded — the Directions button's returnable `OpenURLIntent` is iOS 18+, so the app moved to 18; every Live Activity path is still `@available(iOS 17.2, *)`-gated internally). `APNS_AUTH_KEY`/`APNS_KEY_ID`/`APNS_TEAM_ID` now exist in Secret Manager (created 2026-07-19), so a deploy no longer fails at secret binding. **Deployed to prod + card-start verified on device 2026-07-20** (via the sandbox fallback above; the missing `firestore:indexes` — see below — were the reason the first attempts produced only the push and no card, exactly as this file warned). **Only the two functions that bind `APNS_SECRETS` may read them** — `notifications.js` splits `liveDeps()` (no `apnsAuth`) from `liveActivityDeps()` (with it), because reading a secret param a function didn't bind logs a "No value found for secret parameter" warning on *every* invocation; the digest and overdue sweeps are Firestore-only and must keep using `liveDeps()`. Device-side capability (iOS 17.2+, ActivityKit available, Live Activities not switched off in iOS Settings) is probed in exactly one place — `LiveActivityRegistrationController.canHostCards()`, which never throws — and backs both `_ensurePlugin()` and the Settings row's `liveActivitySupportedProvider`; don't re-probe the plugin anywhere else. **The user's opt-out cannot be a local flag alone:** the card is *push-started* by the server, so `liveActivityEnabledProvider` (SharedPreferences, device-local, **default on**) only stops a later `sync()` from re-registering — the Settings toggle itself must call `unregister()` to end the live card and delete this device's token rows. `unregister()` deletes the push-to-start row **by kind, via query** (`deleteTokensOfKind`) and re-resolves the users-doc id when `_docId` is unset — the row's doc id IS a token this session may never have seen, and a cold start with the preference already off returns from `_syncGuarded` before `_docId` is set. A cold-start `sync()` MUST `await` the preference's `ready` future before acting on it, or the optimistic `true` default silently re-registers an opted-out device. Two **composite indexes are what make the feature work at all** — `liveActivityTokens` `(kind, employeeDocId)` at COLLECTION_GROUP scope and `liveActivityCards` `(phase, startTime)`; without them every registry query fails `FAILED_PRECONDITION`, the best-effort catch swallows it, and the card silently never appears. Deploy `firestore:indexes` with the functions. Mac runbook + device checklist: `ios/ScheduleWidget/LIVE_ACTIVITY_README.md`.
  - **Siri App Intents snapshot** (`features/siri` + `ios/SiriIntents`, iOS-only, **Phases 1–3: Dart + Swift landed 2026-07-19; the `SiriIntents` App Intents extension target was created + embedded in Runner 2026-07-19 and builds clean (bundle id `net.vogas.scheduling.SiriIntents`, entitlements `SiriIntentsExtension.entitlements` sharing the App Group, iOS 18.0). Phase-1 read intents (count / today / next), Phase-2 date intents (`TomorrowScheduleIntent` deterministic, `DayScheduleIntent` for any in-window day), and the Phase-3 `NthAppointmentIntent` ("read a specific appointment" → Siri prompts for a position) are all code-complete and pass the App Intents metadata compiler; on-device Siri phrase verification still pending — see `ios/SiriIntents/README.md`. Phases 2–3 added NO Dart/schema change (the snapshot already carries all 8 buckets). Note: a `Date` OR `Int` parameter cannot be interpolated into a spoken App Shortcut phrase (Siri only allows AppEnum/AppEntity there), so `DayScheduleIntent` and `NthAppointmentIntent` carry no such value in their phrases and Siri resolves it via its own locale-aware follow-up prompt ("For what day?" / "Which appointment?") — this prompt→answer is the only in-session multi-turn App Intents supports (there is no free-form "and tomorrow?" session), so don't "fix" it into a phrase parameter. A new `.swift` in `ios/SiriIntents/` must be hand-added to the target in `project.pbxproj` (all four sections)**): `ScheduleSnapshotService` writes a **today + 7 days** payload into the *same* App Group `group.net.vogas.scheduling` under a **separate key `schedule_snapshot`** (the widget's `schedulePayload` is untouched; the snapshot deliberately does NOT call `HomeWidget.updateWidget` — nothing renders it). Role-aware: employees get `myAppointmentsProvider`, admins the business-wide `appointmentsInRangeProvider`. Both off-screen schedule mirrors (this and the home-screen widget) resolve *who* they're for through the single `activeUserIdentityProvider` (`features/auth/application/active_user_identity_provider.dart` — active-status gate, employee-or-admin, `retryAsync(findUserByUid)` for the post-sign-in token lag); it returns `(role, docId)` and returning null is what wipes both mirrors on sign-out. Route any new mirror through it rather than re-deriving the identity. **Both fetch the SAME window, `AppointmentDateRange.forMirrors(today)`** (2026-08-08): they ask the same `myAppointmentsProvider` family, which is keyed by range VALUE, and both are held open for the whole session by `AppSyncListeners` — so two different windows meant two permanent Firestore listeners per signed-in employee, one a strict subset of the other. `buildWidgetPayload` re-scopes to today/tomorrow in Dart regardless, so the wider list feeds it unchanged; never narrow one mirror's range on its own. `mirrorLookaheadDays` owns the length and `scheduleSnapshotLookaheadDays` is that value. Both must also `ref.watch(currentDayProvider)` (`core/utils/`) for their day bucketing instead of a bare `DateTime.now()` — their appointment streams only re-emit on a write, so an app resident across midnight otherwise keeps publishing yesterday's buckets and Siri answers "no appointments today" while jobs exist. `buildScheduleSnapshot` (`siri/domain/schedule_snapshot.dart`) and the Swift `ScheduleSnapshot.swift` decoder are hand-mirrored — change one, change both, and bump `version` on both sides of a schema change. Cancelled visits and **records with a null/empty `id` are dropped at build** (Phase-4 write actions resolve their target by that id). **Sign-out wipes the snapshot implicitly** — `scheduleSnapshotProvider` emits `data(null)` and `AppSyncListeners._snapshotSync` (`core/app/app_sync_listeners.dart`) calls `clearSnapshot()`; don't add an explicit sign-out clear (same contract as the widget). The App Group stays readable while the device is locked, so the payload carries **only the fields the intents speak** (client name, times, address, status) — never notes, phone, or pictures. **Phases 1–3 keep the extension Firebase-free and network-free**; Phase 4 breaks that deliberately as its own reviewed increment (it's also blocked on App Attest's bundle-ID binding — see the implementation plan).
  - **Notification permission recovery:** Settings has a Notifications row (`notificationAuthStatusProvider`, read WITHOUT prompting) — `notDetermined` re-shows the one-time OS prompt; any other non-granted state (or a granted tap) opens system Settings, since iOS never re-shows the dialog once answered. On return (app-lifecycle `resumed`) it invalidates the status provider and re-runs `PushRegistrationController.sync()` so a just-enabled device actually stores its token.
- **Wave Accounting** (`functions/wave/*`): admin callables (`waveBootstrap`,
  `waveImportCustomers` — App Check + `assertAdmin` + `enforceDurableRateLimit`).
  **`waveImportCustomers` is a TWO-WAY sync despite its name** (2026-08-04): it
  drains the outbox to Wave via `drainForSync` and only then imports. The name
  is historical and **stays** — renaming a deployed callable deletes the one
  every shipped build calls, so the cost of the accurate name is a broken
  "Sync with Wave" button on every phone until it updates. This outlived the
  `#compat-1.37.1` shim it was first tagged with: the constraint was never
  specific to 1.37.1.
  **AN IMPORT MUST NEVER TOUCH A CLIENT WITH AN UN-PUSHED OUTBOX JOB.** This is
  the invariant, and push-before-pull is only half of it. `importCustomers`
  overwrites every mapped field of a linked client with Wave's values AND
  stamps `wave.lastSyncedHash` from them — so a queued edit isn't merely
  overwritten, it is marked *synced*: the pending job then hashes the clobbered
  doc, matches, returns `noop`, and the edit is gone with the row reading
  "synced" and nothing logged. Ordering alone does not prevent it, because the
  drain is bounded AND its query only takes jobs already due — a job backed off
  after a transient Wave error is invisible to the drain and still live
  milliseconds later. Every caller of `importCustomers` therefore passes
  `skipClientIds` from **`listOutstandingClientIds`** (`worker.js`, covers
  `queued` AND `inflight`); the param is injected rather than read inside
  `customers.js` because `worker.js` already requires that module and reaching
  back would close a cycle. Both callers need it — the daily
  the daily `runWaveDaily` most of all, since it runs unattended.
  **The import is hash-gated, and `updated` counts REAL changes only.** It
  skips any linked client whose stored `wave.lastSyncedHash` already equals
  `mappedFieldsHash(fromWaveCustomer(node))` (counted as `skippedUnchanged`).
  That equality is exact, not a heuristic — both sides hash the same
  `toWaveCustomerInput` projection, which is the identity
  `shouldEnqueueClientWrite`'s Rule 2 already depends on to stop an import
  feeding every client back into the outbox. Without the gate the import
  re-wrote all ~650 clients every run: ~650 writes AND ~650
  `waveUpsertCustomer` invocations per press that all conclude "nothing to
  do", and the app reported "650 clients updated in the app" after a sync that
  changed nothing. **The `hasCreatedAt` half of the condition is
  load-bearing** — the update branch is the only thing that backfills a missing
  `createdAt`, and the clients list orders by it, so skipping a doc without one
  hides it from the list forever.
  **The import is also a DELTA when `since` is supplied** (2026-08-04): Wave
  filters `modifiedAtAfter` server-side, so it returns only changed customers.
  `LIST_CUSTOMERS_SINCE` is a **separate document** from `LIST_CUSTOMERS`, not
  one query with a nullable variable — a server reading an omitted variable as
  `modifiedAtAfter: null` would give a full import that imports nothing and
  reports success. **`importCustomers` stays stateless about the watermark; the
  whole read → decide → import → advance sequence has ONE owner,
  `importWithWatermark` (`wave/sync_run.js`)**, called by both the interactive
  sync and the unattended daily import. It was hand-copied in both before, and
  each omission fails silently in its own direction; the unattended copy — the
  one where a mistake is invisible — was the untested one. The decisions
  themselves are the pure `resolveImportWindow` / `watermarkPatch`, in
  `wave/import_schedule.js` beside `isImportDue` because the two cadences
  interact.
  **THE WATERMARK ADVANCES ONLY OVER A WINDOW THAT WAS FULLY COVERED.** Three
  things break it, all silent, all handled: a throw (leaves both stamps, next
  run redoes the window), a run with `skippedPending > 0` (those clients were
  deliberately protected from the clobber, so their Wave-side change would be
  invisible to every later delta — the watermark is HELD), and an unknown
  `skippedPending` (treated as not-covered, since holding is free and advancing
  wrongly loses data). It is the run's START minus an overlap, never its end.
  **A delta-only failure retries once as a FULL import** — without that, a bad
  `modifiedAtAfter` makes every interactive sync fail identically until the
  7-day resync ages the window out, and only the admin-facing path breaks. **A
  failed watermark WRITE is logged, not thrown**: the import already committed,
  and failing there would report a successful sync as an error and discard the
  push counts with it.
  A periodic full pass runs every 7 days: not for deletes
  (the import never deletes a local client) but as the backstop for `modifiedAt`
  itself, which we trust Wave to bump and cannot verify. That interval is
  shorter than both cadences, so the SCHEDULED import normally goes full every
  time and the delta mostly benefits the interactive sync — accepted, since a
  weekly job paying 7 Wave pages costs nothing. `buildWaveIdIndex` is
  built lazily so a no-op delta costs zero Firestore reads. Full detail:
  `docs/CLOUD_FUNCTIONS.md`.
  **Wave rejects INLINE STRING ARGUMENTS — every string must travel as a
  GraphQL variable** (`GRAPHQL_VALIDATION_FAILED: Inline argument of type
  String is not allowed`). Confirmed against the live API 2026-08-04. Inline
  `Int`/`Boolean` are accepted; only `String` is refused. Every query in
  `wave/customers.js` already parameterises, so this only bites a query
  written by hand — write the variable in from the start rather than
  discovering it as a 400.
  The push is best-effort (bounded by `SYNC_PUSH_BATCH_LIMIT` /
  `SYNC_PUSH_BUDGET_MS`, with the `waveUpsertCustomer` trigger having already
  pushed each edit as it was made and the daily sweep retrying the rest) and its
  failure must never fail the import. Those two bounds are sized against
  `kWaveSyncTimeoutSeconds` (`wave_service.dart`, hand-mirrored) and NOT
  against the 300 s function timeout: a callable cannot be cancelled, so past
  the client's deadline the admin has already been told the sync failed and
  will tap again.
  **A zero counter must never be reported as success.** The response carries
  `pushedPending` (a `count()` taken AFTER the drain), `pushedFailed`
  (`drained.dead` — dead-lettered jobs are not `queued`, so the pending count
  misses them and they never retry) and `pushIncomplete` (the drain or the
  count threw). Without all three, a broken push, a bounded push and an empty
  queue produce identical zeros, and the app says "everything was already up to
  date" while edits sit undelivered. Response fields are additive only.
  `drainQueue`'s `created`/`updated`
  counters come from `tallyUpsert`, folded from each `upsertCustomer` status
  and incremented only where `done` is (a committed outcome), so a superseded
  job can't be counted in two drains; `linked` counts as an **update**, since
  that path patches a customer a crashed attempt already created.
  the read-only `waveGetConnection` (admin + App Check; no secret, but
  durably rate-limited — `wave-connection`, 60/hour, added once it stopped
  being a single-document read: it also runs two `count()` aggregates on
  `waveSyncQueue` so Settings can show the outbox depth), `waveSetImportSchedule`
  (admin + App Check; no secret, but durably rate-limited like every other
  admin write callable — `wave-schedule`, 20/hour — writes the `importSchedule`
  field on `wave/connection`), `waveRetryFailedJobs` (admin + App Check + the
  `WAVE_FULL_ACCESS_TOKEN` secret + durable rate limit — `wave-retry`,
  10/hour — admin-only recovery for dead-lettered outbox jobs: `requeueDeadJobs`
  puts them back in the queue, then a best-effort drain pushes them so the
  admin sees the result of the press rather than waiting for the next client
  edit or the daily sweep. **The requeue runs its per-job transactions in
  `REQUEUE_CHUNK`-sized concurrent batches, not one at a time** — the shape
  that produces dead jobs is a bulk backfill, a few hundred of them, and a
  serial round trip each spent 12-20 s of the callable's budget before the
  drain behind it had run at all. The transactions touch distinct documents,
  so there is nothing to serialize for, and the per-job catch still keeps one
  stubborn job from aborting the recovery.
  **The response carries `failed` (`drained.dead`) beside `pushed`, and it is
  not optional** (2026-08-15): the very reason this action is manual — a job
  that died on a `WaveValidationError` dies again — means the drain behind the
  requeue routinely dead-letters it a SECOND time inside the same call, leaving
  the outbox's dead count exactly where it was. Reporting only `requeued` made
  the app announce "1 client queued for Wave again" as a success over a
  Settings row still reading "1 client failed to sync", which is the same
  silence `pushedFailed` was added to the sync response to end. Null-is-unknown
  like `pushed` — the drain threw, or never ran — and the app must never render
  that as "nothing failed"), the `waveUpsertCustomer`
  `clients` trigger, and the daily `runWaveDaily` — which is NOT its own
  export: `waveScheduledImport` was deleted 2026-08-13 and this now rides
  `sendDailyJobDigest` as an isolated rider (server-triggered, so no App
  Check/rate limit).
  **THE PUSH IS EVENT-DRIVEN, NOT POLLED** (2026-08-13, owner call). The
  `waveSyncWorker` scheduler — `every 5 minutes`, drain the `waveSyncQueue`
  outbox — is **DELETED**. `waveUpsertCustomer` now enqueues the job AND
  drains it in the same invocation, so an edit reaches Wave in seconds rather
  than up to five minutes, an idle day costs zero invocations instead of 288,
  and one of the six Cloud Scheduler jobs (only 3 are free per billing account)
  goes away. Two properties there are load-bearing and must not be
  "simplified": the drain is wrapped so it **cannot throw** — the job is
  already durably queued, so a failure is a delay, not a loss, and a throw
  would re-run the whole handler under `retry: true` for something a retry
  cannot fix — and it sits **below** the `shouldEnqueueClientWrite` gate, which
  is what stops `upsertCustomer`'s own `wave.*` write-back from re-entering the
  drain in a cycle (the hash is unchanged by that write, so the re-fire returns
  at the top).
  **`runWaveDaily` therefore drains BEFORE its due check, unconditionally.**
  That is the safety net for the two states an event-driven push structurally
  cannot catch: a job sitting on its `nextAttemptAt` backoff, and a job left
  `inflight` by a dead instance (reclaimed by `drainQueue`'s lease pass) —
  neither produces a client write to ride on. It must run even when
  `importSchedule` is `off`, which is the DEFAULT and governs the PULL only;
  gating the push on it would mean a default install never pushes
  automatically at all. It also re-establishes push-before-pull on the
  unattended path, and reads `skipClientIds` AFTER the drain. Pinned by
  `wave_callables.test.js` ("pushes without a poll" / "is the drain safety
  net"). Don't reintroduce a polling worker to "fix" a sync latency
  complaint — check the trigger's drain and the daily sweep first.
  `importCustomers` still only re-runs when the configured cadence is due.
  **Auto-import cadence:** `importSchedule` on `wave/connection` is one of
  `off`/`weekly`/`monthly` (`WaveImportSchedule` enum client-side; `SCHEDULE_VALUES`
  server-side). The `isImportDue` helper (`wave/import_schedule.js`, pure/jest-testable)
  treats **off or any unknown value as never-run**; a due import stamps
  `lastAutoImportAt` and a failed one leaves it unchanged (retried next day). The full-access
  Wave token lives in Secret Manager (`WAVE_FULL_ACCESS_TOKEN`) only — **no
  OAuth**. The Connect target is chosen **server-side**: `waveBootstrap` resolves
  the business from the `WAVE_BUSINESS_NAME` secret when the client sends no
  `businessId`/`businessName`, so the business name never ships in the app and
  `_connect()` passes no selector. (Business resolution is fully server-side via
  the internal `listBusinesses` helper — there is no `waveListBusinesses`
  callable; the in-app business picker was removed.) The app
  cannot read the rules-locked `wave` collection directly, so the Settings Wave
  section calls `waveGetConnection` on mount to show persistent "Connected to X"
  status — this is the **only** Wave read path; never read the collection
  client-side. **Import invariant:** `importCustomers` MUST write
  `createdAt`/`updatedAt` on every client doc (new docs get both; re-runs backfill
  `createdAt` only when missing) — the clients list/search order by `createdAt`
  and Firestore **excludes any doc missing the orderBy field**, so a timestampless
  import is silently invisible in-app. **Outbox invariant:** the job claim AND the
  outcome write are both transactional — `commitOutcome` writes
  `done`/`queued`/`dead` only while the job is still `inflight` with the same
  `claimedAt`, so a client edit that re-enqueues mid-dispatch isn't clobbered.
  The reclaim pass enforces the same rule with a single read+write transaction
  (it has no Wave call to span), so neither path may ever do an unconditional
  `update`.
  **A `waveCustomerId` pointing at a customer that no longer exists in Wave
  must RELINK, never dead-letter** (2026-08-15, found in prod). Wave reports a
  missing `customerPatch` target as a top-level GraphQL error — so it arrives
  as `WaveApiError('graphql')`, which the retry taxonomy correctly calls
  non-retryable — or, equivalently, as a `NOT_FOUND` **inputError**. Both
  dead-lettered, and both were unrecoverable in a way ordinary dead-lettering
  is not: **the offending value is STORED on the doc**, so every later push and
  every "Retry failed" press re-sent the same missing id and failed
  identically. Two clients sat like that with the Settings row reading
  "2 clients failed to sync" and no way to clear it. `upsertCustomer` now
  routes both shapes (`isStaleCustomerLink` / `hasNotFoundInputError`,
  `wave/customers.js`) into the create path with the identity search FORCED on
  — the same route a crashed create takes, and the reason a spurious NOT_FOUND
  relinks rather than minting a duplicate customer. **`writeSyncSuccess` needed
  the matching exception**: it sets `waveCustomerId` only on a doc that is
  still unlinked, which is what keeps it idempotent, so the healed link would
  never have persisted. `replacesLink` is that exception and is conditioned on
  the stale id still being the one on the doc — a link established concurrently
  is newer and unproven-dead, so it wins. Keep the predicates narrow
  (a structured `NOT_FOUND`, never a text match on Wave's message): this is the
  one path here that REWRITES a client's Wave identity.
  **Mapper invariant: NEVER send a value outside a Wave ENUM's vocabulary —
  omit the field instead** (2026-08-15). `provinceCode` and `countryCode` are
  GraphQL enums, so a value they don't know is NOT an `inputErrors` entry the
  worker can report against that one field: GraphQL refuses to coerce the whole
  `$input` variable and answers with a **top-level** error, which arrives as
  `WaveApiError(graphql)`, is non-retryable by design, and dead-letters the job.
  Nothing recovers it — "Retry failed" re-sends the identical payload into the
  identical refusal — so one stray address field costs that client every future
  sync, permanently and silently. `toProvinceCode`/`toCountryCode`
  (`wave/mappers.js`) therefore test MEMBERSHIP against `ISO_COUNTRY_CODES` and
  `SUBDIVISION_CODES` rather than shape: both doc blocks always claimed they
  "omit rather than guess", but `/^[A-Z]{2}$/` accepts any two letters, so a
  province typed into the country box ("ON", "QC") shipped as a country code.
  The province prefix follows the client's **resolved country** too — it was an
  unconditional `CA-`, so a New York client was sent as `CA-NY`, a subdivision
  of nowhere. Resolve country BEFORE province in `toWaveCustomerInput`; the
  province reads against it. Apply the same rule to any new enum-typed field.
  **And `sanitizeError` is not a diagnostic** — it flattens every transport
  failure to `WaveApiError(graphql)`, which is correct for the job's
  `lastError` and the client's `wave.syncError` (the app reads those), but it
  left the REASON recorded nowhere in the system. `describeWaveError`
  (`wave/retry_policy.js`) is the log-only companion the dead-letter
  `logger.error` carries as `errorDetail`: GraphQL `extensions.code`, the error
  `path` and the `at "input.address.countryCode"` field fragment, plus
  `Expected type`. It takes **only** the quoted run following `at` — the same
  message quotes the offending VALUE immediately before it, and that is
  customer data. Keep new detail extraction on that side of the line.

**Firestore TTL policies are declared in `firestore.indexes.json`**, as
`fieldOverrides` entries with `"ttl": true` on `expiresAt`. They are NOT
console-only state: `firebase deploy --only firestore:indexes` treats any prod
field override missing from that file as drift and DELETES it (this removed all
5 live TTL policies once, on 2026-07-21 — never pass `--force` to a deploy).
Keep real single-field indexes on those entries rather than the Firebase docs'
`"indexes": []` example — `live_activity_registry.js` `_pruneExpired` queries
`.where("expiresAt", "<=", now)`, and the token sweep is a **collection-group**
query, so `liveActivityTokens.expiresAt` needs a `COLLECTION_GROUP`-scoped index
or the reaper fails `FAILED_PRECONDITION` into a swallowed no-op.

**`fieldOverrides` also carries the single-field index EXEMPTIONS** (added
2026-08-13, entries with `"indexes": []`). Firestore indexes every field of
every document ascending AND descending by default, and every element of an
array — including each subfield of every map inside it. On `appointments` that
meant `pictures` alone generating four indexed subfields per photo per doc,
forever, for a field nothing has ever queried; the free-text and denormalized
fields (`title`, `notes`, `materialsNeeded`, `address`, `clientName`,
`clientPhone`, `employeeNames`, `seriesOpId`) and the `clients` name/address
family plus `contacts` are the same shape. Entity search is matched in **Dart**
over a bounded window by design (see the root `CLAUDE.md`), so none of these is
ever a query constraint — the exemptions cut index storage and shorten every
write without changing a single query. **Adding a `where`/`orderBy` on an
exempted field means removing its override first**, and the rebuild is not
instant; check this list before writing a new query rather than debugging a
`FAILED_PRECONDITION`. Deliberately NOT exempted, though nothing queries them
today: `createdAt`/`updatedAt` (the fields you reach for when investigating
something in the console) and the low-cardinality flags.

**A TTL policy only deletes docs that HAVE the field**, exactly like the
`where("expiresAt", ...)` sweeps — Firestore excludes documents missing the
filter field. So any client-writable TTL field must be **required** in the
rules, not merely bounded when present, or a modified client can mint rows no
reaper can ever reach (see the `liveActivityTokens` rule).

**Firestore TTL policies must use expiration offset `0`.** Every collection that
writes an `expiresAt` (`appointmentReminders`, `appointmentOverduePrompts`,
`appointmentSeriesNotices`, `liveActivityTokens`, `liveActivityCards`,
`rateLimits`) stores
the *absolute* deletion instant — the lifetime is already baked in by
`LEDGER_TTL_MS` / `CARD_TTL_MS` / the limiter window. The
console's "expiration offset" ADDS to that value, so any non-zero offset
silently multiplies retention (the ledgers ran at ~14 days instead of 7 until
2026-07-20). An offset is **immutable once set**: correcting one means delete →
wait for the policy to disappear from the list → recreate, or the create fails
`400: Cannot modify TTL offset`. A policy can only be created for a collection
group that already holds documents. TTL is housekeeping only — every one of
these is also swept in-code, so a missing policy is never a correctness bug.

Release runbook (ordering, old-build compatibility, rollback, deploy log):
`docs/DEPLOYMENT.md`.

Deploy: `firebase deploy --only functions,firestore:rules,firestore:indexes,storage`
(drop `firestore:indexes` only when `firestore.indexes.json` is unchanged — a
query whose index is missing fails `FAILED_PRECONDITION`, which best-effort
callers swallow into a silent no-op.)
(`storage:rules` is **not** a valid deploy target — use `storage`.)
Always run `cd functions && npm run lint` before deploying (Google ESLint, 80-char line limit).

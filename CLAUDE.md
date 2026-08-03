# CLAUDE.md

Flutter app (Dart `^3.10.7`) for managing appointments, clients, and employees.
Backend: Firebase (Auth, Firestore, Storage, App Check). Targets Android and iOS.
**Ships to the App Store ONLY (decision 2026-07-08).** Android is a dev/test
target on this Windows box and is never published to Play — keep `android/`
and the Android Firebase app (they're the local dev harness; deleting them
would leave no runnable platform on this machine), but don't chase
Play-release work (keystore, Data Safety, Play Integrity).

iOS notes live in `ios/CLAUDE.md` (loads when working under `ios/`) — SPM-only
(there is no Podfile and never will be), iOS 18.0 deployment floor, App Attest,
the Crashlytics dSYM run-script phases, and the `homeWidget` deep-link param.
Since P4b a real `app_links` dispatcher exists (`lib/core/deep_links/`), but the
`homeWidget` param and the `home_widget` tap channel are **both still live** and
retire together — the dispatcher skips those URIs rather than replacing them.
**Do NOT re-run `flutterfire configure`** — `lib/firebase_options.dart` already
builds the iOS options from `dev/.env`; re-running it rewrites the file into the
literal-values style and breaks the env-based setup.

## Commands

```bash
flutter analyze 2>&1 | grep -E "error -|warning -"   # the baseline is 0 issues — any lint you see is yours
```

## Required environment

`dev/.env` (gitignored, bundled as asset). 8 keys: `FIREBASE_API_KEY`,
`APP_ID`, `MESSAGING_SENDER_ID`, `PROJECT_ID`, `STORAGE_BUCKET`, plus the iOS
pair `IOS_API_KEY`, `IOS_APP_ID` (read in `lib/firebase_options.dart` to build
the iOS `FirebaseOptions`), plus `IOS_MAPS_API_KEY` (iOS client Google Maps
key, parsed natively by `AppDelegate.swift`). Android also needs
`google-services.json` plus `MAPS_API_KEY` in `android/local.properties`
(gitignored, dev harness only). `IOS_MAPS_API_KEY` and `MAPS_API_KEY` are
RESTRICTED CLIENT keys — distinct from the server-side Secret-Manager
`GOOGLE_MAP_API_KEY`, which must never ship in the app.

- **`dev/.env` holds Firebase client config plus RESTRICTED client keys (e.g. `IOS_MAPS_API_KEY`) only.** It's an asset bundled into the APK/AAB, so anything in it ships in the binary — restrict those keys app-side (bundle ID / package + API restrictions) in the Google Cloud Console. Server-side or unrestricted keys (Stripe, OpenAI, admin tokens, `GOOGLE_MAP_API_KEY`) must live in Google Secret Manager and be read from a Cloud Function — never in `dev/.env`.

## Critical invariants

- **Auth:** Every signed-in user needs a Firestore `users` doc with matching
  `uid`, and it must be `active` — with ONE exception. `SplashScreen` signs out
  otherwise. Don't break this. Gate with `!employee.isActive` — `isDisabled`
  only matches `'disabled'`, so it misses `''` and any future status.
  **The exception is `invited` (P4c, 2026-08-02): it routes to
  `AccountSetupScreen` and KEEPS the session**, at both gates
  (`splash_controller.dart`, `sign_in_controller.dart`). The admin created that
  account with the shared starting password and this is the person's first
  sign-in — signing them out makes setup unreachable, since the credential they
  just used is the one it needs. The test is `employee.isInvited`, an **exact**
  match checked BEFORE the active gate, so an empty or unknown status still
  gets the old sign-out. Tests pin both halves.
- **Live account-deletion signal (kick-out) needs a populated→empty transition.**
  `isAccountDeletionSignal` (`account_status_provider.dart`) fires the runtime
  sign-out only when the current doc is a *settled* empty following a
  previously-populated one — so pass `previous` (the prior emission) from the
  `ref.listen` in `main.dart`. A first-seen empty doc is a bootstrap window
  (fresh-sign-in `uid == null` branch, or an invited account signed in before
  `redeemSignupCode` activates its doc), NOT a deletion. Never simplify back to
  `doc.isEmpty` alone, or invited employees get wrongly kicked out mid-activation
  (cold-start already-deleted accounts are caught earlier by `SplashScreen`).
- **Employee visibility:** Employees see only appointments where their doc id is
  in `employeeIds`. Apply this filter on any new appointment view.
- **Editing an appointment must preserve assignees not in the active picker.**
  The employee picker only shows active staff, so a disabled/removed assignee
  can't be deselected — saving must re-append original `employeeIds` not in the
  active set, or that staff is silently unassigned (which also changes who can
  see the visit). The merge itself is the pure, tested `mergeRetainedAssignees`
  (`calendar/domain/assignee_resolver.dart`) — route the retain logic through it.
  Resolve the active set the way `_enrichSelectedEmployees` does
  (cached `employeesStreamProvider` value, falling back to a fresh
  `watchEmployees().first`) — never trust a cold/empty stream value at save time,
  or every original assignee is wrongly retained and real deselections are undone.
- **Image validation:** Reject uploads where first 4 bytes aren't JPEG
  (`FF D8 FF`) or PNG (`89 50 4E`). Extension alone is not sufficient.
- **Image upload pipeline:** Single stage — `ImagePickerService` resizes +
  JPEG-compresses at pick time (`image_picker` `maxWidth/maxHeight: 1600`,
  `imageQuality: 70`); `ImageStorageService` then validates magic bytes and
  uploads. `ImageCompressService` was removed — don't reintroduce a second
  compression pass. Background dispatch via `AppointmentImageUploadService`
  after appointment save; the picker's temp files are deleted in a `finally`.
- **Offline photo-upload queue:** a failed/incomplete photo batch is persisted
  by `PendingUploadStore` (one JSON list under the SharedPreferences key
  `pending_photo_uploads`, entries pruned after 7 days) so uploads survive
  going offline. `AppointmentImageUploadService.drainPending()` retries the
  queue — it's reentrancy-guarded, re-queues the *unsent*
  paths on a transient failure (preserving `enqueuedAtMs` so a batch can't
  retry past the prune window), and `arrayUnion`-appends uploaded pictures so a
  concurrent edit or the batch's other half never clobbers them.
  **When the uploads land but the `arrayUnion` doc-link append itself throws
  transiently, the already-uploaded images are carried forward on the queue
  entry's `uploaded` field for an append-only retry — NOT re-uploaded (their
  local temp files are already gone), and NEVER dropped, or the Storage bytes
  orphan invisibly on the job.** That re-link stays idempotent because each
  carried image serializes its exact `uploadedAt` (ISO-8601 in the JSON,
  round-tripped by `AppointmentImage.fromMap`), so an append that actually
  committed server-side dedupes on the next pass. An entry with no paths AND no
  carried `uploaded` images is the only genuinely-empty one that drains away.
  **Staging and draining share ONE serialized path** (`drainPending`, guarded
  by `_draining` + `_pendingDrain`): a save that stages a batch does NOT upload
  it directly, because a listener-driven `drainPending()` firing in that window
  would load the just-added entry and upload it concurrently — and since
  `ImageStorageService` mints each file name from `DateTime.now()`, the two
  passes produce different storage paths that `arrayUnion` can't dedupe, so the
  photo lands twice. A request arriving mid-drain sets `_pendingDrain` so the
  in-flight pass repeats (coalesce, never drop).
  **`PendingUploadStore`'s mutations are serialized inside the store**
  (`_serialized`, one `_mutations` chain) — `add`/`remove`/`prune` are each
  `load()` → mutate → `_save()` over ONE SharedPreferences key, so two
  overlapping mutations both read the same list and the second save erases the
  first's change: a save staging a batch while a drain removed a finished one
  wrote `[E1, E2]` then `[]`, stranding E2's files with no queue entry and no
  failure notice. Keep new mutating methods inside `_serialized`, and never
  "simplify" it away by serializing at the call site — the requeue inside a
  drain is a caller too. `AppSyncListeners`
  (`core/app/app_sync_listeners.dart`, registered from `main.dart`)
  drives the drain on the offline→online flip AND when the account doc first
  arrives (Storage rules need an authed user — a signed-out drain just
  re-queues); both transitions are covered by
  `test/core/app/app_sync_listeners_test.dart`. Method-channel plugin —
  device-only verification of the upload itself.
- **Offline write guard:** the appointment/client submit controllers
  (`add_event`, `event_details`, `client_form`) fail fast when
  `ref.read(isOfflineProvider)` is true by returning a fabricated
  `SocketException('offline')` **before** the in-flight flag is set; the widget
  maps it to the offline notice via `composeErrorNotice`/`error_cause.dart`
  (which keys on the `SocketException` *type*, so the message string is cosmetic).
  An awaited Firestore write only resolves on server ack, so without this Save
  spins until reconnect. Deliberate asymmetry: entity writes fail fast offline
  while photos retry via the queue above. `persistenceEnabled: true` is pinned in
  `main()` (serves cached reads) — don't remove it.
- **App Check:** `FirebaseAppCheck.instance.activate()` in `main()`. Do not remove.
- **Appointment status allowlist:** The lifecycle is `pending` →
  `in_progress` → `done`, plus `cancelled` (set by the separate Cancel action).
  These four are the ONLY valid *stored* values — enforced by
  `isValidAppointmentStatus` in `firestore.rules` and `_allowedStatuses` in
  `firebase_appointments_repository.dart`. New appointments must be created
  with `status: 'pending'`. **`AppointmentStatus.overdue` is a display-only,
  time-derived state — NEVER stored, NEVER in the picker.** `displayStatus`
  (`appointment_record.dart`) maps a non-terminal visit to `in_progress` while
  now is within [start, end] and to `overdue` once `endTime` has passed.
  **That ladder has exactly ONE owner: `AppointmentRecord.displayStatusAt(now)`;
  `displayStatus` is `displayStatusAt(DateTime.now())` and
  `DashboardAggregator.displayStatusAt` delegates to it.** The dashboard used to
  carry a hand-copied "mirror" of it and had already drifted — it was missing
  the `isPersonal` carve-out, so a personal block past its end read "Scheduled"
  on its card and sat under the dashboard's Attention list as *overdue*, where
  an admin had no affordance to clear it (personal jobs have no mark-done
  flow). Never re-copy the ladder; add clock-derived rules to
  `displayStatusAt` only. The
  card/tile and the read-only detail header render `displayStatus`, but the edit
  picker and all writes seed from the real stored `status` (so `overdue` can't
  leak into a write). Don't add `overdue` to `appointmentValues` or the
  allowlist; reading `AppointmentStatus.overdue.raw` **throws** on purpose so a
  stray write path fails loudly at the source instead of emitting an
  off-allowlist value that the rules reject with an opaque `permission-denied`. (`confirmed` was retired 2026-07-09 when the picker
  collapsed to three states; `done` is labeled "Complete" in the UI. Account
  statuses `active`/`invited`/`disabled` live in the separate `UserStatus` enum
  — `shared/widgets/feedback/user_status_chip.dart` — not `AppointmentStatus`.)
  **Any edit that re-serializes a stored record must normalize its status
  through `AppointmentStatus.storedRaw(status)` before writing** — legacy
  `confirmed`/unknown docs exist, an unchanged status is re-written verbatim,
  and the rules reject anything off the allowlist (a raw write would fail the
  whole save/series-update with `permission-denied`). Use `storedRaw`, never
  `fromRaw(x).raw`: it maps legacy/unknown AND the display-only `overdue` onto
  `pending`, so it can't throw the way a bare `.raw` does. Done at the seed in
  `event_details_controller`, per-sibling in `appointment_series_editor`'s
  `propagate`, and in the Siri snapshot builder. `UserStatus.fromRaw` is the
  matching mapper for account statuses (unknown/empty → `invited`).
- **Employee "Mark as complete" gates on `hasStarted`, not on "is today".**
  `!appointment.startTime.isAfter(now)` in `details_view_body.dart` — the edit
  form's status picker is admin-only, so an employee who misses the button
  before midnight (or is on day 2+ of a multi-day visit) has no other way to
  close the job while the server keeps sending "job finished?" nudges. The
  rules allow an assignee to write `status:'done'` with no date restriction.
- **Admin-only appointment actions are gated by an explicit `showActions`.**
  `showEventDetails(..., showActions:)` is a REQUIRED param, and
  `AppointmentTile` / `EventDetailsSheet` / `EventDetailsView` all default it
  **CLOSED** (`false`). A default of `true` silently showed employees the
  Edit/Cancel/Delete affordances, which the rules then reject with an opaque
  `permission-denied`. Pass the caller's resolved role; never re-add a `true`
  default. (Rules remain the real gate — this is defense-in-depth plus UX.)
- **Personal jobs (`isPersonal`, added 2026-07-31) carry no client and no
  address.** The switch at the top of the form's WHO section is on BOTH the add
  and edit flows (unlike the template chips), because the flag is stored and
  has to be reversible. Turning it on hides the client picker and the address
  field, clears their controllers, and drops `clientRequired` from
  `AppointmentFormValidator` — **the assignees stay required**, they are who the
  block is for and who can see it. Both save paths write `clientId`/
  `clientName`/`clientPhone`/`address` as **empty strings**, including when an
  existing client visit is converted, so a hidden field can never keep a stale
  value the UI no longer shows. Everything that speaks a client name falls back
  to the **title**: the card and the detail row say "Personal"
  (`calendar_personal`), the widget and Siri decoders already fell back to
  `title`, and `_who` in `functions/notification_messages.js` now does too
  (`_contextFor` therefore has to keep passing `title` through).
  **`live_activity_utils.js` carries its OWN `_who` with the same fallback, and
  it is not optional:** a *timed* personal job is still a travel candidate, so
  the `leaveNow` push and the Lock Screen card describe the same trip at the
  same moment — the card read "Client"/"un client" while the push read
  "Dentist" until `title` was threaded through. Every `ctx` passed to
  `startLiveActivity`/`updateLiveActivity`/`endLiveActivity` (the sweep, the
  on-site flip, the terminal end, the reschedule hook) must carry `title`, and
  `_stateFor` must forward it into `buildContentState` — the state builder
  field-picks its `ctx`, so a dropped field fails silently back to "Client".
  `propagateClientEdits` can't touch these — it
  queries by `clientId`, which is empty. Also dropped from a personal job: the
  template chips, the repeat picker, materials and photos. The **title is
  optional** there and an unnamed one saves as "Personal" — substituted in the
  widget layer (both sheets), which is where `l10n` lives. The edit form shows
  the switch **only when the job is already personal** (`onPersonalChanged: null`
  otherwise), so an ordinary client visit can't be converted mid-life. Turning
  it on clears the hidden text controllers and, in the ADD flow only, resets
  `repeat` — the edit flow keeps its repeat, where clearing it would rewrite a
  live series.
- **An all-day block (`isAllDay`) stores real instants**, midnight → 23:59, so
  every range query, `orderBy('startTime')` and sweep keeps working unchanged —
  the flag only changes how it is SHOWN (`allDaySpan` builds the pair).
  **Neither save path may re-derive that pair itself** — both the add and edit
  controllers resolve their instants through the one `appointmentSpan(...)`
  helper beside `allDaySpan` (`calendar/domain/policies/appointment_form_validator.dart`),
  which picks the all-day span or the picked times. Hand-writing the ternary in
  a controller gives the convention three owners, and a change to it (23:59 →
  23:59:59, a DST-safe end) then lands on one save path and not the other.
  **`setPersonal(value: false)` MUST clear `isAllDay` too** (both controllers do
  — `isAllDay: value && state.isAllDay`): the all-day switch is rendered only
  for a personal job, so leaving the flag set saves a midnight–23:59 *client*
  visit with neither the switch nor the time rows on screen to correct it —
  unrepairable, skipped by `selectTravelCandidates`, and nagged by the overdue
  sweep (which gates on `isPersonal`, not `isAllDay`). **The validator's
  end-after-start check is likewise gated on `!isAllDay`**, not just on the
  times being non-null: times picked before the switch was flipped stay in
  state, so a stale equal pair otherwise fails Save against hidden rows with no
  visible error. Offered
  on personal jobs only, ON by default when no time has been picked, and it
  hides the start/end rows. The switch is the schedule `SheetPanel`'s first
  row — **that panel holds the whole of "when": all-day, date, start/end and
  the repeat rule**, which is a `SheetFieldRow` + `showAdaptiveActionSheet`
  rather than the standalone dropdown it used to be (owner call, 2026-07-31). `AppointmentCard` and the detail when-line render
  "All day" instead of "12:00 AM – 11:59 PM". A personal job also **never
  derives `in_progress`/`overdue`**: `displayStatus` returns its stored status
  (which reads "Scheduled"), and `selectOverdueCandidates` in
  `functions/notification_utils.js` skips `isPersonal` records for the same
  reason — "job finished?" is the wrong question for a dentist appointment.
  Keep those two in sync. **`isAllDay` is threaded through all four off-screen
  mirrors** (2026-07-31), and each one needs it for a different reason:
  - **Reminder sweep** — `selectTravelCandidates` (`functions/travel_utils.js`)
    skips all-day records. Without it the midnight start put the block inside
    the 90-min window at ~23:30 the night before and fired a "time to leave"
    push for something that has no departure time. A *timed* personal job keeps
    its reminder; only the all-day skip is new.
  - **Push/digest text** — `_contextFor` carries `isAllDay`, and
    `notification_messages.js` renders the date alone ("Wed, Jul 8") instead of
    "Wed, Jul 8, 12:00 a.m."; `_whoAt` joins with "·" rather than "at"/"à",
    since there is no clock time to sit after the preposition.
  - **Home-screen widget** — `isAllDay` is in the job JSON in BOTH hand-mirrored
    builders (`widget_sync_service.dart`, `widget_payload_utils.js`) and the
    Swift `Job` decodes it as `Bool?` so a pre-existing payload still parses.
    `timeLabel` says "All day". **The "today" filter is `endTime`-based for an
    all-day block** — the old `startTime.isAfter(now)` test dropped it from
    today from 00:00 onward, so it appeared only under *tomorrow* and then
    vanished. `DaySchedule.nextJob` prefers a timed job, falling back to the
    all-day one, or a midnight block owns "up next" all day.
  - **Siri snapshot** — schema **v2** (`scheduleSnapshotVersion`, matched by
    `supportedVersion` in `ScheduleSnapshot.swift`): adds `isAllDay` AND
    `title`, since a personal job has no client and the snapshot previously had
    no title to fall back to, so Siri said "unnamed client". `SiriStrings.who`
    is now the single client→title→placeholder resolver and `timePhrase` speaks
    "all day"; `nextAppointment` applies the same prefer-timed rule as the
    widget, and treats an all-day block as upcoming until its 23:59 end.
    **That prefer-timed test must be scoped to the block's OWN span**
    (`$0.start < earliest.end`), not to every timed visit in the 7-day window:
    the widget's `nextJob` runs against a single day's bucket, but the Siri
    snapshot is flattened across 8 days, so a window-wide comparison skipped
    today's all-day block whenever *any* later day held a timed job — Siri
    answered with Thursday's visit and never mentioned today's.
- **Job templates are display-only quick-fill, NEVER stored.** `JobTemplate`
  (`calendar/domain/models/job_template.dart`) backs the one-tap chips on the
  **add** flow only (`onApplyTemplate`, null on edit); picking one just seeds the
  title text and — if a start time is set — the end time from
  `defaultDurationMinutes` (clamped inside the same day). The appointment still
  saves with `status: 'pending'` and whatever the admin edits afterwards; there
  is no template field on the record. Add new types to the enum + a
  `jobTemplateLabel` case + EN/FR ARB keys (mirrors `statusLabel`).
- **No client `runTransaction` on routine/concurrent paths.** The
  cloud_firestore iOS plugin mutates an unsynchronized NSMutableDictionary from
  the transaction queue (`FLTTransactionStreamHandler` → `_transactions`), so
  concurrent client transactions can EXC_BAD_ACCESS (seen fatal in 1.34.1;
  unfixed upstream as of 6.7.0). The FCM + Live Activity token repos therefore
  use plain get-then-set (a double-upsert can only re-stamp `createdAt` —
  cosmetic); don't reintroduce transactions there. The two remaining client
  transactions (employee edit uniqueness re-check, series update) are isolated
  one-at-a-time admin actions — don't add new transaction call sites that can
  run concurrently with them or each other.
- **Secure storage is iOS `first_unlock_this_device`** (`SecureStorageService`):
  the default `unlocked` Keychain class made every read throw -25308 when a
  content-available push cold-started the app on a locked phone — Crashlytics
  noise AND the biometric app-lock silently not engaging that session — and
  `..._this_device` additionally keeps the cached identity out of
  device/iCloud backups (cache self-rebuilds on next sign-in after a restore).
  The service lazily migrates old items (backup-slot then delete-then-rewrite,
  marker `ios_keychain_accessibility_v2`) before any operation — keep
  `_ensureMigrated` first in every public method, and add new keys to
  `SecureStorageKeys.all` or they never migrate. `isKeychainLockedError`
  classifies residual -25308 (pre-first-unlock) as log-only at the three
  flag-read catch sites.
- **Role cache:** Never read `isAdmin`/role from SharedPreferences — always Firestore.
- **Routing:** `AppRoutes.onGenerateRoute` is the single source of truth.
  Pass typed arg classes via `Navigator.pushNamed(..., arguments: ...)`.
- **Firestore query rules vs. get rules:** For list/query operations, security rules are
  evaluated against query *constraints*, not document data. If a rule checks
  `resource.data.status == 'active'`, queries must also `.where('status', isEqualTo: 'active')`
  or Firestore rejects the whole query with `permission-denied`. Direct `doc.get()` calls
  ARE evaluated against actual document data. See `watchEmployees()` for a corrected example.
- **Users collection read rule** has three clauses (see `firestore.rules`):
  admin, `status == 'active'`, or `uid == request.auth.uid` (own doc). New
  queries on `users` must satisfy one clause via their WHERE constraints or
  they'll be rejected. A fourth
  `email_verified && status == 'invited' && email == token.email` clause existed
  only because the retired code flow left `uid` empty until redemption; P4c
  mints the Auth account up front, so an invited person now reads their own doc
  through clause 3 and the fourth clause was deleted as uncallable. An ordinary
  employee still cannot see a pending account: clause 2 requires `active`.
- **Employee accounts: the admin invites, the employee sets up** (P4c,
  2026-08-02 — this REPLACED the one-time signup-code flow entirely). The
  admin's person sheet calls `createEmployeeAccount`, which mints a **Firebase
  Auth account** with the shared starting password `Welcome123!` plus a `users`
  doc that is `invited` but **already carries the real `uid`**, and returns the
  email + password for the admin to hand over out-of-band (the `NewAccountDialog`
  right after creation, or the expanded roster row later). The employee then
  signs in normally; both gates see `invited` and route to
  `AccountSetupScreen`, where they **choose their own password** and fill in
  name/phone/consent → `completeEmployeeSetup` flips the doc to `active`.
  **ORDER IS THE APP-LAYER GUARANTEE: the password is replaced FIRST,
  client-side, then the account is activated.** The server cannot see a
  password, so "you must replace the shared default" holds because
  `AuthService.completeAccountSetup` calls `User.updatePassword` before the
  callable — swap the two and an interrupted setup leaves an *active* account
  still on `Welcome123!`. Pinned by a test (`verifyInOrder`, plus the half that
  matters: a thrown `updatePassword` must `verifyNever` the activation).
  **Be precise about how strong this is: it is client-side ordering, NOT a
  server check.** `completeEmployeeSetup` verifies only auth + a matching doc +
  `status == 'invited'`; it does not verify that the password actually rotated,
  so anything reaching the callable directly activates an un-rotated account.
  `enforceAppCheck: true` is what actually stands in the way there, and App
  Check is attestation, not authorization. Don't build on this as if the server
  enforced it.
  **The setup screen rejects `kDefaultStartingPassword` by name**
  (`account_setup_screen.dart`, `validation_passwordMustDifferFromStarting`).
  That check is load-bearing, not belt-and-braces: `Welcome123!` satisfies every
  requirement `AuthValidators.newPassword` tests (length, upper, lower, digit,
  symbol), so without it someone can "choose" the password the admin just read
  to them and end up permanently `active` on a constant that is in the source,
  on every pending roster row and known to every admin — with the roster
  reporting `active` and nothing anywhere flagging it. A failure *after* the password change deliberately does **not** revert
  it: the new password is the one the person just chose and typed twice, so
  leaving them `invited` with a working password beats resetting them to the
  shared default (the next sign-in routes back to setup, which never assumes the
  current password is the default). Re-running create on a still-`invited`
  person **resets their password** — that IS the "never signed in / lost it"
  path — but it refuses with `email-exists` once someone has set up. **That
  refusal resolves the target by `uid`, not by email, and the password rotation
  happens AFTER the doc-level transaction claims the person as still-`invited`
  (`resetProvisionedPassword`, split out of `provisionAuthAccount` for exactly
  this).** Both halves are load-bearing and both were bugs: `users.email` is
  admin-editable and is never written back to the Auth account, so an
  email-only check can clear a doc that is NOT the account Auth hands back —
  which reset a live employee's password and minted a second `users` doc
  carrying their uid, and `syncUsersByUid` then DELETED their `usersByUid`
  bridge, locking them out of everything. The transaction therefore also
  refuses when the uid already belongs to another doc (the rules' `allow create`
  uid denylist restated for the one path that bypasses rules). And resetting
  before the claim meant a setup committing in that window left the person
  active on a password nobody told them had been reverted
  and only then discover Firestore says no. `deleteEmployeeAccount` likewise
  only works while `invited` (transactional, so a setup that commits first makes
  the delete refuse); after that the no-delete invariant applies and disable is
  the only removal. Provisioning **rolls back**: if the Firestore write fails
  after the Auth account is created, that Auth account is deleted — but only if
  *we* just minted it — since an Auth account with no `users` doc is a sign-in
  `SplashScreen` can't resolve and no admin surface can see.
  **The security posture is weaker than the codes it replaced, deliberately and
  with the owner's sign-off.** `Welcome123!` is known to everyone forever, so
  between creation and first sign-in anyone who knows an employee's email can
  sign in as them and complete setup. What holds instead: an `invited` user is
  granted **nothing** by `firestore.rules` — no clients, no appointments, no
  peers — so the window is "can reach the setup screen as this person", not "can
  read the business"; and **the window is under the admin's control** (create
  the account when you are handing the credentials over, not weeks ahead). That
  mitigation is operational, not technical, and belongs in the onboarding
  instructions. `create_account_screen.dart`, both `accept_invite_*` screens,
  `CodeEntryBoxes`, `signup_code_dialog`, `InvitePreview`, the `signupCodes`
  collection and the `createEmployeeInvite`/`redeemSignupCode`/`revokeInvite`/
  `previewInvite` callables are all **deleted** — there is nothing left to
  "accept", which is why sign-in's bottom prompt went with them. Design:
  `docs/plans/redesign-subdocs/2026-08-02-p4c-HANDOFF.md`.
- **An employee's email is READ-ONLY once their doc carries a `uid`**
  (`edit_person_sheet.dart`, `readOnly: widget.employee.uid.isNotEmpty`).
  `updateEmployee` writes only the Firestore doc, and **nothing anywhere syncs
  that value back to the Firebase Auth account** — the only `auth.updateUser`
  calls in `functions/` are the two `{disabled}` flips in `bridge.js` and the
  provisioning password reset. So an edited email left the person signing in
  with the old address while every admin surface showed the new one, and it
  desynced the two stores that `createEmployeeAccount` joins on (see the
  uid-not-email refusal above). Changing a sign-in identity needs a callable
  that moves Auth and Firestore together; until that exists, not-editable is
  the honest UI. Don't re-enable the field without building that callable.
- **`kDefaultStartingPassword` is hand-mirrored** in
  `employees/domain/policies/starting_password_policy.dart` and
  `DEFAULT_PASSWORD` in `functions/employee_accounts.js`; both carry a pointer to
  the other. The Dart copy is only ever a **display fallback** for a row whose
  account was created earlier — any surface that just called the callable shows
  the password the **server echoed back**, so a drift can't reach the screen
  where it matters.
- **A displayed starting password is a CREDENTIAL — state-only, never logged,
  never persisted.** It lives in widget/controller state and dies with the
  surface, keyed to the account it belongs to (`_credentialsFor`, so a recycled
  `State` can't show one person's password on another person's row). It is never
  passed to `logger.*` (auth catch sites log through `logger.authFailure`, whose
  breadcrumb carries only the label and `failure.runtimeType`), never
  interpolated into a notice or an error message, and never written to
  SharedPreferences or secure storage. The **"Copy both"** clipboard action on
  the new-account dialog and on the roster row is the ONE sanctioned egress — it
  is the feature. Both go through `copyCredentialsToClipboard`
  (`employees/widgets/fields/credential_line.dart`), which is the single owner
  of that payload format — never re-inline `'$email\n$password'` at a call
  site, or the two surfaces can put different things on the clipboard. The
  `CredentialLine` widget beside it is shared for the same reason.
- **The deep-link dispatcher is the single `app_links` consumer, and it MUST
  skip any URI carrying the `homeWidget` query param.** `classifyDeepLink`
  (`core/deep_links/deep_link_target.dart`) returns `IgnoredLink` for it, with
  or without a value. That skip is load-bearing, not tidy: once `app_links` is
  listening, BOTH plugins observe the same `openURL`, so without it every
  widget, Live-Activity and Siri tap opens the appointment sheet **twice**. The
  param and the `home_widget` tap channel retire **together, later** (see
  `ios/CLAUDE.md`) — dropping either one alone re-breaks widget taps. On iOS,
  `FlutterDeepLinkingEnabled` stays **false**: that is the correct setting *for*
  `app_links`, since Flutter's own handler would otherwise consume the URL
  first. P4c reduced the dispatcher to the **appointment branch alone**: an old
  `esproschedule://invite?code=…` link now falls through to `IgnoredLink`, which
  is deliberate — those links can still be sitting in someone's messages and
  must not reach a screen that no longer exists. `awaitLoginRoute` and the whole
  invite-branch route race went with it. **`TopRouteObserver` is still
  registered on `MaterialApp.navigatorObservers` and still deliberately has no
  `didRemove` override** — `pushNamedAndRemoveUntil` (the account-disabled path)
  pushes *before* it removes, so overriding it would overwrite the just-pushed
  name with a route no longer on the stack. It now has no in-app caller; leave
  it and this note in place.
- **`termsAcceptedAt` / `locationConsentAt` are function-owned `users`
  fields.** They are on the `/users` update **denylist** in `firestore.rules`
  beside `uid` — **three fields**, since P4c deleted `codeExpiresAt` everywhere
  (same posture as `jobCount`/`wave` on clients), so a compromised admin session
  can't forge a consent record; `EmployeeRecord.toMap()` must never emit them, or a future
  whole-record `set()` becomes an opaque `permission-denied`. **`toMap()` omits
  `uid` and `status` for the same reason** — `uid` is on that denylist and
  `status` belongs to deactivate/reactivate; the repository's field-scoped
  allowlist in `updateEmployee` is the real write path, and `toMap()` exists
  only to round-trip the editable fields. **The denylist is on `allow create`
  as well as `allow update`**: without it the same admin session that cannot
  edit `uid` could simply create a doc carrying a forged one, and a second doc
  claiming an existing employee's uid repoints the `usersByUid` bridge every
  rules gate resolves through.
  `completeEmployeeSetup` writes the consent stamps **only when the payload
  flags are actually `true`** — stamping unconditionally would mint a
  legally-flavoured consent record for someone who never saw the checkbox.
- **Account re-provisioning REFRESHES the pending doc's editable fields, so
  `createAccount` takes the whole `EmployeeRecord` — never loose scalars.**
  `performCreateAccount`'s existing-doc branch *updates*
  `name`/`firstName`/`lastName`/`phone`/`colorValue`/`jobTitle`/`role` with
  whatever it is handed, so a call site that omits one silently wipes the
  pending person's phone or job title. `EmployeeFormController.createAccount`
  therefore takes a record and destructures it in ONE place (the repository
  method below it is the only place that speaks named strings), and
  `PendingInviteTile` passes `widget.employee` whole — the omission is
  unexpressible rather than merely documented. Don't "flatten" the controller
  signature back to named strings: that shape was a trap that bit the old Show
  code and Resend equally, and a new pending-user field had to be threaded
  through four layers with no compile error if you missed one.
  Unlike the retired code flow, **expanding the row is NOT a re-issue** — the
  starting password is a fixed shared value, so the row renders it with no
  server round-trip. Only **Reset password** re-provisions, and only that
  rotates what the person was given.
- **`watchEmployees()`** now filters `status == 'active'` — it no longer returns invited or
  disabled users. Use `watchAllUsers()` (admin-only) if all statuses are needed.
  All three `users` streams are bounded by the shared `_userStreamLimit` (500)
  so a runaway collection can't stream an unbounded snapshot to every client —
  add the bound to any new one. **The appointment range streams are bounded
  too** (`_rangeStreamLimit`, 1000) and WARN when a snapshot comes back at the
  cap — past it the calendar is showing a prefix of the range, which the grid
  dots and agenda would otherwise misreport in silence. `watchEmployees` deliberately has **no
  `orderBy`**: `watchAllUsers`' `orderBy('name')` makes Firestore exclude docs
  missing `name`, which would drop an unnamed active employee out of the
  picker (and silently change who can see a visit). That asymmetry is also why
  it isn't derived from `allUsersStreamProvider`.
- **ClientRecord legacy back-compat:** pre-Wave-reshape "business-only" client
  docs stored their name under `businessName` with an empty `name`.
  `ClientRecord.fromMap` falls back `name ← businessName`, and the repository
  search index includes `businessName`, so those docs stay visible, searchable,
  and editable. The one-time `backfillLegacyClientNames` function was removed, so
  these two reads are now the *only* thing keeping legacy business-only docs
  visible/searchable — keep them indefinitely; never strip them. (A doc missing
  `name` entirely is excluded by the list/search `orderBy('name')`; the fallback
  only rescues docs whose `name` is present-but-empty.) `toMap` must NEVER emit
  `waveCustomerId`/`wave`/`jobCount`; those are function-owned and
  `firestore.rules` rejects any client write that touches them. Every field
  `toMap` DOES emit is type/length-capped by `isValidClientData` in
  `firestore.rules` (name/business/first/last/phone/mobile/email plus the
  address family, a bounded `contacts` array, and the P3 additions
  `type`/`accessNotes`/`onSiteManager`/`billingTerms`/`autoInvoice`) —
  add the matching rule cap when you add a new client field, or the write passes
  the app but a rules tightening later rejects it.
- **A client is never removed — no delete, no archive** (owner decision
  2026-08-01, which withdrew a shipped delete). Deleting one orphaned its past
  appointments: they keep the denormalized `clientName` but lose the `clientId`
  link, so history silently detaches. The edit sheet's footer therefore holds no
  destructive action. **The one exception is temporary and must not ship:** a
  debug-gated testing delete (`kShowTestingDeleteClient` in
  `lib/core/testing_flags.dart`) reopens both `ClientsRepository.deleteClient`
  and `allow delete` on `/clients` so junk test data can be cleared. Rules are
  not build-aware, so that hole IS open in production once deployed — remove
  both together via the checklist in
  `docs/plans/redesign-subdocs/2026-08-01-p3-HANDOFF.md` §5b (grep `#pre-ship`)
  before submission. Archive was evaluated as the safe
  alternative and also dropped — it would have forced every archived-doc filter
  into Dart (pre-existing and Wave-imported docs have no such field, and
  Firestore excludes docs missing a filter field), which in turn forces
  `fetchClientsPage` to stop returning a plain `List`. It returns one today, and
  the list's `items.length < pageSize` end-of-list test is correct **only**
  because nothing filters the page after the server returns it. Reintroducing
  any post-query filter breaks that test — one filtered-out doc in a full page
  truncates the list permanently — so it would have to come back with a page
  object carrying the raw page size and a raw cursor. The Admin SDK bypasses
  rules, so console/support cleanup is unaffected.
- **The clients type filter is a SEPARATE bounded read, never a filter over the
  paginated list.** `fetchClientsByType` scans the same cached 1000-doc window
  `searchClients` uses, so the chip row and its results cost no extra Firestore
  read inside the 2-minute TTL and need no composite index.
  Routing it through `fetchClientsPage` instead would filter a server page in
  Dart, shortening a page the server actually filled — which is exactly what
  stops `ClientsListView` paging early and hides every client below the first
  non-matching one. The window bound is the same one search already lives with:
  past ~1000 clients the filter sees a prefix, not the whole roster. The chips
  offer the fixed `ClientType.pickable` set, so there is no vocabulary to
  discover and no spelling to reconcile — searching *within* an active filter
  runs in Dart over that same bounded list via `ClientSearchPolicy`, indexed
  once per result set rather than per keystroke.
  **A write patches that cached window by MERGING over the stored doc, never
  replacing it** (`_patchWindow`): `ClientRecord.toMap()` emits user-owned
  fields only, so a plain substitution drops the function-owned `jobCount` and
  `createdAt` and blanks the count on every search and type-filter result until
  the TTL expires. Any new field `toMap()` doesn't emit inherits this.
- **`jobCount` is recomputed absolutely, never incremented.** `recountClientJobs`
  (`functions/client_job_count.js`) runs `retry: true`, so a retried event would
  double-count a `FieldValue.increment`; it runs a `count()` aggregate and SETS
  the value. It fires only when `clientId` actually changes (create, delete,
  reassignment) — an ordinary title or time edit costs zero reads — and writes
  with `update()`, not `set({merge: true})`, so a client removed out-of-band is
  never resurrected as a count-only stub. Backfill is lazy: a client's count
  self-heals on its next appointment write, and a row renders nothing (never
  `0`) until the field exists.
- **`mobile` is no longer editable and self-heals into `phone`.** The edit sheet
  dropped the second phone field (owner change 5), so `EditClientSheet._save`
  promotes a stored `mobile` into `phone` when `phone` is empty and clears
  `mobile` either way, on every save. Without that, a stored number would sit on
  the doc forever — invisible, uneditable, still matched by `matchClientDocs`
  (which reads `mobile`) and still in the Wave payload. There is no migration
  script and none is needed; the fleet heals as clients are edited.
- **The street + apt precedence rule has ONE owner: `AddressParser.canonicalFrom`.**
  Both client save paths resolve their stored address through it — the explicit
  apt field wins over an apt embedded in the street text, and a blank one keeps
  the embedded value. It was a verbatim copy in each sheet, which is two owners
  for a rule whose two answers must agree on the same typed input.
- **Inline add-client while booking:** `ClientsRepository.addClient` returns the
  created `ClientRecord` with its generated Firestore doc id (NOT `void`) — the
  appointment form's "Add new client" flow links the appointment to that id.
  Don't revert it to `void`. All add-client sheet opens go through
  `showAddClientSheet` (`clients/widgets/sheets/add_client_sheet.dart`), which
  pops the created client and gates its result on `context.mounted`; pass
  `settleFocus: true` when opening from a search field (the appointment client
  picker). The affordance lives in the shared `ClientSearchField` (`onAddNew`
  callback, injected null when unused) and is admin-only only because the
  appointment forms are admin-only surfaces — gate it explicitly if it's ever
  reused somewhere non-admin. Both appointment hosts guard the open via the
  shared `InlineAddClientHost` mixin (`requestAddClient`, in
  `calendar/widgets/sheets/inline_add_client_host.dart`) — an in-flight flag,
  because the settle delays the modal barrier so an unguarded double-tap stacks
  two sheets → duplicate client. Mix it into any new inline-add host rather than
  re-copying the flag.

- **`users.name` is composed, never abandoned.** P4 added `firstName`/`lastName`,
  but `watchAllUsers()` orders by `name` and Firestore **excludes docs missing
  the orderBy field**, so a user whose `name` went empty vanishes from the admin
  roster. Every write path builds it through `composeEmployeeName`
  (`employees/domain/policies/employee_name_policy.dart`), which falls back to
  the stored name and then to `'—'` — it can never return `''`. The edit sheet
  seeds First from the whole stored `name` when both halves are empty, so a
  legacy single-name doc round-trips unchanged. **`EmployeeFormValidator` takes
  the two halves separately, never the composed name** — `composeEmployeeName`
  falls back and so can never return empty, meaning a composed value cannot
  express "the last name is missing". Its `requireLastName` flag is the one real
  difference between the two person sheets: the invite demands both halves, the
  edit leaves the last name optional so a legacy single-name doc still saves.
- **`jobTitle` is not `role`.** `role` stays the ACCESS flag
  (`admin`/`employee`) and is what `firestore.rules` gates on; `jobTitle`
  (Lead tech · Technician · Apprentice · Dispatcher) is what someone does on
  site and gates nothing. `JobTitleChips` therefore has no side effect on the
  ACCESS toggle — conflating them would make picking "Dispatcher" silently
  grant or revoke admin.
- **`workingDays` is Sunday-indexed** (`[0]` = Sunday), matching
  `weekStartForLocale` and `weekdayLabelsForLocale`, which both read intl's
  Sunday-indexed `NARROWWEEKDAYS`. Storing Monday-first would put a `% 7`
  conversion at every read and write, and one missed conversion shifts a whole
  roster by a day. Display order comes from `orderedWorkingDays`, whose cells
  carry their own `storedIndex` — a widget must write back through that, never
  through the visual position. `formatWorkingDays` (the detail page's DAYS row)
  takes its `labels` **Sunday-indexed and unrotated** (`weekdayAbbreviationsForLocale`),
  because it indexes them by `storedIndex`; passing a display-ordered list
  silently mislabels every day.
- **A user-doc rules cap must not be tighter than the widest value a shipped
  write path can produce.** `createEmployeeInvite` accepts `phone` up to 40
  chars while `TextLimits.phone` is 15, so `isValidUserData` caps phone at
  **40** — a cap of 15 would make every invite-created doc with a longer phone
  permanently un-updatable, including by `deactivateEmployee`. Rules caps mirror
  the *server* limit; the client caps with `TextLimits`. Same reasoning for the
  P4b `emergencyPhone`: rules cap **40**, client caps `TextLimits.phone`.
  **The converse also holds: a client cap must not be LOOSER than the callable's,
  or the field silently accepts a value the callable rejects as
  `invalid-argument`** — which reaches the user as an unexplained "Something went
  wrong" they cannot fix by editing. That is why the `users` name halves use
  `TextLimits.employeeNameHalf` (**100**), matching `createEmployeeInvite` and
  `redeemSignupCode` exactly, rather than the 200-char `TextLimits.firstName`
  used for clients. `name` is the JOIN of those halves, so it legitimately
  reaches 201 — its server and rules caps are **250**, sized to the composed
  value and never to a half.
- **Phone numbers are stored FORMATTED, not as raw digits** (owner call,
  2026-08-02). `PhoneInputFormatter` (`core/validators/phone_format.dart`) masks
  every phone field as it is typed, so `phone`, `emergencyPhone` and each
  contact phone persist as `(514) 555-1234`. Two deliberate pass-throughs, both
  load-bearing: anything containing `+` is returned untouched (an international
  number has no fixed 10-digit shape, and bracketing its first three digits as
  an area code would be wrong), and digits past the tenth are appended verbatim
  rather than truncated, so an extension survives. Consequences to keep in
  sync — **`launchPhoneCall` strips back to digits** (keeping a leading `+`)
  before building the `tel:` URI, because `Uri` percent-encodes the brackets and
  space into a path some dialers reject; and `ClientSearchPolicy.digitsOnly`
  already normalized on both sides, so phone search is unaffected.
  **`TextLimits.phone` is 24, and it must stay above the widest string
  `formatPhoneNumber` can emit** — `LabeledTextField` appends the
  `LengthLimitingTextInputFormatter` **after** `PhoneInputFormatter`, so the
  mask runs first and the cap truncates its output. At the old 15 the two
  pass-throughs above were unreachable: a NANP number typed with its leading 1
  formats to 16 chars, so the 11th digit could never be entered, and every
  further keystroke re-truncated to the same 15 with no error shown. Never size
  this cap to the 14-char happy path.
- **The emergency contact lives in `users/{docId}/private/emergency`, NOT on the
  users doc, and it is the one piece of person data gated to the admin AND the
  person themselves** (owner call, 2026-08-02). Firestore rules are
  document-level — there is no way to hide a field from someone allowed to read
  the document — and `/users` read clause 2 deliberately lets every active
  employee read every active peer (the crew pickers, names and colours need it).
  On the parent doc this pair therefore shipped a **third party's** name and
  phone to every employee's device; that person is not an app user and never
  consented. A subcollection is the only place rules can express the grant:
  `allow read, write: if isAdmin() || (isActiveUser() && myDocId() == userId)`.
  **Never move these back onto the users doc, and never widen a `/users` read
  clause to reach them.** Consequences to keep in sync:
  `EmployeeRecord` does **not** carry them (`EmergencyContact` does, read via
  `emergencyContactProvider`); `updateEmployee` sends
  `FieldValue.delete()` for both on every save, scrubbing any value a pre-move
  build left on the parent doc — drop that scrub only once no doc can still
  carry them; `isAvailabilityOnlyChange()` no longer lists them, because P5's
  self-service clause governs the users doc and these are not on it; and a read
  failure on this path means "not entitled", so a surface must render it as
  *not shown*, never as *none on file*.
- **`MyDetailsScreen` (Settings › My details) is the ONLY surface where a person
  edits their own record**, and it exists solely to exercise the owner half of
  the grant above — the employee detail and edit sheets are admin-only. Keep it
  scoped to the emergency contact: everything else about a person is
  admin-owned, and `allow update` on `/users` is still admin-only, so a general
  profile editor here would fail with `permission-denied`.
- **The emergency pair is its own section, not a tail on availability.** Both
  the edit sheet (`MonoSectionLabel` `employees_sectionEmergency`) and the
  read-only detail view (its own `KeyValuePanel`, rendered only when non-empty)
  group them apart from hours and access — who to call when something goes
  wrong on site is a different question from when someone works.
- **An employee is never deleted — disable is the only removal** (owner decision
  2026-08-02, which withdrew a shipped delete). Deleting the `users` doc
  orphaned every past appointment's `employeeIds` link: the visit keeps the
  denormalized `employeeNames` and loses the crew colour and the person.
  `syncUsersByUid` already does strictly more on disable — it disables the Auth
  account, calls `revokeRefreshTokens`, and purges `presence/location`,
  `fcmTokens`, every `liveActivityTokens` row and the `liveActivityCards`
  marker. `allow delete` is withdrawn from `/users`; the Admin SDK bypasses
  rules, so console cleanup is unaffected.
- **A disabled or invited employee's colour is TAKEN.** `usedColors` reads
  `allUsersStreamProvider`, never `employeesStreamProvider` — the latter filters
  to `status == 'active'`, so a disabled employee's colour was offered again and
  two people ended up the same hue, which is what the appointment bar and the
  calendar dots key on.
- **`isAvailabilityOnlyChange()` in `firestore.rules` has no caller yet.** It
  exists for P5's own-doc self-service clause; `allow update` on `/users` is
  still admin-only. Don't delete it as dead rules code, and don't wire it before
  the My-details UI ships. A deploy prints `Unused function` plus two
  `Invalid variable name` warnings for it — all three are artifacts of it being
  uncalled and disappear once P5 wires it up.

- **Calendar (rebuilt in P2, 2026-07-30):** `table_calendar` is **deleted**;
  the month view is our own `CalendarMonthGrid` + `CalendarMonthPager`. It
  renders **only the weeks the month actually occupies** — 4, 5 or 6 rows from
  `monthGridRowCount` (owner call, 2026-07-31: a fixed 6 trailed a week of
  nothing but off-month cells). A fixed **5** is still wrong the other way and
  drops the end of months like August 2026, so the row count must stay derived,
  never a constant. Week start comes from the locale (`weekStartForLocale`,
  memoized per locale string — it builds a `DateFormat` just to read its
  symbols, and the grid, pager and week strip all ask on every calendar
  rebuild). Resolve it from a widget through `CalendarMonthGrid.weekStartOf(context)`
  rather than re-inlining `weekStartForLocale(Localizations.localeOf(...))`.
  Because rows vary, `CalendarMonthGrid.heightFor` takes a **required `rows`**
  (use `rowsFor(context, month)`), the pager animates its viewport to the month
  in view, and each page is wrapped in `ClipRect` + top-aligned `OverflowBox`
  so a taller month being dragged in doesn't overflow before the height
  settles. Off-month cells render a **faint day number AND their
  crew dots** but stay untappable and out of the semantics tree: the design says
  "blank, Ink 15, not tappable" while the program spec widened the fetch range
  precisely so trailing days aren't dotless, and dots-plus-faint-number is what
  reconciles the two (owner-confirmed). **The crew dots also survive selection**
  (owner call, 2026-07-31): the selection circle fills the day number only and
  the dot row sits below it on the plain cell background, so suppressing them
  there made the day being looked at the one day whose crew was invisible.
  Every cell that has crew shows it — off-month, selected, today, all of them.
  `today` always comes from
  `currentDayProvider`, never `DateTime.now()`, or the circle sticks on
  yesterday in an app left open across midnight.
  **`AppointmentDateRange.visibleMonth` overscans ±14 days, not ±7.** With the
  variable-row grid the true worst case is ±6, so ±14 is now a deliberate
  superset — keep it rather than tuning it to the current row rule, or a future
  grid change silently empties the edge cells' dots.
  **Portrait is TWO scroll areas** (owner call, 2026-07-31): the grid is FIXED
  above the agenda, and the jobs have their own `CustomScrollView`, so reading
  down the day never moves the calendar. Collapse is a **drag on the divider
  between them** — `_CollapseHandle`, which is also a tap-toggle and carries the
  Hide/Show calendar tooltip that the widget tests find it by.
  `CalendarCollapse` (`domain/collapse_state.dart`) accumulates drag deltas past
  **24px**, resetting on a direction reversal and on `endDrag` so two half-drags
  don't add up. Only `onDragDelta` returns a bool (it means "the flag flipped",
  so the caller rebuilds on a transition and not per gesture frame); `toggle()`
  is `void` — it always flips, so a bool there would be a constant nobody reads.
  The agenda's own `ScrollController` is load-bearing for a second reason: an
  explicitly-controlled scrollable is not the *primary* one, which is what keeps
  it and the grid off the app-wide `Scrollbar`'s single controller. The old
  shared-viewport version needed a derived
  `gridHeight − stripHeight` spacer to hold the extent the grid vacated; with two
  viewports there is no vacated extent, and the spacer is gone. **The grid does
  not scroll at all** (owner call, 2026-07-31): it sits in a `Flexible` +
  `SingleChildScrollView` whose physics are `NeverScrollableScrollPhysics`, so
  the viewport is pure overflow protection — a short viewport (small phone,
  large text scale) shrinks the grid instead of running the column past the
  bottom, and at normal heights it shrink-wraps and is inert. The handle is the
  ONLY thing that moves the grid; don't restore scrollable physics to "fix" a
  clipped month.
  **Collapse is portrait-only** — `_splitCalendar` short-circuits the strip.
  **Paging selects.** A month swipe (or the month picker) lands on the 1st and
  SELECTS it, and a swipe on the collapsed week strip pages one week and selects
  that week's first day — the agenda must always describe the grid above it.
  That is also why the fetch window is `AppointmentDateRange.forCalendar`
  (month grid ∪ selected day) rather than the month alone: any path that leaves
  a selection outside the visible month drops its jobs from the fetch, and the
  agenda then reports "0 jobs" for a day that has some.
  The calendar is the **one screen with no `AppTopBar`** (see the frontend rule):
  `CalendarHeaderBlock` replaces it, and therefore must set the system overlay
  style itself via `AnnotatedRegion`, choosing icon brightness from the surface
  colour rather than the theme brightness. Its title and controls **stack under
  `context.isCompact`**. The month name itself is **measured, not gated**: the
  screen passes both `monthLabel` and `monthLabelShort` (`DateFormat.MMMM` /
  `.MMM`) and `_MonthRow` lays out the row, subtracts the year + chevron, and
  takes the abbreviation when the full name won't fit. Don't "simplify" that
  back to a text-scale threshold — the in-app XL setting is **exactly 1.4**, so
  the `isCompact` gate (`> 1.4`) missed it entirely, and the OS scaler, the
  device width and the locale's month lengths all move independently. The
  semantics label always speaks the full month. Note the widget test asserts
  against **viewport width**, not a scale: the test font is far wider per glyph
  than the shipped one.
- **`AppointmentCard` is the ONE appointment card** — calendar agenda, day
  route, client job history, both dashboard sections and the paginated history
  list (`AppointmentTile` is deleted, along with `colorFromMap` and
  `resolveAssigneeNames`). It takes `crew: List<AppointmentCrew>` from
  `crewFor(appointment, colorMap:, nameMap:)`; without a `nameMap` that falls
  back to the record's denormalized `employeeNames`, which is what the history
  and client surfaces already showed. **The crew bar bands EVERY assignee**
  (`_crewBarDecoration`, up to `_kMaxCrewShown` = 4 — the SAME cap the avatar
  stack uses, deliberately, so the bands and the faces never disagree on how
  much of the crew the card shows): a flat colour for one,
  a hard-stopped `LinearGradient` of each crew colour for more (owner call,
  2026-07-31 — it followed the first assignee alone before that, and the
  pre-redesign grey-for-multi-crew is doubly wrong: grey reads as
  *unassigned*). Only a job with no crew at all is `textFaint`. The meta line
  is an **overlapped avatar stack — one avatar per assignee — followed by the
  client name** (owner call, 2026-07-31; it was a single avatar plus the text
  `Theo +1 · Client`, and `calendar_crewAndClient` is deleted). `_CrewAvatars`
  computes its own width rather than laying out, because of the
  `IntrinsicHeight` rule below; `_crewLabel`/`calendar_crewPlusOthers` survive
  only as the fallback text for a record with no client name to show. `alwaysShowChip` is **gone**, not ported
  (every call site passed `true`); cancelled dims to **0.6**, not 0.75. The card
  uses `IntrinsicHeight` to stretch the crew bar, so **nothing in its subtree may
  use `LayoutBuilder`, `AutoSizeText` or `FittedBox`** — they cannot report
  intrinsics.
- **`findBusyEmployees` must exclude the appointment under edit.** Pass
  `excludeAppointmentId` from any edit-flow conflict check or the job collides
  with itself and reports every one of its own assignees as busy. The exclusion
  is by **doc id, not by series**, so a genuine clash with a sibling occurrence
  still surfaces. A clash returns the sealed `EventDetailsBusyEmployees` (not an
  error) and **must clear `isSaving`** before returning, or Save stays stuck
  once the dialog is dismissed.
- **Navigation (`lib/core/navigation/`, restructured 2026-07-30):**
  `AppDestination` is a **sealed** family — `enum HubTab {calendar, clients,
  employees, liveMap}` (the four `IndexedStack` panes) and
  `enum PushedDestination {dayRoute, history, dashboard, settings}` (plain
  routes above the shell). The split makes `select(settings)` a **compile
  error** instead of an `IndexedStack` range crash; that is the whole point —
  never collapse it back to one enum plus a list or an `isHubTab` flag.
  `implements Enum` keeps `.name`/`.values` on the union type, and `.name` is
  load-bearing: it is the persisted `tour_seen_tabs` key AND the showcase scope
  name, so **renaming a member silently replays or orphans a tour** (that is
  why the member stayed `employees` while its label became "Team" via
  `nav_team`). `navigateToDestination` is the one nav action; a hub tab reached
  from a pushed route goes through `selectAndReveal` (collapse, then switch) —
  the old `pushReplacementNamed` path left the wrong screen on top from a
  2-deep stack. `goHomeToCalendar` is the canonical go-home gesture behind the
  header's Calendar pill. **`_popToShell` targets the shell's captured
  `ModalRoute`, never `isFirst`** — on `_hubRoute`'s fallback branch the shell
  is not route #1, so `popUntil(isFirst)` pops the shell itself and strands the
  user. The **nav rail, `AdaptiveShell`, `AdaptiveDestination`,
  `Breakpoints.expanded` and `isExpanded` are all deleted**; `AppNavDrawer`
  (right-anchored, from `drawerGroups(isAdmin:)`) is the nav surface at every
  screen size, and `AppHeaderPair` sits in every `AppTopBar.actions` — on the
  **calendar only** it is built with `showCalendarPill: false` (a go-home pill
  on the screen it goes home to is dead weight; owner call 2026-07-31), so that
  header carries the day-route button and the hamburger alone.
  `_hubRoute` + `HubTabRedirectRoute` survive at three tab routes — they look
  dead but remain the cold-start fallback and are pinned by `hub_shell_test`.

- **Feature tours (`lib/features/feature_tour/`, showcaseview 5.x):** each
  destination registers its OWN showcaseview scope (`tourScopeName`) — the hub
  IndexedStack keeps every tab mounted, so a shared scope would mix hidden
  tabs' targets into the visible tour. `FeatureTourHost` is the only start
  path. **Its visibility gate is chosen by the destination's sealed type, not
  by a null `HubShellScope`**: a `HubTab` gates on `HubShellScope.currentOf`,
  a `PushedDestination` on `ModalRoute.of(context)?.isCurrent`. A null scope is
  ambiguous — it also describes a hub screen hosted standalone in a test, where
  "never start" must be preserved. Before this split, Settings and History
  (now pushed routes) would have had `currentOf == null` and their tours would
  have silently never started; Settings is one of only two employee tours.
  Route mode also awaits `_routeTransitionSettled()` so showcase measures a
  page that has finished sliding in. It
  awaits `tourSeenProvider.ready` before acting (the optimistic empty default
  would replay seen tours on cold start), and drops steps whose target isn't
  rendered via `isTargetRendered` — **never `GlobalKey.currentContext`: the
  5.x `Showcase` widget does NOT forward its key to the element tree, so
  currentContext is always null** (zero survivors → mark seen, never
  crash/retry). The auto-start sets a `_started` guard before its post-frame
  callback runs; **reset `_started` on the visibility-changed early-return** (the
  tab was switched away before the callback fired) — a stale `true` there
  permanently suppresses that tab's tour for the session, so a fast tab-switch
  during auto-start otherwise wedges it shut. **Data-dependent tabs MUST pass `FeatureTourHost(ready:)` false
  while their body shows a loading/error placeholder** — the tour's targets
  don't exist yet, so an ungated start finds zero survivors and permanently
  marks the tab seen against an empty body (bit LiveMap: its FAB targets live in
  the map stack, absent during the presence-data load). Calendar gates on
  `!isLoading`; LiveMap gates on `_mapTargetsRendered` (the map stack, not the
  placeholder, is showing). Settings instead FORCES its below-fold targets to
  mount via `autoScroll: true` + an inflated `scrollCacheExtent` — a lazy list
  won't build off-screen rows for `isTargetRendered` to find. Scopes are
  registered in initState and deliberately NEVER
  unregistered (register() replaces; unregister in dispose would race the
  replacement State's initState on a hub identity change), and every
  dismiss/mark-seen is gated by `_tourRunning` because the package fires
  onDismiss even when idle. Step catalogs are pure (`tourStepsFor`);
  Clients/Employees/History/LiveMap are admin-only tabs, so their employee
  catalogs are empty and their screens guard wraps on catalog membership.
  Seen flags are device-local SharedPreferences ONLY (`tour_seen_tabs`);
  sign-out does not reset them — the Settings "Replay app tour" row is the
  only reset.

## Conventions

- Feature-first: `lib/features/{auth,calendar,clients,employees,settings,splash}/`.
  Promote to `shared/` or `core/` only when reused across features.
- Services are plain classes; no DI container. `AuthService` accepts optional
  injected deps for testability — mirror this pattern.
- Normalize emails: `.trim().toLowerCase()` before any Firestore read/write.
- `initState` must be thin — extract heavy init to `_initStreams()`.
- **Submit/save reentrancy:** in a controller's submit/save, set the in-flight
  flag (`isSubmitting`/`isSaving`) synchronously BEFORE the first `await` —
  including any pre-validation seed-settle await or conflict-check round-trip —
  and reset it on every early-return and `catch`. Awaiting before the flag is
  set leaves the button enabled, so a double-tap starts a concurrent write
  (duplicate appointment / series rewrite); an un-caught pre-check throw with
  the flag already set leaves the button stuck. A detail view that stays mounted
  after its action (master-detail pane — only a delete clears the selection)
  must also reset its busy flag after `onAction` under a `mounted` guard; the
  sheet variant unmounts there, so the guard covers both.
- All Firestore writes via service classes (never direct `FirebaseFirestore.instance` in UI).
  Always set `createdAt`/`updatedAt` server timestamps.
- Entity search matches in Dart (Firestore has no full-text search) — don't
  "fix" it into a server query. Clients/history search read a bounded window
  (`_historySearchScanLimit` / clients ~1000 docs) via `clientSearchProvider` /
  `historySearchProvider` (`autoDispose.family` keyed by query) and match across
  all fields in Dart; the loaded-page filter fills the gap until the debounced
  read settles. `ClientSearchPolicy.normalize` (accent-fold) + `digitsOnly`
  (phone) are the matching primitives, and `ClientSearchPolicy.matchesClient` is
  the single client-side fallback matcher — route new client matching through it.
  `FirebaseAppointmentsRepository` keeps a bounded LRU of recent `searchHistory`
  results on the long-lived singleton; every write path clears it via
  `_invalidateSearchCache()`, so a new appointment-write method MUST call it too
  or history search serves stale results (including a just-deleted appointment
  that opens a detail view for a doc that no longer exists).
- **Client "Job history" section** (`ClientJobHistorySection`, admin-only client
  detail) reads via `fetchClientHistory` (`clientJobHistoryProvider`, an
  `autoDispose.family` that re-fetches on `onLocalWrite`). The query filters on
  `clientId` alone so the automatic single-field index serves it — there is NO
  `orderBy`, so newest-first is sorted in Dart over the bounded window. Don't add
  a server `orderBy('startTime')`, or it needs a `(clientId, startTime)`
  composite index.
- **The team roster's "jobs today" count is ONE listener, not one per row.**
  `employeeJobsTodayProvider` reduces a single `appointmentsInRangeProvider` over
  today's range into a `Map<String,int>`; every row reads the map. The range
  comes from `todayRangeProvider`, which watches `currentDayProvider` — never
  `DateTime.now()`, or the counts stick on yesterday in an app left open across
  midnight. Cancelled visits don't count. **The employee detail's TODAY panel
  filters that SAME stream** (`employeeTodayJobsProvider`) rather than opening a
  per-employee query — the Team tab already holds the day range open, so a
  detail costs no extra read and the panel can't disagree with the count on the
  row that opened it.
- **Every widget-layer offline write guard goes through `guardedOffline`**
  (`core/errors/error_cause.dart`, beside `composeErrorNotice`) — it reads
  `isOfflineProvider`, pushes the cause+tag notice and returns true so the
  caller returns. The block was copy-pasted at six sites; the `tag` must still
  match the `logger.warn` prefix at the same site. The two `accept_invite_*`
  screens deliberately stay out — they surface offline through their own
  `AuthBanner`, not a notice. Controller-layer guards (`add_event`,
  `event_details`, `client_form`) keep returning a typed failure instead.
- **`DateFormat` is memoized per locale** (`calendar/domain/month_grid.dart`:
  `longDateFormatFor`, `weekdayAbbrevFormatFor`, `_symbolsFormat`). Constructing
  one verifies the locale and parses a skeleton into pattern fields, and the
  calendar built a fresh one PER DAY CELL for a semantics label — 30–90 per
  rebuild on every day tap and month swipe. Never call a `DateFormat.*`
  constructor inside a cell/item builder.
- **`TourSteps`** (`feature_tour/domain/tour_steps.dart`) owns a screen's step
  ids, keys and `step()` wrapper. Six screens had a copy of the trio that had to
  stay in sync (`keys[id]!` force-unwraps; `indexOf`/`length` feed "step N of
  M") and Settings had already drifted. One `late final _tour = TourSteps(dest,
  isAdmin:)` per screen — don't re-inline it.
- **The account-exit teardown lives in `AccountExitListeners`**
  (`core/app/account_exit_listeners.dart`), the sibling of `AppSyncListeners`.
  The ORDER is load-bearing: push, presence and Live Activity de-register
  BEFORE `signOut()`, because each needs the credential sign-out revokes. Its
  `_isHandlingAccountExit` guard is released by the post-frame callback on
  success and by the `finally` only on failure — three listeners can fire for
  one underlying event.
- Per-keystroke search debounces through `Debouncer` (`lib/core/utils/debouncer.dart`,
  own one per State, `dispose()` it). `SettingsSaveDebouncer` is the async-action
  variant — don't add a third raw `Timer`.
- Localization (`gen_l10n`):
  - Source of truth: `lib/l10n/app_en.arb` (template) + `lib/l10n/app_fr.arb`.
  - Generated `app_localizations*.dart` live in `lib/l10n/.gen/` and are
    **gitignored**. Regenerate with `flutter gen-l10n`; never hand-edit them.
  - Single canonical import: `package:scheduling/l10n/l10n.dart` (re-exports
    `AppLocalizations` + the `context.l10n` extension). Don't import
    `app_localizations.dart` directly.
  - `context.l10n` is non-nullable (`nullable-getter: false`) — no `!`.
  - `MaterialApp` uses `AppLocalizations.localizationsDelegates` and
    `AppLocalizations.supportedLocales`; don't hand-build the delegates list.
  - Every key MUST carry a `@key` metadata block (description + typed
    placeholders). Enforced by `required-resource-attributes: true` in
    `l10n.yaml` — `flutter gen-l10n` fails on a bare key.
  - Key naming: `feature_keyName`. Prefix buckets: `auth_`, `calendar_`,
    `clients_`, `employees_`, `settings_`, `maps_`, `status_`,
    `validation_`, `error_`, `common_`, `nav_`, `app_`.
  - Adding a key: update both ARBs in lockstep, add the `@key` block in EN,
    run `flutter gen-l10n`. EN/FR drift surfaces in
    `lib/l10n/.gen/untranslated.json`.
- Firebase callable responses on Android return nested objects as
  `Map<dynamic, dynamic>`, not `Map<String, dynamic>`. Casting directly
  with `as Map<String, dynamic>?` throws a `TypeError` at runtime.
  Always cast loosely first: `(value as Map?)?.cast<String, dynamic>()`.
- `whereArrayContainsAny` has a hard limit of 30 items. When querying by a
  list of IDs (e.g. employee IDs), chunk into batches of 30 and merge results
  in Dart. See `findBusyEmployees` in `firebase_appointments_repository.dart`
  for the reference implementation.

## Cloud Functions

Functions live in `functions/` (project `schedulingapp-88727`, region
`us-central1`), split into domain modules re-exported by a thin `index.js`.
Full guidance — module map, every function, push / Live Activities / Wave, the
Firestore TTL rules — is in `functions/CLAUDE.md`, which loads when working
under `functions/`. Per-function reference: `docs/CLOUD_FUNCTIONS.md`.

**Release deploy runbook: `docs/DEPLOYMENT.md`** — ordering (backend BEFORE the
app build, because `assertPayloadShape` rejects unknown keys), the
old-build-compatibility check, rollback, and the deploy log recording what
production actually runs. Read it before any deploy that touches a callable
payload or a rules cap.

Deploy: `firebase deploy --only functions,firestore:rules,firestore:indexes,storage`
(`storage:rules` is **not** a valid deploy target — use `storage`.)
**Never pass `--force`** — it deletes any prod Firestore TTL policy missing from
`firestore.indexes.json` (this removed all 5 live policies once, 2026-07-21).
Always run `cd functions && npm run lint` before deploying.

`GOOGLE_MAP_API_KEY` lives in Secret Manager only — it is **not** in `dev/.env`.

App Check emulator setup: run app once → search Logcat for `DebugAppCheckProvider`
UUID → register it in Firebase Console → App Check → your Android app → Manage
debug tokens. The UUID is stable per AVD but changes on new AVDs or full
reinstalls — re-register when it does. An unregistered token causes all Firestore
writes and non-cached reads to fail with `permission-denied` while cached reads
still succeed, making the failure appear collection-specific.

## Testing

- Use `_scaledHarness` (Size 260×640, textScaler 2.0) to catch overflow.
- Harness requirements, mocking rules and device-only caveats: `.claude/rules/testing.md`.

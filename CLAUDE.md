# CLAUDE.md

Flutter app (Dart `^3.10.7`) for managing appointments, clients, and employees.
Backend: Firebase (Auth, Firestore, Storage, App Check). Targets Android and iOS.
**Ships to the App Store ONLY (decision 2026-07-08).** Android is a dev/test
target on this Windows box and is never published to Play — keep `android/`
and the Android Firebase app (they're the local dev harness; deleting them
would leave no runnable platform on this machine), but don't chase
Play-release work (keystore, Data Safety, Play Integrity).

iOS notes (Phase 0 of clean-architecture restructure):
- iOS native build, run, and Crashlytics dSYM upload require a Mac. **Do NOT
  re-run `flutterfire configure`** — `lib/firebase_options.dart` already builds
  the iOS options from `dev/.env` (`IOS_API_KEY`, `IOS_APP_ID`,
  `iosBundleId: net.vogas.scheduling`); re-running it rewrites the file into the
  literal-values style and breaks the env-based setup. Carry
  `ios/GoogleService-Info.plist` (gitignored) to the Mac out-of-band; it lives
  at the `ios/` **root**, not `ios/Runner/`.
- **The project uses Swift Package Manager — there is no Podfile and never will
  be.** Ignore any older notes mentioning `pod install` or `${PODS_ROOT}`.
  Xcode resolves `firebase-ios-sdk` (pinned in `Package.resolved`) on first
  open. The Crashlytics dSYM upload Run Script from the SPM checkout
  (`"${BUILD_DIR%/Build/*}/SourcePackages/checkouts/firebase-ios-sdk/Crashlytics/run"`)
  is wired in `project.pbxproj` on ALL THREE code-bearing targets (added
  2026-07-21): Runner (bundled plist), plus ScheduleWidgetExtension and
  SiriIntents — the extensions are Firebase-free so their phases pass
  `-gsp "${PROJECT_DIR}/GoogleService-Info.plist"` (the ios/-root plist) and
  need `ENABLE_USER_SCRIPT_SANDBOXING = NO` (flipped on the widget target;
  don't re-enable it or the upload silently fails). Debug Information Format
  is `DWARF with dSYM` for Release at the project level, which the extension
  targets inherit — don't set a per-target override back to `dwarf`. `google_maps_flutter` uses the `google_maps_flutter_ios_sdk9`
  endorsed SPM override (Maps SDK 9.x, iOS 15+) — never fall back to the
  default CocoaPods-only `google_maps_flutter_ios`. Same rule for save/share:
  the photo viewer's Save-to-Photos uses **`saver_gallery`** (ships a
  `Package.swift`), deliberately NOT the more popular `gal` — `gal` is
  CocoaPods-only and would force a Podfile into this SPM-only project. Vet any
  new iOS plugin for SPM support before adding it.
- Deployment target is **iOS 18.0** (set on all targets in the Xcode project;
  bumped from 15.0 on 2026-07-19 — the Siri App Intents extension needs iOS 16
  and the Live Activity Directions button's returnable `OpenURLIntent` needs
  iOS 18, so the whole app moved to an 18.0 floor and iOS 15–17 users are
  dropped). Well above App Attest's 14+ requirement. App Check uses **App
  Attest** (`AppleAppAttestProvider` in `main()`); don't lower the target below
  14 or attestation silently fails on the runtime device. See
  `docs/plans/APP_STORE_SUBMISSION.md` for the full Mac runbook.
- App Check via **App Attest** (not DeviceCheck) needs, on the Xcode side:
  the **App Attest** capability / entitlement
  (`com.apple.developer.devicecheck.appattest-environment`, set to `production`
  for Release), and App Attest **enabled in the Firebase Console** (Build →
  App Check → the iOS app — no `.p8` key required, unlike DeviceCheck). The
  console provider MUST match the code provider or attestation is rejected.
  App Attest fails on the iOS Simulator — verify on real hardware.
- `Info.plist` already declares `NSCameraUsageDescription`,
  `NSPhotoLibraryUsageDescription`, and `LSApplicationQueriesSchemes`.
- **Deep-link tap URLs must keep the `homeWidget` query item.** The three iOS
  producers (`ScheduleWidget.swift`, `LiveActivitiesAppAttributes.swift`,
  `SiriIntents/ScheduleSnapshot.swift`) emit
  `esproschedule://appointment?id=…&homeWidget`; the `home_widget` plugin's
  `isWidgetUrl` claims a URL only when that query item is present, and nothing
  else consumes the scheme (`FlutterDeepLinkingEnabled` is `false` and
  `AppDelegate` has no `open url` override), so dropping the param silently
  turns taps into plain app launches (fixed 2026-07-29). Retire the param only
  together with the `home_widget` tap channel, when the P4b `app_links`
  dispatcher lands (docs/plans/2026-07-29-redesign-program.md). Swift-side, so
  Mac-only verification: widget row / Live Activity tap → appointment sheet.

## Commands

```bash
flutter pub get
flutter run
flutter analyze
flutter analyze 2>&1 | grep -E "error -|warning -"   # the baseline is 0 issues — any lint you see is yours
flutter test
flutter test test/<path>.dart
flutter test --plain-name "<name>"
flutter build apk
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

- **Auth:** Every signed-in user needs an `active` Firestore `users` doc with
  matching `uid`. `SplashScreen` signs out otherwise. Don't break this.
  Gate with `!employee.isActive` — `isDisabled` only matches `'disabled'`,
  so it misses `'invited'`, `''`, and any future status.
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
  now is within [start, end] and to `overdue` once `endTime` has passed; the
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
- **Users collection read rule** has four clauses (see `firestore.rules`): admin,
  `status == 'active'`, `uid == request.auth.uid` (own doc), or
  `email_verified == true && status == 'invited' && email == token.email` (own
  invite). New queries on `users` must satisfy one clause via their WHERE
  constraints or they'll be rejected. The `email_verified` guard on the invited
  clause is deliberate hardening — a password signup leaves the token
  unverified, so this clause never actually rescues the invited user, but the
  flow doesn't need it (activation is Admin-SDK-only in `redeemSignupCode`); it
  only closes an unverified principal claiming someone else's invite email.
- **Invited-employee signup (one-time codes):** the admin's "Invite" calls the
  `createEmployeeInvite` callable, which creates the `invited` `users` doc and a
  `signupCodes/{sha256(code)}` doc and returns the **plaintext code once** (shown
  in a copy dialog for the admin to share out-of-band). The employee signs up
  with email + password + code via `AuthService.signUpWithCode`, which registers
  then calls `redeemSignupCode`; that callable validates server-side (14-day
  expiry; token email must equal the invite email) and **activates the account
  atomically** (`uid` + `status:'active'`, code consumed). `redeemSignupCode` is
  rate-limited **by token email**, not caller uid — a failed signup deletes +
  re-registers to mint a fresh uid, which would reset a uid-keyed cap. On redeem
  failure `signUpWithCode` **rolls back the just-created Auth user** (re-auth
  then `delete()`) so no orphan is left; if rollback itself fails it throws
  `AuthFailureAccountCreationIncomplete` and logs the orphan uid. A valid code
  whose token email ≠ invite email returns a distinct `code-email-mismatch` →
  `AuthFailureSignupEmailMismatch` (tells the user to use the exact invited
  email, not the misleading generic `invalid-code`; only reachable once the
  caller already holds a real code, so disclosure is minimal). There is NO email
  verification and NO client self-activation — activation is Admin-SDK only, and
  `firestore.rules` denies all client access to `signupCodes`. `createEmployeeInvite`
  is idempotent for a still-`invited` email (re-issues a fresh code; the separate
  `regenerateSignupCode` callable was dropped); an active account errors
  `email-exists`. Sign-in (`login_screen.dart`) just
  `findUserByUid` → route or sign out (no activation step). Design:
  `docs/archive/INVITED_SIGNUP_REDESIGN.md`.
- **`watchEmployees()`** now filters `status == 'active'` — it no longer returns invited or
  disabled users. Use `watchAllUsers()` (admin-only) if all statuses are needed.
  All three `users` streams are bounded by the shared `_userStreamLimit` (500)
  so a runaway collection can't stream an unbounded snapshot to every client —
  add the bound to any new one. `watchEmployees` deliberately has **no
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
  `type`/`tags`/`accessNotes`/`onSiteManager`/`billingTerms`/`autoInvoice`) —
  add the matching rule cap when you add a new client field, or the write passes
  the app but a rules tightening later rejects it.
- **A client is never removed — no delete, no archive** (owner decision
  2026-08-01, which withdrew a shipped delete). Deleting one orphaned its past
  appointments: they keep the denormalized `clientName` but lose the `clientId`
  link, so history silently detaches. `ClientsRepository` therefore has no
  `deleteClient`, `clients` has no `allow delete` rule, and the edit sheet's
  footer holds no destructive action. Archive was evaluated as the safe
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
- Per-keystroke search debounces through `Debouncer` (`lib/core/utils/debouncer.dart`,
  own one per State, `dispose()` it). `SettingsSaveDebouncer` is the async-action
  variant — don't add a third raw `Timer`.
- Sheet-from-search: 80 ms settle before `showModalBottomSheet`;
  double unfocus with 120 ms gap after sheet closes.
- Catch blocks log via `ref.read(loggerProvider).warn('label', e, st)`. For
  user-visible failures (save/delete/status), also push
  `noticeServiceProvider.error(<l10n string>)` from the widget layer.
- Notices slide in from the **top** of the screen via `Overlay` (`NoticeListener`).
  `NoticeListener` is in `MaterialApp.builder`, which sits above the `Navigator`,
  so `Overlay.maybeOf(context)` returns null. It must be constructed with
  `navigatorKey: _navigatorKey` (from `_PaulAppState`) to reach the Navigator's
  overlay. Omitting it silently suppresses all notices.
  Do not call `ScaffoldMessenger.showSnackBar` for user feedback — use
  `ref.read(noticeServiceProvider).success/error/info(message)` instead.
  The three remaining direct SnackBar call sites (account-disabled in `main.dart`,
  photo-upload in `main_calendar_screen.dart`, map-launch in `address_map_launcher.dart`)
  use `scheme.errorContainer` / `scheme.onErrorContainer` + an icon `Row`.
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
- Failure UX strings already exist — `somethingWentWrong`,
  `somethingWentWrongPleaseTryAgain`. Reuse before adding new ones. (Most
  generic catch sites now compose via `composeErrorNotice` cause+tag instead.)
- Typed failures: each feature defines a sealed `Failure` family at
  `lib/features/<f>/domain/<f>_failure.dart` (see `AuthFailure`,
  `EmployeesFailure`, `MapsFailure`). Repositories throw the typed
  failure; catch sites surface via
  `noticeServiceProvider.error(failure.toLocalizedMessage(context))`.
  Don't reach for `throw Exception(...)` — the string leaks to UI/logs.
- One-shot side effects on `AsyncValue` transitions (e.g., stream goes
  data → error) belong in `ref.listen`, not in `.when`'s error branch.
  The `.when` error branch fires on every rebuild and would spam the
  notice surface.
- Text-field length caps live in `lib/core/validators/text_limits.dart`.
  Use the constants via `LabeledTextField(maxLength: TextLimits.x)` —
  don't hardcode integer caps at call sites.
- `StatusChip` internally caps user text scaling at 1.3×. Never wrap a
  `StatusChip` call site in `MediaQuery(textScaler: noScaling)` — the
  chip handles it.
- Firebase callable responses on Android return nested objects as
  `Map<dynamic, dynamic>`, not `Map<String, dynamic>`. Casting directly
  with `as Map<String, dynamic>?` throws a `TypeError` at runtime.
  Always cast loosely first: `(value as Map?)?.cast<String, dynamic>()`.
- `AuthErrorMapper` only catches `FirebaseAuthException` — a Firestore
  `FirebaseException` (e.g. `permission-denied` from rules) falls through to
  `AuthFailureUnknown` → "Something went wrong. Please try again." When
  debugging that generic error in the auth/sign-up flow, check `firestore.rules`
  first, not Firebase Auth error codes.
- `whereArrayContainsAny` has a hard limit of 30 items. When querying by a
  list of IDs (e.g. employee IDs), chunk into batches of 30 and merge results
  in Dart. See `findBusyEmployees` in `firebase_appointments_repository.dart`
  for the reference implementation.

## Cloud Functions

Functions live in `functions/` (project `schedulingapp-88727`, region
`us-central1`). `index.js` is now a thin wiring surface that re-exports all 22
functions under their original names — the implementations are split into
domain modules: `security.js` (shared callable guards — `assertPayloadShape`,
`requireString`, `requireNumberInRange` (finite number in `[min,max]`; rejects
`NaN`/`Infinity`), `readSessionToken`, `enforceDurableRateLimit`, `assertAdmin`),
`bridge.js` (`syncUsersByUid`), `client_propagation.js`
(`propagateClientEdits`), `client_job_count.js` (`recountClientJobs`, backed by
the pure `clientsToRecount`), `places.js`, `account.js`, `invites.js`
(invited-employee signup codes — `createEmployeeInvite` + `redeemSignupCode`,
backed by pure helpers in `signup_code_utils.js`), `maintenance.js`
(image validation + history purge; the pure JPEG/PNG magic-byte check lives in
`image_magic.js`), `notifications.js` (FCM push triggers, backed by
`notification_utils.js` and — for the travel-time reminder sweep —
`travel_utils.js`), the Live Activity stack (`apns_client.js`,
`live_activity_utils.js`, `live_activity_registry.js`,
`live_activity_dispatch.js` — see the Live Activities bullet below), and
`wave/callables.js`. Instant + business-time-zone primitives (`toMillis`,
`formatBusinessTime`/`formatTimeOfDay`, `businessYmd`/`businessOffsetMs`/
`businessMidnight`, `BUSINESS_TIME_ZONE`) live in `time_utils.js` and are shared
by `notification_utils.js`, `live_activity_utils.js`, and
`widget_payload_utils.js` — so a push and the Live Activity card can't drift on
how they render the same instant. It must stay **dependency-free**: those three
consumers sit on a `notification_utils` → `live_activity_dispatch` →
`live_activity_utils` require chain, and any require here would close a cycle.
Never re-inline a local `toMillis` or a bare `timeZone: "America/Toronto"`.
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
(`image_magic.js`, `signup_code_utils.js`, `notification_utils.js`) and test
that; `onCall`/`onDocument*` modules load lazily and are safe to `require`
directly. Jest tests live in **`functions/__tests__/` only** — the parallel
`functions/test/` directory was merged away 2026-07-19; don't recreate it.
- `syncUsersByUid` — Firestore trigger: mirrors `users/{id}` into `usersByUid/{uid}` bridge collection so security rules can resolve roles from auth UID alone. **It also owns deactivation:** on `active` → anything else it disables the Firebase Auth account + `revokeRefreshTokens` and purges every delivery artifact (`presence/location`, `fcmTokens`, `liveActivityTokens` via `recursiveDelete`, and the `liveActivityCards` marker); `→ active` symmetrically re-enables the account. This is load-bearing, not cleanup — the rules gates below assume a *live* status check can't be reached with a stale credential, and `deactivateEmployee` only flips the Firestore field. All of it runs AFTER the auth-critical bridge write and is idempotent (`retry: true`; `auth/user-not-found` is swallowed so the delete-account ordering converges).
- **Disabled employees must not read their old jobs.** `isAssignedEmployee` (`firestore.rules`) and `isAssignedToAppointment` (`storage.rules`) both gate on `status == 'active'`, NOT on bridge-doc existence — the bridge doc is deliberately retained for `disabled` users, so an existence-only check leaves a terminated tech reading client PII and job photos indefinitely. Keep the two helpers in lockstep.
- `placesAutocomplete` — proxies Google Places API (New) autocomplete. Requires App Check + auth + `assertAdmin` (address autocomplete is only surfaced on the admin-only appointment form, so gating on admin keeps a non-admin from scripting the billable API). Key in Secret Manager (`GOOGLE_MAP_API_KEY`).
- `placesGetDetails` — proxies Google Places API (New) place details. Same guards (App Check + auth + `assertAdmin`).
- `placesReverseGeocode` — proxies Google Geocoding API to convert a staff member's coordinates into a street address for the admin-only live staff map. Requires App Check + auth + `assertAdmin` + durable rate limit; returns only the top `formatted_address`; coordinates are never logged. Key in Secret Manager (`GOOGLE_MAP_API_KEY`).
- `validateUploadedImage` — Storage trigger: validates JPEG/PNG magic bytes for `appointments/*/images/*` uploads; deletes non-conforming files server-side.
- `propagateClientEdits` — Firestore `clients/{id}` update trigger: fans a client's name/phone/address edit onto that client's FUTURE appointments (the denormalized `clientName`/`clientPhone`/`address` copies). Per-appointment custom addresses (stored address ≠ client's previous address) and past/history visits are left untouched. Idempotent (absolute writes, `retry: true`); needs the `(clientId ASC, startTime ASC)` composite index. Pure helpers (`relevantClientChange`/`buildAppointmentPatch`) exported for unit tests.
- **Push notifications** (`notifications.js` + jest-testable `notification_utils.js`; functions + rules **deployed to prod 2026-07-11**; iOS-native APNs key + Push/App-Groups entitlements wired on the Mac 2026-07-11; the two ledger collections' Firestore **TTL policies were enabled 2026-07-11** — on-device verify is the only push item still pending; see the archived push-notifications plan): `notifyAppointmentChanges` (appointment write trigger → assignment/reschedule/cancel/unassign pushes; deliberately no `retry` — a duplicate push is worse than a missed one. **Repeat series are collapsed to ONE push per (employee, kind)**: a "this and all future" edit writes up to ~15 sibling docs in one client batch and each fires this trigger, which used to mean ~15 pushes and ~15× the reads for a single user action. The differ's anchor rule (`id === seriesId`) handles CREATE only — delete/cancel/reschedule batches often start partway through a series, so the anchor doc is frequently absent and an anchor-only rule would suppress *every* notification. Hence the `appointmentSeriesNotices/{seriesId}_{kind}_{employeeDocId}` claim ledger (`claimSeriesNotice`, Admin-SDK-only). It **fails OPEN** everywhere — any claim error (and, in the delete fallback, a claim with no readable `createdAt`) sends anyway; degrading to the old one-push-per-sibling behavior beats risking a dropped cancellation for a tech already driving to the job. **Two keying modes.** WRITES (create/update — after present) carry a fresh **`seriesOpId`** stamped by `_newSeriesOpId()` in `firebase_appointments_repository.dart`: one uuid per write operation, shared by every doc that operation touches and reused by no other, so an `op_<opId>_<kind>_<emp>` claim collision is DEFINITIVE (same batch) and needs **no time window** — two separate actions get different op-ids and both notify, even back-to-back. That is what fixed the "cancel Tuesday then Thursday of the same series → second push dropped" bug. DELETES have no `after`, so `before.seriesOpId` is stale (minted at the doc's last write, shared by every future delete of the series) — the call site passes `""` for a delete, routing it to the fallback `(seriesId, kind, employee)` + `SERIES_CLAIM_WINDOW_MS` (45 s, keep in seconds) + stale-takeover. **`updateAppointmentStatus` stamps `seriesOpId` ONLY on `cancelled`, never on `done`** — the employee mark-done rule is `affectedKeys().hasOnly(['status','updatedAt'])`, so a stray field there is `permission-denied`; cancel is admin-only. `seriesOpId` is write metadata, NOT on `AppointmentRecord`. Build the claim's `.doc()` ref INSIDE the try — `.doc()` throws synchronously on an id containing `/`, and an escape here would kill every push for the write instead of degrading), `sendUpcomingJobReminders` (every 5 min, **travel-aware "time to leave" reminder** — `runTravelAwareReminderSweep` in `travel_utils.js`; per (job, assignee) it decides an origin [intervening job's address → fresh background-GPS presence ≤25 min → recently-ended job's address ≤4h → none], calls Google Routes API `computeRoutes` with `TRAFFIC_AWARE`, and fires at `startTime − driveTime − 10min`; **every failure path — no origin, empty address, any Routes error — degrades to the fixed 30-min `reminder` kind**, so it never regresses below the old behavior; `leaveNow` kind sets APNs `interruption-level: time-sensitive`. Reuses the existing `appointmentReminders/{id}_{startMs}_{employeeDocId}` ledger and key format, so claims from before the upgrade stay honored. The per-employee origin-context read is bounded by `CONTEXT_QUERY_MAX` (`travel_utils.js`), ordered `endTime` ASC so the cap keeps the just-ended/imminent jobs `decideOrigin` actually uses — don't remove the `.limit()` or the query re-reads every future appointment each sweep. Its `endTime` upper bound is `TRAVEL_WINDOW_MS + MAX_BOOKING_MS`, **not** the travel window: an intervening job can start inside the window and still run a full day longer, and narrowing the bound to the window silently drops it from `decideOrigin`'s first prong. The sweep also memoizes drive-time estimates per (job, assignee) for `ESTIMATE_TTL_MS` so a job sitting in the 90-min window isn't re-priced ~18 times to fire once — a cached estimate may only ever DEFER a Routes call (by `SKIP_MARGIN_MS`), never trigger a send; the fire decision is always made against a fresh response. Needs the Routes API enabled + added to the `GOOGLE_MAP_API_KEY` restriction), `sendDailyJobDigest` (18:00 Toronto), and `sendOverdueJobPrompts` (every 15 min, "job finished?" nudge for jobs past `endTime` but still open — server mirror of the display-only `overdue` state, keep in sync with `AppointmentRecord.displayStatus`). Recipients always filtered to active employees; tokens in `users/{docId}/fcmTokens/{token}` (per-device `locale` drives EN/FR text). Idempotency via Admin-SDK-only **per-recipient** ledgers `appointmentReminders/{id}_{startMs}_{employeeDocId}` and `appointmentOverduePrompts/{id}_{endMs}_{employeeDocId}` (create()-fails-if-exists; any claim — reminder OR overdue — with zero delivered pushes is released for retry, keyed per assignee so a late-registering token is retried without re-notifying an already-delivered assignee; both write `expiresAt` +7d for a console-enabled Firestore TTL — see the TTL-offset rule under Cloud Functions). The overdue sweep queries `startTime` over 48h (24h eligibility + <24h max booking) **ordered `startTime` DESC** (existing `(status, startTime DESC)` index) so the `OVERDUE_SWEEP_MAX` cap keeps the newest-overdue jobs, not the oldest — don't drop the `orderBy` or "simplify" it to an `endTime` query without adding an index. (Travel-aware sweep + audit hardening **deployed to prod 2026-07-18**.)
  - **Client side:** `PushRegistrationController` (`features/notifications`) registers this device's FCM token for active employees AND admins (`shouldRegisterPush` — admins register only for the timed nudges; the server withholds change-driven pushes from them), keyed by the users-doc id at `users/{docId}/fcmTokens/{token}`; `AppSyncListeners` (`core/app/app_sync_listeners.dart`, registered from `main.dart`) drives `sync()` on every account-doc emission + on language change (re-upserts `locale`). A notification tap AND an iOS home-screen widget tap both deep-link to the appointment detail sheet.
  - **Live-location presence** (`features/presence`, `geolocator`, backs the travel-time reminders): `PresenceSyncController` mirrors `PushRegistrationController` (provider + `main.dart`-driven `sync()` on every account-doc emission; both — and the Live Activity registration controller — get their coalesce-not-drop reentrancy from the shared `ReentrantSync` mixin (`core/utils/reentrant_sync.dart`), so `sync()` sets the guard synchronously before its first await and a concurrent call re-runs exactly once with the latest state; don't re-inline `_busy`/`_pendingResync`) and owns a **foreground-only** `getPositionStream` for active employees AND admins (`shouldTrackPresence` **delegates to** `shouldRegisterPush`, so the presence audience can't drift from the push audience — never re-inline the predicate body). **The `location` UIBackgroundModes entry was REMOVED 2026-07-27 after an App Store rejection under guideline 2.5.4** ("using the location background mode for the sole purpose of tracking employees is not appropriate") — iOS now suspends the stream whenever the app is backgrounded, and that is intended. **Never re-add `location` to `UIBackgroundModes`, never re-add `NSLocationAlwaysAndWhenInUseUsageDescription`, and never request an Always upgrade** (`LocationPermissionService.ensureLocation` deliberately issues exactly ONE prompt — the second, escalating `requestPermission()` call was removed; a pre-existing Always grant is still honored, we just never ask). `AppleSettings.showBackgroundLocationIndicator` was dropped for the same reason: it only means anything for a stream that survives backgrounding. `geolocator` gates `allowsBackgroundLocationUpdates` on the Info.plist key itself (`GeolocationHandler.shouldEnableBackgroundLocationUpdates`), so the removal degrades cleanly instead of throwing. It writes `users/{docId}/presence/location` (`{lat, lng, uid, updatedAt: serverTimestamp()}`, self-only rules, `updatedAt == request.time` so freshness can't be spoofed) throttled to 250 m of movement / ≥2 min per write, plus a 10-min heartbeat re-upsert so a *stationary* tracker stays fresh (server staleness window is `PRESENCE_STALE_MINUTES = 25` in `travel_utils.js` — a live heartbeat sits well inside it). A *failed* write rolls the throttle clock back (`upsertLocation` returns `PresenceWriteResult.ok/failed/denied`) so a dropped write can't suppress the next fix and let the doc drift toward the staleness window; a **`denied`** result additionally calls `_stop()` — the rules gate presence on an active account, so a deactivated user's background stream would otherwise log a denied write every heartbeat until the app is killed (the 11-event Crashlytics spam of 1.32.0; next `sync()` on resume/account-emission re-runs the gate). Expected stream deaths (permission revoked / Location Services off, incl. the iOS `kCLErrorDomain error 1` surfaced as `PositionUpdateException`) are classified by `_isExpectedLocationLoss` and logged WITHOUT a Crashlytics error record. OS location permission is the only switch: a denial degrades silently (server falls through its address→30-min chain). **Because presence is now foreground-only, a backgrounded device's doc goes stale within `PRESENCE_STALE_MINUTES` and the travel-aware sweep routinely falls back to the intervening/recent job address, or to the fixed 30-min `reminder` kind — that fallback is the normal path now, not an error case.** `decideOrigin`'s presence prong still fires whenever a tech has the app open (the common case while reviewing the day's route), so keep it. Torn down + presence doc deleted on sign-out/delete (beside `unregisterCurrentDevice`). The position stream is **device-only** verification (no geolocator channel tests). iOS needs only `NSLocationWhenInUseUsageDescription` in `Info.plist`; the Time Sensitive Notifications entitlement (for `leaveNow`) is Mac-side. **Admin live staff map read path:** admins read ALL presence via a collection-group rule (`match /{path=**}/presence/{presenceId}` read if `isAdmin()`; the wildcard reserves the subcollection name `presence`); the client joins `collectionGroup('presence')` to `watchAllUsers()` on the admin-only Live map hub tab; `presenceStaleAfter` (Dart, `lib/features/presence/domain/live_map_aggregator.dart`, 25 min) must stay in sync with `PRESENCE_STALE_MINUTES` in `functions/travel_utils.js`. **Staleness is surfaced as TEXT only** — the freshness labels in the info card + roster (`LiveMapAggregator.isStale`/`freshnessOf`); the **map marker itself is never dimmed/greyed** (the `staleDocIdsProvider` + marker-dimming path was removed 2026-07-19, and `StaffMarkerIconRenderer` has no `stale` param), so don't reintroduce pin greying. Presence docs are server-purged by `syncUsersByUid` (`functions/bridge.js`) when a user doc is deleted or status leaves `'active'` (purge runs AFTER the auth-critical bridge write, isolated try/catch) — see the deactivation invariant under Cloud Functions for the rest of that purge. The map's **staff roster sheet** (`staff_roster_sheet.dart`) lists everyone sharing location; ordering, haversine distance, and nearest-city parsing are pure functions on `LiveMapAggregator` (`sortedByProximity`/`distanceMeters`/`cityFromAddress` — self row leads, rest nearest-first) so they test without the geolocator/Maps plugins. Location permission is gated by `LocationPermissionService` (`core/permissions`, `geolocator`; `whileInUse`/`always` both count as granted).
  - **iOS home-screen widget** (`features/home_widget` + `ios/ScheduleWidget`, `home_widget` package, iOS-only): `WidgetSyncService` writes a **two-day** payload into the App Group `group.net.vogas.scheduling` — `todayJobs` (remaining, non-terminal), `tomorrowJobs`, and a `rolloverAt` instant so WidgetKit flips today→tomorrow on-device with no app run (set only once today has no incomplete job left). The widget payload's `startTime` MUST be an absolute UTC instant (`toUtc().toIso8601String()`, …Z) — a bare local `toIso8601String()` has no zone designator and the Swift `ISO8601DateFormatter` can't parse it. The Dart builder (`buildWidgetPayload`, `widget_sync_service.dart`) and the server builder (`functions/widget_payload_utils.js`) are hand-mirrored — keep them and the Swift decoder in lockstep. **Known divergence:** the server resolves day boundaries in `America/Toronto`; the Dart mirror uses device-local midnight — harmless for this single-timezone (Quebec) business, but on an off-Toronto device the app-written and push-written payloads can disagree on which day a job is "today". **All-day blocks narrow that margin to zero:** a timed 2 p.m. job needs a ~10 h offset to change days, but an all-day block starts *at* midnight, so any westward device offset flips its bucket and the widget's contents depend on which writer went last. Still accepted (single-timezone business) — but this is the first thing to fix if the app ever ships outside Quebec. Widget/notification taps use the `esproschedule://appointment?id=…` deep link.
  - **Widget refresh while the app is closed:** change-driven pushes carry a fresh `widgetPayload` + APNs `content-available`, so `firebaseMessagingBackgroundHandler` (`core/notifications/fcm_background_handler.dart`, registered via `FirebaseMessaging.onBackgroundMessage` in `main()`) rewrites the widget in a fresh OS-spawned isolate — without it the widget only updated while the app ran. It MUST stay a top-level `@pragma('vm:entry-point')` function, iOS-gated, and dependency-light (only the `home_widget` channel after `WidgetsFlutterBinding.ensureInitialized()`; NO `Firebase.initializeApp`/Firestore/Riverpod in the isolate).
  - **iOS Live Activities — "time to leave" card** (`features/live_activity` + `ios/ScheduleWidget/JobLiveActivity.swift`, `live_activities` package, iOS 17.2+, **built 2026-07-19; DEPLOYED to prod + on-device card-start VERIFIED on real hardware 2026-07-20. The Lock Screen card renders and is started by the `leaveNow` sweep end-to-end; the Dynamic Island presentation is still unverified — the test device is a base iPhone 14, which has no Dynamic Island (Pro-only hardware)**): a Lock Screen / Dynamic Island card started by the travel-aware `leaveNow` sweep and ended when the job completes. **FCM cannot send Live Activity pushes** (they need `apns-push-type: liveactivity` on topic `net.vogas.scheduling.push-type.liveactivity`), so this is the one path with a **direct APNs HTTP/2 client** (`apns_client.js`, ES256 provider JWT cached and re-minted at 50 min; secrets `APNS_AUTH_KEY`/`APNS_KEY_ID`/`APNS_TEAM_ID`). **APNs environment: `sendLiveActivityPush` tries the PRODUCTION host, then retries the SANDBOX host on a `BadDeviceToken` response** (added 2026-07-20). This is load-bearing for *any* dev-signed build: a `flutter run` build ships an `aps-environment: development` provisioning profile, so its push-to-start token is a SANDBOX token that the production host rejects with `BadDeviceToken` → the card would never start (the plain `leaveNow` push still works because FCM auto-routes APNs environments; the direct client does not). The retry only fires when the production push did NOT deliver, so a production (TestFlight/App Store) token that succeeds on the first host is never re-sent — no duplicate-card risk. Don't remove the sandbox fallback thinking "prod only." **Every Live Activity path is additive and best-effort** — no token, no secrets, iOS < 17.2, Live Activities disabled, or any APNs failure all degrade to the existing `leaveNow` push, which fires independently and is unchanged; nothing in the reminder pipeline gains a new way to fail. Keep it that way. The start hangs off `deliverRecipientOnce`'s **return value** (`kind === 'leaveNow' && delivered > 0`) so it inherits that ledger's exactly-once claim — a start placed before the claim double-fires on a collision. **`liveActivityCards/{employeeDocId}` (Admin-SDK-only) is load-bearing, not a convenience:** a push-*started* activity's id is minted by ActivityKit and its attributes can't be read back, so the device physically cannot stamp `appointmentId` on its own token row — the server owns that association, and update/end resolve through the marker (resolving by employee alone would let a cancel on next week's job kill the card for the job the tech is driving to). The travel→on-site flip is **clock-derived on both sides** (mirrors `AppointmentRecord.displayStatus`); **no `markInProgress` write path exists or should be added**. Both the flip and the end are **server-owned**: `runOnSiteFlipPass` must run on every sweep — not only when there are travel candidates, since a tech whose job already started is by definition no longer a candidate — and **every terminal transition ends the card via `endCardOnTerminal` in the appointment write trigger: done, cancelled, DELETED, and unassigned, deliberately UNCONDITIONAL on the job's start time** (generalized from done-only `endCardOnCompletion` 2026-07-21; the notification diff suppresses events for past-start jobs via `notPast`, which is exactly when a live card exists — riding the diff left a deleted/cancelled started job's card stuck on the Lock Screen). `runOnSiteFlipPass` is the backstop for the same bug: a marker whose appointment is deleted/terminal must END the on-device card (`endLiveActivity`), never just clear the marker — the card outlives the Firestore doc. Keep the explicit `clearCardMarker` after that backstop end: `endLiveActivity` returns before clearing the marker when no token rows remain. The client must never end cards off its own status write (`endAllActivities()` is device-wide, so completing job B would kill the card for job A). "Complete" is a **deep link** into the appointment sheet, never a new authenticated write surface in the extension. Card text is built server-side in EN/FR from the `_MESSAGES`-shaped table in `live_activity_utils.js` — never `NSLocalizedString` in Swift, which would fork translations outside the ARBs. `buildContentState`/`buildAttributes` and `ios/ScheduleWidget/LiveActivitiesAppAttributes.swift` are hand-mirrored — the content state carries `endTime` (added 2026-07-21) so the on-site card counts DOWN the remaining booked time to the scheduled end (`Text(timerInterval:countsDown:true)`, a live system timer that ticks without pushes); past the end — or on a payload with no `endTime` — it falls back to the elapsed count-up from the start, which honestly signals the overrun. Thread `endTime` through every dispatch `ctx` (sweep candidate, on-site flip, reschedule update) or the next update push silently drops the countdown. **A travel-phase card with no known `leaveAt` must NEVER label the job's own `startTime` as "Leave at"** — `buildContentState` renders the `startsAt` string ("Starts at" / "Débute à") in that case. The old fallback silently presented the appointment time as the departure time, so a rescheduled job told the tech to leave exactly when they were due to arrive (fixed 2026-07-27). Only the sweep knows a real lead, so `writeCardMarker` persists `leadMinutes`/`travelMinutes` on `liveActivityCards/{employeeDocId}` at card start and `updateLiveActivity` rebuilds `leaveAt = newStart − leadMinutes` from the marker (`_withLeaveAt`) — that's why the reschedule hook can pass `leaveAt: null` and still render a correct departure time. `setCardStart` merges, so it must never overwrite those two fields. `_liveRowsFor` returns `{rows, marker}` (not a bare array) to feed that rebuild without a second marker read. Note `live_activity_dispatch.js` defines its own `MINUTE_MS` rather than importing it from `travel_utils.js` — that module requires this one, so reaching back would close a cycle. **The on-site backstop (`listCardsDueForOnSite`) keys the flip off `marker.startTime`, so `updateLiveActivity` must refresh it via `setCardStart` (merge start+phase) on EVERY update, not just the flip** — a reschedule that left the stale start flipped a job moved earlier past the tech's real arrival and re-pushed a travel update every sweep for a job moved later (the old `setCardPhase` wrote phase only; don't reintroduce it). **The reschedule card refresh runs per-occurrence, ABOVE the series-claim gate** in `handleAppointmentWrite` (unlike the push): the claim collapses an "all future" reschedule to one push per (employee, kind) and which sibling wins is nondeterministic, but the card is per-occurrence, so each sibling's own trigger must refresh its own card — `updateLiveActivity` is a cheap marker-read no-op for any occurrence that isn't the live card, and a deactivated employee has no marker/tokens so it can't resurrect a card (no `delivered > 0` guard needed there). **The ActivityAttributes type MUST be named exactly `LiveActivitiesAppAttributes`** (renamed from `JobActivityAttributes` 2026-07-19): the `live_activities` Flutter plugin registers the push-to-start AND per-activity update-token streams against `Activity<LiveActivitiesAppAttributes>` — a type of that exact name — so the device token the server pushes to only resolves when the name agrees in three places: the widget struct, the widget's `ActivityConfiguration(for:)`, and the server's `ATTRIBUTES_TYPE` (`live_activity_utils.js`). Rename any one and every push-to-start/update/end fails silently (degrades to the plain `leaveNow` push). Because the plugin (linked into Runner) owns token observation against its own copy of that type, the widget's `LiveActivitiesAppAttributes.swift` lives ONLY in the ScheduleWidget extension target — **do NOT add it to the Runner target** (the plugin, not app-native code, drives `pushToStartTokenUpdates`). **Xcode integration landed 2026-07-19** — the `WidgetBundle` `@main` hosts `JobLiveActivity` and the whole `ios/ScheduleWidget/` group builds clean at the new iOS 18.0 floor (the earlier "stay at 15.0, no bump" plan was superseded — the Directions button's returnable `OpenURLIntent` is iOS 18+, so the app moved to 18; every Live Activity path is still `@available(iOS 17.2, *)`-gated internally). `APNS_AUTH_KEY`/`APNS_KEY_ID`/`APNS_TEAM_ID` now exist in Secret Manager (created 2026-07-19), so a deploy no longer fails at secret binding. **Deployed to prod + card-start verified on device 2026-07-20** (via the sandbox fallback above; the missing `firestore:indexes` — see below — were the reason the first attempts produced only the push and no card, exactly as this file warned). **Only the two functions that bind `APNS_SECRETS` may read them** — `notifications.js` splits `liveDeps()` (no `apnsAuth`) from `liveActivityDeps()` (with it), because reading a secret param a function didn't bind logs a "No value found for secret parameter" warning on *every* invocation; the digest and overdue sweeps are Firestore-only and must keep using `liveDeps()`. Device-side capability (iOS 17.2+, ActivityKit available, Live Activities not switched off in iOS Settings) is probed in exactly one place — `LiveActivityRegistrationController.canHostCards()`, which never throws — and backs both `_ensurePlugin()` and the Settings row's `liveActivitySupportedProvider`; don't re-probe the plugin anywhere else. **The user's opt-out cannot be a local flag alone:** the card is *push-started* by the server, so `liveActivityEnabledProvider` (SharedPreferences, device-local, **default on**) only stops a later `sync()` from re-registering — the Settings toggle itself must call `unregister()` to end the live card and delete this device's token rows. `unregister()` deletes the push-to-start row **by kind, via query** (`deleteTokensOfKind`) and re-resolves the users-doc id when `_docId` is unset — the row's doc id IS a token this session may never have seen, and a cold start with the preference already off returns from `_syncGuarded` before `_docId` is set. A cold-start `sync()` MUST `await` the preference's `ready` future before acting on it, or the optimistic `true` default silently re-registers an opted-out device. Two **composite indexes are what make the feature work at all** — `liveActivityTokens` `(kind, employeeDocId)` at COLLECTION_GROUP scope and `liveActivityCards` `(phase, startTime)`; without them every registry query fails `FAILED_PRECONDITION`, the best-effort catch swallows it, and the card silently never appears. Deploy `firestore:indexes` with the functions. Mac runbook + device checklist: `ios/ScheduleWidget/LIVE_ACTIVITY_README.md`.
  - **Siri App Intents snapshot** (`features/siri` + `ios/SiriIntents`, iOS-only, **Phases 1–3: Dart + Swift landed 2026-07-19; the `SiriIntents` App Intents extension target was created + embedded in Runner 2026-07-19 and builds clean (bundle id `net.vogas.scheduling.SiriIntents`, entitlements `SiriIntentsExtension.entitlements` sharing the App Group, iOS 18.0). Phase-1 read intents (count / today / next), Phase-2 date intents (`TomorrowScheduleIntent` deterministic, `DayScheduleIntent` for any in-window day), and the Phase-3 `NthAppointmentIntent` ("read a specific appointment" → Siri prompts for a position) are all code-complete and pass the App Intents metadata compiler; on-device Siri phrase verification still pending — see `ios/SiriIntents/README.md`. Phases 2–3 added NO Dart/schema change (the snapshot already carries all 8 buckets). Note: a `Date` OR `Int` parameter cannot be interpolated into a spoken App Shortcut phrase (Siri only allows AppEnum/AppEntity there), so `DayScheduleIntent` and `NthAppointmentIntent` carry no such value in their phrases and Siri resolves it via its own locale-aware follow-up prompt ("For what day?" / "Which appointment?") — this prompt→answer is the only in-session multi-turn App Intents supports (there is no free-form "and tomorrow?" session), so don't "fix" it into a phrase parameter. A new `.swift` in `ios/SiriIntents/` must be hand-added to the target in `project.pbxproj` (all four sections)**): `ScheduleSnapshotService` writes a **today + 7 days** payload into the *same* App Group `group.net.vogas.scheduling` under a **separate key `schedule_snapshot`** (the widget's `schedulePayload` is untouched; the snapshot deliberately does NOT call `HomeWidget.updateWidget` — nothing renders it). Role-aware: employees get `myAppointmentsProvider`, admins the business-wide `appointmentsInRangeProvider`. Both off-screen schedule mirrors (this and the home-screen widget) resolve *who* they're for through the single `activeUserIdentityProvider` (`features/auth/application/active_user_identity_provider.dart` — active-status gate, employee-or-admin, `retryAsync(findUserByUid)` for the post-sign-in token lag); it returns `(role, docId)` and returning null is what wipes both mirrors on sign-out. Route any new mirror through it rather than re-deriving the identity. Both must also `ref.watch(currentDayProvider)` (`core/utils/`) for their day bucketing instead of a bare `DateTime.now()` — their appointment streams only re-emit on a write, so an app resident across midnight otherwise keeps publishing yesterday's buckets and Siri answers "no appointments today" while jobs exist. `buildScheduleSnapshot` (`siri/domain/schedule_snapshot.dart`) and the Swift `ScheduleSnapshot.swift` decoder are hand-mirrored — change one, change both, and bump `version` on both sides of a schema change. Cancelled visits and **records with a null/empty `id` are dropped at build** (Phase-4 write actions resolve their target by that id). **Sign-out wipes the snapshot implicitly** — `scheduleSnapshotProvider` emits `data(null)` and `AppSyncListeners._snapshotSync` (`core/app/app_sync_listeners.dart`) calls `clearSnapshot()`; don't add an explicit sign-out clear (same contract as the widget). The App Group stays readable while the device is locked, so the payload carries **only the fields the intents speak** (client name, times, address, status) — never notes, phone, or pictures. **Phases 1–3 keep the extension Firebase-free and network-free**; Phase 4 breaks that deliberately as its own reviewed increment (it's also blocked on App Attest's bundle-ID binding — see the implementation plan).
  - **Notification permission recovery:** Settings has a Notifications row (`notificationAuthStatusProvider`, read WITHOUT prompting) — `notDetermined` re-shows the one-time OS prompt; any other non-granted state (or a granted tap) opens system Settings, since iOS never re-shows the dialog once answered. On return (app-lifecycle `resumed`) it invalidates the status provider and re-runs `PushRegistrationController.sync()` so a just-enabled device actually stores its token.
- **Wave Accounting** (`functions/wave/*`): admin callables (`waveBootstrap`,
  `waveImportCustomers` — App Check + `assertAdmin` + `enforceDurableRateLimit`),
  the read-only `waveGetConnection` (admin + App Check; **no secret, no rate
  limit** — it only reads the `wave/connection` doc), `waveSetImportSchedule`
  (admin + App Check, no secret/rate limit — writes the `importSchedule` field
  on `wave/connection`), the `waveUpsertCustomer`
  `clients` trigger that enqueues an outbox job, the scheduled
  `waveSyncWorker` that drains the `waveSyncQueue` collection, and the daily
  `waveScheduledImport` (server-triggered `onSchedule`, so no App Check/rate
  limit) which re-runs `importCustomers` only when the configured cadence is due.
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

**A TTL policy only deletes docs that HAVE the field**, exactly like the
`where("expiresAt", ...)` sweeps — Firestore excludes documents missing the
filter field. So any client-writable TTL field must be **required** in the
rules, not merely bounded when present, or a modified client can mint rows no
reaper can ever reach (see the `liveActivityTokens` rule).

**Firestore TTL policies must use expiration offset `0`.** Every collection that
writes an `expiresAt` (`appointmentReminders`, `appointmentOverduePrompts`,
`appointmentSeriesNotices`, `liveActivityTokens`, `liveActivityCards`,
`rateLimits`, `signupCodes`) stores
the *absolute* deletion instant — the lifetime is already baked in by
`LEDGER_TTL_MS` / `INVITE_CODE_TTL_MS` / `CARD_TTL_MS` / the limiter window. The
console's "expiration offset" ADDS to that value, so any non-zero offset
silently multiplies retention (the ledgers ran at ~14 days instead of 7 until
2026-07-20). An offset is **immutable once set**: correcting one means delete →
wait for the policy to disappear from the list → recreate, or the create fails
`400: Cannot modify TTL offset`. A policy can only be created for a collection
group that already holds documents. TTL is housekeeping only — every one of
these is also swept in-code, so a missing policy is never a correctness bug.

Deploy: `firebase deploy --only functions,firestore:rules,firestore:indexes,storage`
(drop `firestore:indexes` only when `firestore.indexes.json` is unchanged — a
query whose index is missing fails `FAILED_PRECONDITION`, which best-effort
callers swallow into a silent no-op.)
(`storage:rules` is **not** a valid deploy target — use `storage`.)
Always run `cd functions && npm run lint` before deploying (Google ESLint, 80-char line limit).

`GOOGLE_MAP_API_KEY` lives in Secret Manager only — it is **not** in `dev/.env`.

App Check emulator setup: run app once → search Logcat for `DebugAppCheckProvider`
UUID → register it in Firebase Console → App Check → your Android app → Manage
debug tokens. The UUID is stable per AVD but changes on new AVDs or full
reinstalls — re-register when it does. An unregistered token causes all Firestore
writes and non-cached reads to fail with `permission-denied` while cached reads
still succeed, making the failure appear collection-specific.

## Testing

- Wrap widgets using `ThemeNotifier.of(context)` in a full `ThemeNotifier(..., child: ...)`.
- Use `_scaledHarness` (Size 260×640, textScaler 2.0) to catch overflow.
- Policy classes (`ClientSearchPolicy`, etc.) test with `test()` — no Firebase needed.
- `ImagePickerService` / `ImageStorageService` have no unit tests — they depend
  on method-channel plugins. Verify image-related fixes via `flutter run` on a device.
- `AppLogger` resolves `FirebaseCrashlytics` lazily, so controllers using
  `loggerProvider` in `catch` blocks don't need Firebase set up in tests.
- AutoDispose providers in tests need
  `container.listen(provider, (_, _) {})` in `setUp` so the family-keyed
  state survives across reads.
- Mocktail's `captureAny()` returns `Map<Object, Object?>`, not
  `Map<String, dynamic>`. Direct `as Map<String, dynamic>` cast throws at
  runtime. Use `(captured as Map).cast<String, dynamic>()` instead.
- Repositories that accept optional deps (e.g. `FirebaseEmployeesRepository`
  takes `auth`) must have those deps passed explicitly in tests — never let
  the constructor fall back to `FirebaseAuth.instance` or any singleton.
- Widgets that call `context.l10n` (including `StatusChip`) require
  `localizationsDelegates: [AppLocalizations.delegate, GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate]`
  and `supportedLocales: AppLocalizations.supportedLocales` in their test `MaterialApp`.

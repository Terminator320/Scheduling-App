# CLAUDE.md

Flutter app (Dart `^3.10.7`) for managing appointments, clients, and employees.
Backend: Firebase (Auth, Firestore, Storage, App Check). **iOS is the only
platform.**
**Ships to the App Store ONLY (decision 2026-07-08), and `android/` was
DELETED on 2026-08-05** (owner call) once development moved from a Windows box
to a Mac and iOS could build and run locally — Android had only ever been the
dev/test harness that gave that Windows box something runnable, and it was
never published to Play. Don't re-add it, don't restore Play-release work
(keystore, Data Safety, Play Integrity), and don't "fix" an iOS-only assumption
by reintroducing an Android branch. Recover the tree from git history if it is
ever genuinely needed. **`/android/` is now in `.gitignore`, and that entry is
load-bearing** (2026-08-08): a merge (`33715f82`) silently resurrected the tree
and brought `android/local.properties` with it, which carries a live
`MAPS_API_KEY` — a committed secret. `flutter` regenerates that directory on any
Android-touching command, so ignoring it is the only thing that stops a second
resurrection; deleting the files alone does not. Don't remove the entry to
"restore" an Android build. Two Android remnants survive **deliberately** and are
not dead code to clean up: `DefaultFirebaseOptions.android` (the Android
Firebase app still exists in the console, and the shared `dev/.env` keys feed
it) and the `platform: 'ios' | 'android'` field on `fcmTokens` docs, which the
CURRENT build still writes — `push_registration_controller.dart` stamps
`Platform.isIOS ? 'ios' : 'android'`, so on an iOS-only fleet the value is
always `'ios'` but the write is live code, not a legacy row. (An earlier note
here credited the 1.37.1 App Store build for it; that was wrong even then, and
retiring the shim on 2026-08-08 changed nothing about this field.)
**`web/`, `windows/`, `linux/` and `macos/` STAY** (owner call, 2026-08-05,
asked and answered when `android/` went). They are untouched `flutter create`
boilerplate for platforms nothing targets or builds — leave them alone; their
presence is not evidence that any of those platforms is supported. In
particular `macos/Podfile` is scaffold, not a CocoaPods setup, and does not
contradict the SPM-only rule in `ios/CLAUDE.md`.

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
flutter analyze   # baseline is `No issues found!` — any lint you see is yours
```

## Required environment

`dev/.env` (gitignored, bundled as asset). 8 keys: `FIREBASE_API_KEY`,
`APP_ID`, `MESSAGING_SENDER_ID`, `PROJECT_ID`, `STORAGE_BUCKET`, plus the iOS
pair `IOS_API_KEY`, `IOS_APP_ID` (read in `lib/firebase_options.dart` to build
the iOS `FirebaseOptions`), plus `IOS_MAPS_API_KEY` (iOS client Google Maps
key, parsed natively by `AppDelegate.swift`). The first five are still required
even though only iOS ships: three of them are platform-neutral, and
`FIREBASE_API_KEY`/`APP_ID` still back `DefaultFirebaseOptions.android`.
`IOS_MAPS_API_KEY` is a RESTRICTED CLIENT key — distinct from the server-side
Secret-Manager `GOOGLE_MAP_API_KEY`, which must never ship in the app.

- **`dev/.env` holds Firebase client config plus RESTRICTED client keys (e.g. `IOS_MAPS_API_KEY`) only.** It's an asset bundled into the IPA, so anything in it ships in the binary — restrict those keys app-side (bundle ID / package + API restrictions) in the Google Cloud Console. Server-side or unrestricted keys (Stripe, OpenAI, admin tokens, `GOOGLE_MAP_API_KEY`) must live in Google Secret Manager and be read from a Cloud Function — never in `dev/.env`.

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
  `completeEmployeeSetup` activates its doc), NOT a deletion. Never simplify back to
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
  Resolve the active set through the ONE owner, `_resolveActiveEmployees`
  (`event_details_controller.dart`), which awaits `watchEmployees().first` —
  never a cached provider value, and never a `.value ?? []` read. The await is
  the point: a cold or empty stream value at save time makes every original
  assignee look inactive, so all of them are retained and a real deselection is
  silently undone. (This bullet previously described a two-tier "cached value
  falling back to a fresh read" that the code does not have and should not
  grow — the single awaited read is both simpler and strictly safer.)
  **`employeeIds` and `employeeNames` are paired POSITIONALLY, and the bounds
  check has one owner: `assigneeNameAt(names, i)`** (same file, returns null for
  "no name here"). It was re-spelled at five sites; the differing missing-name
  fallbacks around it are legitimately per-surface (the day route shows the id,
  the history filter shows nothing), so the helper owns only the LOOKUP and each
  caller keeps its own substitute. The edit-sheet copy is the dangerous one — a
  blank name there flows into `mergeRetainedAssignees` and is written back.
- **Image validation:** Reject uploads where first 4 bytes aren't JPEG
  (`FF D8 FF`) or PNG (`89 50 4E`). Extension alone is not sufficient.
- **Image upload pipeline:** Single stage — `ImagePickerService` resizes +
  JPEG-compresses at pick time (`image_picker` `maxWidth/maxHeight: 1600`,
  `imageQuality: 70`); `ImageStorageService` then validates magic bytes and
  uploads. `ImageCompressService` was removed — don't reintroduce a second
  compression pass. Background dispatch via `AppointmentImageUploadService`
  after appointment save; the picker's temp files are deleted in a `finally`.
- **Photos are RENDERED from `storagePath`, never from the persisted `url`**
  (2026-08-08). `getDownloadURL()` mints a permanent `?alt=media&token=…` URL
  that anyone holding it can read with **no auth and no rules evaluation**, so a
  URL captured while an employee was active kept working after
  `deactivateEmployee` disabled their Auth account and revoked their tokens —
  which is exactly what `storage.rules`' `status == 'active'` gate on
  appointment images exists to stop. `AppointmentImageUrlResolver`
  (`core/images/`) resolves at render time so every read re-evaluates the
  rules, and falls back to the stored `url` only when `storagePath` is empty on
  a legacy doc — that fallback is why this needed no migration.
  **A RULES REJECTION MUST NOT FALL BACK** (2026-08-11): the resolver's `catch`
  used to be unconditional, so the one error it exists to convert into a blank
  tile — a `permission-denied`/`unauthorized` from the `status == 'active'`
  gate — was converted straight back into a working, rules-free token URL. It
  now returns `''` for those two codes and keeps the fallback for everything
  else (offline, transient Storage failures), which say nothing about
  entitlement. An empty resolved URL is therefore a REFUSAL, not a pending
  resolve: `PhotoPickerSection` renders the error tile and keeps it untappable,
  and `buildImageProviders` substitutes a 1×1 transparent image rather than
  dropping the entry — the viewer opens at an INDEX, so dropping one would
  shift every photo beside it.
  `ImageStorageService` **still writes `url`**, deliberately: builds that
  predate the resolver render from it, so dropping the write now would blank
  photos on any phone that hasn't updated. Retire it once the fleet has moved,
  the way the 1.37.1 shim was retired.
  **Resolved URLs are POSITIONAL, so they must be carried with the list they
  were resolved for** — `PhotoPickerSection` keys them on `_resolvedFor` and
  serves `const []` until that matches `existingImages`. A Storage round-trip
  per photo is a real window, not "a frame or two": a partial or stale list
  shifts every index beside it, so removing photo 0 rendered the *deleted*
  photo, an untapped placeholder opened a NEW photo, and the viewer's
  `initialIndex` (composed as `existingUrls.length + i`) ran past the end of
  the provider list and threw a `RangeError` out of Save/Share. Offset a
  viewer index by the URLs actually handed to the viewer, never by
  `existingImages.length`; `ImageViewer.open` also clamps, as depth.
- **Photos are MOVING to `appointments/{id}/images`, and phase 1 writes BOTH
  stores** (2026-08-13). Every appointment document carried its whole photo
  array — a `url` alone is ~215 of a ~290-byte entry — and the calendar reads
  up to 1000 appointments at a time while only the detail sheet ever shows a
  photo. **The `pictures` array is still written and is still authoritative.**
  The shipped build (1.45.0+72) reads photos off the parent document and knows
  nothing about the subcollection, so dropping the array now blanks every photo
  on every phone until it updates; it goes at the CONTRACT step, once no device
  still runs a build that reads it — the same gate the `#compat-1.37.1` shim
  waited on. Do not "finish the migration" by deleting the array early.
  **`appendAppointmentPictures`/`removeAppointmentPictures` write both stores in
  ONE `WriteBatch`** so they cannot disagree: this path is retried by the
  offline queue, which has no way to reconcile a half-written state.
  **The subcollection document id is DERIVED from the photo —
  `appointmentImageDocId` (`calendar/domain/policies/`), hand-mirrored as
  `functions/appointment_image_ids.js`.** That is what makes the write
  idempotent, and it REPLACES the `arrayUnion` dedupe the array form depended
  on (which worked only because every image serialized its exact `uploadedAt`
  and `arrayUnion` compares maps by deep equality — one field serialized a hair
  differently and it silently stopped deduping). It keys on `storagePath`,
  falling back to `url` for the legacy docs that have no storage path, so those
  don't all collide on one id. The two implementations share worked examples in
  their tests; change them together.
  **The subcollection doc omits `url` when `storagePath` is present** — photos
  render from `storagePath` so every read re-evaluates `storage.rules`, and a
  persisted download URL is a permanent rules-free token with no reader here.
  A LEGACY entry with only a `url` keeps it, or backfilling destroys the one
  thing that can render it.
  **Reads are "subcollection first, array fallback", and EMPTY means "use the
  array", never "this job has no photos"** — a document the backfill hasn't
  reached yet is exactly that shape. `EventDetailsController._loadStoredPictures`
  adopts the read only while the list is still what `build()` seeded, so a
  removal made during the round-trip isn't silently put back.
  **`pictureCount` is a FUNCTION-OWNED denormalized counter** (`recountAppointmentPictures`,
  an absolute `count()` aggregate — same discipline as `jobCount`), because
  `AppointmentCard` renders a photo indicator on every range-query surface and
  cannot afford a subcollection read each. `toMap()` must never emit it and the
  rules reject a client write that touches it. The card asks
  `AppointmentRecord.hasPictures`, which tests BOTH stores — during the
  migration a doc legitimately has either.
  **`cascadeDeleteAppointmentImages` is LOAD-BEARING, not cleanup: Firestore
  does NOT delete a subcollection with its parent.** Without it every
  appointment delete leaves photo documents orphaned under a parent that no
  longer exists — invisible in the console, unreachable by every query, with
  nothing reporting it. It covers all three delete paths (single, series,
  `purgeExpiredHistory`), rethrows so `retry: true` means something, and is the
  single reason a subcollection here needs a server component at all.
  Backfill: `functions/scripts/backfill-appointment-images.js` (copy-only,
  `--dry-run`, atomic per appointment so the "partially copied" state the read
  fallback can't detect is unreachable).
  **THREE THINGS THE ARRAY IS STILL DOING, which the CONTRACT step must replace
  before it is removed** — each is currently invisible because the array covers
  it, and each fails silently once it does not:
  1. **Storage cleanup on delete.** `EventDetailsController.deleteAppointment`
     enumerates `appointment.pictures` to know which Storage objects to remove.
     Empty that array and it deletes nothing, and the bytes orphan on every
     appointment delete — `cascadeDeleteAppointmentImages` removes the
     Firestore documents only. Either that trigger grows a Storage prefix
     delete (the way `purgeExpiredHistory` already does it, minding the
     load-time bucket resolution that forced `maintenance_policy.js` to split)
     or the client reads the subcollection first.
  2. **The photo-count bound.** `isValidAppointmentData` caps `pictures` at
     100; a subcollection has no such ceiling, so that guard goes with the
     array unless something replaces it.
  3. **The `AppointmentImage.url` fallback.** `AppointmentImageUrlResolver`
     still falls back to a stored `url` for legacy entries, and only the
     backfilled subcollection docs carry one. Keep the fallback.
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
  on its card and sat under the dashboard's Attention list as *overdue* —
  nagging an admin to close something "job finished?" is the wrong question
  for. (A started personal block CAN be marked complete: `DetailsActionBar`
  gates that button on `hasStarted && !isDone && !isCancelled` with no
  `isPersonal` branch. An earlier note here justified the carve-out by claiming
  personal jobs have no mark-done flow — they do; the carve-out stands on the
  wrongness of the prompt, not on the absence of a way out.)
  Never re-copy the ladder; add clock-derived rules to
  `displayStatusAt` only. The
  card/tile and the read-only detail header render `displayStatus`, but the edit
  picker and all writes seed from the real stored `status` (so `overdue` can't
  leak into a write). Don't add `overdue` to `appointmentValues` or the
  allowlist; reading `AppointmentStatus.overdue.raw` **throws** on purpose so a
  stray write path fails loudly at the source instead of emitting an
  off-allowlist value that the rules reject with an opaque `permission-denied`.
  **"Terminal" as a set of RAW STRINGS has one owner:
  `terminalStatusRawValues` in `calendar/domain/appointment_status_values.dart`**
  (2026-08-08) — `{done, completed, cancelled}`, deliberately Material-free so
  `AppointmentRecord.isClosed` and the History query's `whereIn` can share it.
  It had four definitions and the History one had dropped the legacy
  `completed` alias, so such a doc rendered as Done on its card and was
  **invisible in History and history search**, with no error anywhere.
  `AppointmentStatus.isTerminal` is the enum-level mirror and
  `appointment_status_values_test.dart` pins the two together. (`confirmed` was retired 2026-07-09 when the picker
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
  **A DONE job's edit affordance is the action bar's bottom button, not the
  top chip** (owner call, 2026-08-08): `DetailsViewBody` suppresses
  `DetailsEditChip` when the stored status is done and hands
  `DetailsActionBar.onEdit` instead, which takes over the slot the inert
  "Complete" indicator held — that job has no mark-done or cancel action left,
  so the slot was dead. `onEdit` is null-gated on the same `showActions`, so a
  read-only surface (client job history) still renders the indicator and offers
  nothing. Cancelled and open jobs keep the top chip. The two move together:
  don't restore the chip on a completed job without removing the button, and
  don't drop the button without bringing the chip back, or a finished job
  becomes uneditable again.
  **`AppointmentHistoryView` takes an `isAdmin` and passes it straight through
  as `showActions`** (restored 2026-08-08 after a revert dropped it). It used to
  hardcode `false` on the grounds that History is a read-only surface, but
  History is where `done` and `cancelled` jobs actually LIVE, so that made the
  completed-job edit button above unreachable from the one screen an admin would
  look for it on. It still DEFAULTS closed like every other appointment surface;
  `HistoryScreen` passes `widget.isAdmin`.
- **Personal jobs (`isPersonal`, added 2026-07-31) carry no client, and their
  address is OPTIONAL** (owner call, 2026-08-11, which reversed the original
  "no address"). The switch at the top of the form's WHO section is on BOTH the
  add and edit flows (unlike the template chips), because the flag is stored and
  has to be reversible. Turning it on hides the client picker, clears its
  controller and drops `clientRequired` from `AppointmentFormValidator` —
  **the assignees stay required**, they are who the block is for and who can
  see it. Both save paths write `clientId`/`clientName`/`clientPhone` as
  **empty strings**, including when an existing client visit is converted, so a
  hidden field can never keep a stale value the UI no longer shows.
  **`address` is deliberately NOT in that set**: a dentist appointment or a
  supply run still happens somewhere, and the crew wants directions to it. The
  field stays on screen for a personal job, marked "(Optional)"
  (`AppointmentAddressField.optional`, forwarded to `AddressAutocompleteField`),
  and both save paths write `address.trim()` unconditionally — so the
  "hidden field can't keep a stale value" reasoning doesn't apply to it: what
  saves is what the user can see and edit. The switch therefore must NOT clear
  `controllers.address`, which is the one clear that was removed here; the
  validator never required an address on any job, so nothing was relaxed there.
  Every read surface already gated on `address.isNotEmpty` (the detail row, the
  Directions quick action), so a personal job with one renders it and a
  personal job without one is unchanged — and a *timed* one with an address is
  now a genuinely routable travel candidate rather than one that always
  degraded to the fixed 30-minute reminder for want of a destination.
  Everything that speaks a client name falls back
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
  **Build that `ctx` with `liveActivityCtx(record, opts)`
  (`live_activity_utils.js`) — never a hand-written object literal.** There were
  four copies and they had already drifted again (two normalized `address`, two
  passed it raw), which is exactly the silent-failure shape above.
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
  **`setPersonal(value: false)` MUST NOT clear `isAllDay`** (2026-08-03).
  It used to — the switch was personal-only, so a surviving flag saved a
  midnight–23:59 *client* visit with neither the switch nor the time rows on
  screen to repair it. **All-day is now offered on EVERY job**, so that state is
  reachable, repairable and legitimate: a client visit can genuinely run whole
  days. Clearing the flag now discards a deliberate choice, and both controllers
  pin the new behaviour with a test. The asymmetry is deliberate and also
  pinned: turning Personal **on** still defaults an untimed block to all-day;
  only the **off** direction changed. The travel sweep still skips all-day
  records (no departure time to compute), and the overdue sweep still gates on
  `isPersonal`, so an all-day *client* job does go overdue after its 23:59 end —
  which is correct. **There is no longer an end-after-start check to gate**: an
  end time at or before the start time now means the window crosses midnight
  (see the multi-day bullet below). Now offered
  on every job, ON by default for a personal block when no time has been picked,
  and it hides the start/end rows. The switch is the schedule `SheetPanel`'s first
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
- **An appointment may span up to `maxAppointmentSpanDays` (14) days, and its
  two times are a DAILY WINDOW** (2026-08-03) — 9:00 AM–5:00 PM means 9–5 on
  *each* of those days, not one unbroken stretch through the nights. **No schema
  change**: `startTime`/`endTime` already carry the span, `isMultiDay` is
  derived and never stored (same discipline as display-only `overdue`).
  **`firestore.rules` bounds the span too, as of 2026-08-11** —
  `isValidAppointmentSpan`, on `allow create` and the admin `allow update` —
  but rules reach CLIENT writes only, so the app's clamp is still what contains
  a console or Admin-SDK write. The bound is **14 days inclusive PLUS a two-hour
  DST allowance**: a run booked at one clock time (09:00 → +14d 09:00) is a
  legitimate chain of 24-hour windows, so a `<` would reject the widest thing the
  form can save. The `+2h` is the unit mismatch, not slack — the app counts
  CALENDAR days and `combineDateAndTime` composes LOCAL wall-clock instants,
  while CEL's `duration.value` is absolute, so a window containing the autumn
  fall-back stores an hour MORE than its calendar length (that widest run
  becomes 14d 1h; a 14-day all-day block 14d 0h59m). A flat `duration.value(14,
  'd')` therefore refused, for about two weeks each autumn, a booking the form
  had already accepted — as an opaque `permission-denied`. Pinned by
  `appointment_span_rules_test.dart`; don't "simplify" the term away.
  **An UPDATE whose span is out of range but not WIDENED still passes**
  (`appointmentSpanNotWidened`) — the same asymmetry as `emergencyFieldNotSet`,
  and for the same reason: a doc that already exceeds the cap must stay
  updatable, or the admin trying to CANCEL it is refused too. Don't
  "simplify" that branch into a flat bound. An assignee's status flip never
  reaches either guard (that branch restricts the diff to `status`/`updatedAt`).
  Consequences that must stay in sync:
  **`AppointmentDaySlice` (`calendar/domain/appointment_day_slice.dart`) is the
  ONE owner of day-scoping** — `sliceFor` / `expandToDays` / `lastWorkDayOf`
  (plus `lastWorkDayOfWindow`, its raw start/end form, for the one caller that
  holds a resolved pair and no record yet: the booking-conflict dialog).
  Never re-derive a day index or a run length at a call site, the way the
  `displayStatusAt` ladder and `_who` were re-derived and drifted.
  **The end date names the last day the crew STARTS work**, never the morning an
  overnight run finishes, so the length is `end − start + 1` for day jobs and
  night shifts alike. A window whose end time is at or before its start time
  crosses midnight and counts **nights** — which is why **there is deliberately
  no end-time-after-start-time validation**: that ordering IS a night shift.
  (Consequence, accepted: picking 9:00–9:00 on a one-day job books 24 hours
  rather than erroring, because it is structurally identical to a legitimate
  one-night shift.)
  **Slices are generated per WORK day** — each day the window *begins* — not per
  calendar day the stored instant span touches; that is what keeps a night shift
  off the morning it ends.
  **`AppointmentDateRange.fetchStart` widens the query 14 days back and MUST
  stay a derived getter**, never a constructor field: `==` is keyed on
  `start`/`end`, so two surfaces asking for the same day still produce equal
  ranges and share one listener. Widening at a call site instead forks a second
  Firestore query for the same day.
  **"All day" is reserved for `isAllDay`** and is never borrowed to describe a
  timed job's middle day — the card reads `9:00 AM – 5:00 PM · Day 3 of 5`.
  A continuing *timed* job has a real start time that day and sorts in clock
  order; only all-day blocks pin above the day.
  **A RANGE STREAM IS A SUPERSET OF ITS RANGE — every consumer must re-scope**
  (2026-08-04 audit). Because the query starts at `fetchStart`, the emitted list
  holds every job that STARTED in the previous 14 days. Only the calendar
  clipped it; the day route, the roster's "jobs today", the employee detail's
  TODAY panel and the drawer's calendar badge all read it raw and silently
  reported a fortnight of past jobs as today's. Re-scope through
  **`runsOn(appointment, day)`** (beside `sliceFor` in the same owner file) —
  never by comparing `startTime` at the call site. A reducer over
  `appointmentsInRangeProvider` without a day predicate is a bug.
  **And a "today's window" test on a MULTI-DAY run must use the SLICE's
  window, not the record's `startTime`** (2026-08-11): the dashboard's
  "Upcoming today" re-scoped through `runsOn` and then asked
  `startTime.isAfter(now)`, i.e. the run's first morning — so on day 3 of a
  14:00 job the status counts included it while the section rendered "No visits
  today", and sorting on the stored instant floated it above jobs genuinely
  earlier that day. `computeTodayOps` now carries `AppointmentDaySlice`s.
  **`appointmentsInRangeProvider` is ADMIN-ONLY, and every non-admin consumer
  must role-branch to `myAppointmentsProvider`**: its query constrains
  `startTime` alone, and for a LIST query the rules are evaluated against the
  CONSTRAINTS, so `isAssignedEmployee` rejects a technician's whole query.
  `MyDetailsScreen`'s availability-conflict warning read it raw, and the
  rejection was swallowed by a `?? const []` — the warning silently never fired
  for the only role that screen exists to serve, while a permanently-failing
  listener stayed open. The Siri snapshot and the drawer badge already branch;
  copy them.
  **A conflict check is a DAILY-window overlap, not an instant overlap.**
  `findBusyEmployees`' Firestore query is only a coarse prefilter; its results
  are filtered through **`dailyWindowsOverlap`** (same owner file). Testing the
  raw instants reported a 9-5 run across a week as clashing with a 7 pm job
  inside it — a phantom clash the admin had to force through on every evening
  job. That helper compares ALL window pairs rather than matching day indices,
  because an overnight window runs into the following calendar day.
  **`MAX_APPOINTMENT_SPAN_DAYS`/`_MS` in `functions/time_utils.js` hand-mirrors
  `maxAppointmentSpanDays`** (each carries a pointer to the other). Every
  backend sweep that filters on `startTime` must reach at least that far back,
  or a job already under way is invisible to it — that single missing constant
  caused three separate bugs (no overdue prompt for multi-day runs, a digest
  that told an on-site crew "no jobs tomorrow", and a long job dropping out of
  its own travel context).
  **"Is this job still live?" gates on the run's END, not its start, and has
  ONE owner: `hasWorkLeft(record, nowMs)` in `functions/time_utils.js`.**
  Gating on `startTime` meant cancelling or deleting a job mid-run pushed
  NOTHING to the crew, who then turned up the next morning (the Live Activity
  card still ended, so the only signal was a card silently vanishing), and it
  meant `propagateClientEdits` never reached a crew already on site. It was a
  per-module closure in `notification_policy.js` and `client_propagation.js` —
  the same drift shape as `displayStatusAt` and `_who` — so route any new test
  through the shared helper rather than re-deriving `endTime ?? startTime`.
  **Admitting started jobs makes a status filter MANDATORY where it used to be
  free.** A `startTime >= now` query cannot match a job already marked done, so
  terminal jobs were excluded incidentally; any bound that reaches a run
  already under way admits them. `countFutureAssignments`
  (`firebase_appointments_repository.dart`) therefore tests
  `AppointmentStatus.fromRaw(status).isTerminal` explicitly, or a visit
  completed this morning still tells the admin to reassign it before disabling
  the person. Check every bound relaxed this way for the same gap.
  **That query asks `endTime >= now` and nothing else** (2026-08-13), on the
  existing `(employeeIds CONTAINS, endTime ASC)` index — "has work left" is a
  test on `endTime`, so the query states it rather than approximating it with
  `startTime >= now - maxAppointmentSpanDays` and re-testing in Dart. The old
  form had **no upper bound**: it read every job this person was assigned to
  from a fortnight ago to the end of time — and the repeat horizon pre-books
  five years out — to render one caption. Keep the status test in Dart: a
  `whereIn` over the open statuses would need a third index field and would
  silently drop any status the allowlist doesn't name, and this caption must
  err towards telling the admin to reassign.
  **It is also `.limit`ed** (`_futureAssignmentScanLimit`, 200, added
  2026-08-13) — `endTime >= now` still has no upper bound of its own, and a
  repeat series pre-books up to `RepeatInterval.maxOccurrences` (120)
  occurrences, so a tech on several series was several hundred documents read
  to render that caption. This was the LAST unbounded query in the repository;
  every other one names a ceiling. A `.limit` rather than a horizon bound
  deliberately: with `endTime` the only inequality, Firestore returns these
  `endTime` ASC, so the cap keeps the SOONEST-ending jobs — the ones actually
  needing reassignment — and the number stays EXACT below the cap, so
  `employees_disableReassignCaption` needs no rewording. Bounding the horizon
  instead ("12 jobs in the next 90 days") would read less again but changes
  what the sentence claims; that is a product call, not a performance one. It
  warns at the cap for the same reason the range streams do: understating this
  caption tells an admin they have less to reassign than they do.
  **The mirrors are day-scoped too** (Plan 2, 2026-08-10): the widget payload
  (Dart `widget_sync_service.dart` + `functions/widget_payload_utils.js`), the
  Siri snapshot (**schema v3**) and the push date line all fan a run across the
  days it works. Each carries THAT day's window, never the run's first morning,
  and a multi-day run gets a `dayIndex`/`dayCount` counter that is **omitted**
  for a single-day job so an older decoder still parses.
  **`functions/day_slice_utils.js` is a HAND-MIRROR of
  `appointment_day_slice.dart`** — its jest cases deliberately reuse the Dart
  tests' worked examples (Aug 1–5 day job; Aug 1 22:00 → Aug 4 06:00 = 3 nights
  ending Aug 3), so a divergence fails a test instead of shipping. Change both
  together. Two things it does NOT copy: it re-exports
  `MAX_APPOINTMENT_SPAN_DAYS` from `time_utils.js` rather than restating a
  third copy, and it rebuilds a window as a **wall-clock** time rather than
  midnight-plus-elapsed-minutes, since the latter lands a 9:00 window at 10:00
  on the two DST shift days. It also treats a record with **no `endTime`** as a
  single-day job (the `hasWorkLeft` fallback) — the Dart model never emits one,
  so only the server meets legacy and console-written docs, and reading the
  absent end as "equal times" would make it overnight, count the run backwards
  to zero days, and drop the job out of every mirror silently.
  **The travel sweep and the overdue sweep need NO day-scoping**: the first
  gates on `startTime > now`, so it already fires on day 1 only (days 2+ have
  no separate departure time and the crew is already on site), and the second
  gates on the run's real `endTime`. **Live Activities deliberately skip
  multi-day jobs** — a four-day Lock Screen countdown is worse than no card.
  That skip is `dayCountOf(c) > 1` in `resolveReminderForAssignee`
  (`functions/travel_utils.js`), and it was BUILT 2026-08-11: this bullet
  asserted it as fact from 2026-08-10 while no such gate existed anywhere, so
  the card really did carry the run's `endTime` into
  `Text(timerInterval:countsDown:)`. `docs/plans/2026-08-02-multi-day-appointments.md`
  §10 deferred it, and the doc was right. Only the CARD is withheld — the
  `leaveNow` push still goes out on day 1, which is the only day with a
  departure time.
  **The 14-day cap is applied by ONE clamp, `_clampedDayCount`, and every
  day-scoping answer routes through it** (2026-08-08): `sliceFor`/`runsOn`,
  `runsInRange`, `expandToDays` and `dailyWindowsOverlap`. The rules bound
  stops a CLIENT writing past the cap, but the console and the Admin SDK
  bypass rules entirely, so a doc CAN still exceed it, and
  when the owners disagreed the calendar rendered 14 slices while every
  `runsOn` consumer counted the full corrupt length: a drawer badge reading
  "1 job today" every day for a year, a card counter reading "Day 400 of 900".
  `AppointmentFormValidator` is the one deliberate exception — it reads the
  RAW count, because it is the caller that has to see an out-of-range value in
  order to refuse it.
  **A form's run length has one owner too, `runLengthDays`** (beside
  `appointmentSpan`): the `end − start + 1` rule was hand-copied into both form
  bodies, which even shared the same five-line comment.
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
- **The app-lock flag is TRI-STATE, and BOTH lifecycle gates must honour it.**
  `AppLockController` (`app_lock_provider.dart`) holds `false` until a read
  actually settles, so "off" and "we could not find out" are the same value —
  `isResolved` tells them apart and `retryIfUnresolved()` re-reads. That
  distinction is the whole point: reading the bare bool meant ONE transient
  keychain error (the pre-first-unlock -25308 window above) disabled biometrics
  for the entire session with no sign anything was wrong. `AppLock`
  (`core/security/app_lock.dart`) therefore **retries BEFORE deciding on
  resume**, and — the half that was missed first time — **locks on
  background/`inactive` while UNRESOLVED**, since that is the gate the OS grabs
  its app-switcher snapshot behind and "we don't know yet" must not read there
  as "no lock". A defensive lock is released by `_afterRetry` once the retry
  settles: **a persistent read failure still degrades to unlocked**, on purpose
  — someone who never enabled biometrics must never be trapped behind a prompt
  they cannot satisfy — so the win is the switcher window, not a hard
  guarantee. Don't write it up as one, and don't "simplify" either gate back to
  a plain `ref.read(appLockEnabledProvider)`. Pinned by
  `test/core/security/app_lock_test.dart`.
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
  they'll be rejected. **Three, not four** — a fourth
  `email_verified && status == 'invited' && email == token.email` clause existed
  only because the retired code flow left `uid` empty until redemption, and it
  was deleted 2026-08-08 with the rest of the `#compat-1.37.1` shim. P4c mints
  the Auth account up front, so an invited person reads their own doc through
  clause 3; don't re-add an email-matched clause. An ordinary
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
  server check.** `completeEmployeeSetup` verifies auth + `email_verified` + a
  matching doc + `status == 'invited'`; it does not verify that the password
  actually rotated, so anything reaching the callable directly activates an
  un-rotated account. `enforceAppCheck: true` plus that mailbox check are what
  stand in the way there, and App Check is attestation, not authorization.
  Don't build on the ordering as if the server enforced it.
  **The password itself is validated TRIMMED** — `completeAccountSetup` stores
  `newPassword.trim()`, so checking the raw text let `"Aa1!bcd "` pass the
  8-character rule and set a 7-character password. The strength meter and the
  requirements checklist read the same trimmed value.
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
  admin-editable, and the two stores can still disagree on any doc edited
  before `changeEmployeeEmail` existed (nothing back-fills those), so an
  email-only check can clear a doc that is NOT the account Auth hands back —
  which reset a live employee's password and minted a second `users` doc
  carrying their uid, and `syncUsersByUid` then DELETED their `usersByUid`
  bridge, locking them out of everything. The transaction therefore also
  refuses when the uid already belongs to another doc (the rules' `allow create`
  uid denylist restated for the one path that bypasses rules). And resetting
  before the claim meant a setup committing in that window left the person
  active on a password nobody told them had been reverted.
  **Be precise about what the deferral bought: the window is NARROWED, not
  closed.** Firestore serializes the two transactions, but the Auth call sits
  outside both — a `completeEmployeeSetup` that commits between
  `performCreateAccount` committing and `resetProvisionedPassword` returning
  still ends with an `active` employee on the shared default. That residue is
  milliseconds wide instead of a whole round trip, and it cannot be closed
  from here (Auth is not transactional); don't write it up as fixed.
  `deleteEmployeeAccount` likewise
  only works while `invited` (transactional, so a setup that commits first makes
  the delete refuse); after that the no-delete invariant applies and disable is
  the only removal. Provisioning **rolls back**: if the Firestore write fails
  after the Auth account is created, that Auth account is deleted — but only if
  *we* just minted it — since an Auth account with no `users` doc is a sign-in
  `SplashScreen` can't resolve and no admin surface can see.
  **The security posture is weaker than the codes it replaced, deliberately and
  with the owner's sign-off.** `Welcome123!` is known to everyone forever, so
  between creation and first sign-in anyone who knows an employee's email can
  sign in as them. **What stops them going further is
  `completeEmployeeSetup`'s `email_verified` guard (added 2026-08-08): setup
  requires control of the MAILBOX, not just knowledge of the address.**
  Before that guard the window was priced here as "can reach the setup screen
  as this person, not read the business", and that was wrong — the race winner
  called the callable, landed `active`, and (if the row was provisioned with
  `isAdmin: true`) landed *admin*, which reaches the whole `/clients` PII
  collection. Nothing about the code had drifted; the written risk assessment
  had. Reaching the setup screen is still all an unverified caller gets: an
  `invited` user is granted **nothing** by `firestore.rules` — no clients, no
  appointments, no peers. **The residual risk is now "whoever holds the mailbox
  AND the shared password can activate the account"**, and the window remains
  under the admin's control (create the account when you are handing the
  credentials over, not weeks ahead). That last mitigation is operational, not
  technical, and belongs in the onboarding instructions.
  Client side, `AccountSetupScreen` sends Firebase's own verification email and
  gates its CTA on `AuthService.refreshEmailVerified()`, which **forces an ID
  token refresh** — the callable reads `email_verified` off the token, minted at
  sign-in, so a bare `User.reload()` would leave the server refusing an address
  the person had already verified. `create_account_screen.dart`, both `accept_invite_*` screens,
  `CodeEntryBoxes`, `signup_code_dialog`, `InvitePreview` and the
  `revokeInvite`/`previewInvite` callables are all **deleted** — there is
  nothing left to "accept" in THIS build, which is why sign-in's bottom prompt
  went with them. **The backend half is gone too, as of 2026-08-08**: once every
  device was on 1.40+, the whole `#compat-1.37.1` shim was retired —
  `invites.js`, `signup_code_utils.js`, the `createEmployeeInvite`/
  `redeemSignupCode` callables, the `signupCodes` collection's rules block and
  TTL entry, and the two `allow delete` grants. There is no code-based invite
  anywhere in the stack and none should be reintroduced. Design:
  `docs/plans/redesign-subdocs/2026-08-02-p4c-HANDOFF.md`.
- **An employee's email is their SIGN-IN identity, so an edit to it moves BOTH
  stores or neither** (2026-08-04, which re-enabled a field that had been
  read-only since P4c). The joining callable is `changeEmployeeEmail`
  (`functions/employee_accounts.js`), and `FirebaseEmployeesRepository
  .updateEmployee` is its ONLY caller: it reads the stored doc first and, when
  the email actually changed **and** the doc carries a `uid`, runs the callable
  **before** its own Firestore write, which then merely re-states what the
  server committed. The order is the whole fix — a Firestore-only change left
  the person signing in at the old address while every admin surface showed the
  new one, and desynced the two stores `createEmployeeAccount` joins on (see the
  uid-not-email refusal above). Keep the call **inside** `updateEmployee` rather
  than exposing it on `EmployeesRepository`: "an email edit always moves Auth
  too" is then a property of the one save path, not a second method a call site
  can forget to pair with it.
  **Server-side the order is Auth FIRST, Firestore second, with a revert.**
  Auth is the store that owns sign-in and the only one that can genuinely refuse
  a duplicate, so it must never be the one left behind; if the doc write then
  fails, the Auth email is put back and a failed revert `logger.error`s the
  uid + docId (never the addresses — emails are PII). `performChangeEmail`'s
  transaction re-checks BOTH the previous email and the uniqueness the
  pre-flight checked, and raises `email-changed` on a concurrent edit, which the
  client surfaces as the same "try again" its own transaction guard does.
  A doc with **no** `uid` still takes the direct client write — there is no Auth
  account to join, and that is the one path allowed to write `email` alone.
  **The employee is pushed a `kind:"emailChanged"` notice naming the new
  address**, after the commit and best-effort (`notifyEmailChanged`, through the
  shared `sendToEmployee`). It is a courtesy, **not** a guarantee — no live FCM
  token, no notice — so the admin still has to tell them; don't write it up as
  if the person is reliably informed.
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
  `CredentialLine`, `CopyCredentialsButton` and `credentialPanelDecoration`
  beside it are shared for the same reason — the whole surface, not just the
  payload. They were separate copies and had already drifted twice: the two
  confirmed-state icons disagreed, and the dialog tinted its panel
  `surfaceContainerHighest`/`r8` against the roster row's `sheetRow`/`r12`, so
  the same credential pair rendered on two different fills in the two places an
  admin reads it. Add a new credential surface by calling these, never by
  re-deriving the control or the tint.
- **`EmployeeFormActivity` tracks busy state as SETS OF DOC IDS, not booleans**
  (`savingIds`, `deletingAccountIds`). The notifier is app-wide but its surfaces
  are not: the roster can show several expanded `PendingInviteTile`s at once,
  each with its own Reset and Remove. A single flag made every row claim to be
  busy when any one was, and — worse — made `_save`'s reentrancy guard refuse a
  *different* employee's action, which `EmployeeSaveBusy` then dropped with no
  spinner and no notice. **So `_save` takes a `docId` and guards per key:** the
  same person twice is a double-tap and must be refused; a different person is a
  real action and must proceed. `isSaving` survives as an `isNotEmpty` getter
  for the two person sheets (modal, one at a time). Its sibling
  `isDeletingAccount` has **no** in-app caller — the sheets have no
  delete-account affordance, only `PendingInviteTile` does, and it correctly
  asks the id-keyed form — so it is an aggregate read for tests alone; don't
  wire a surface to it without re-checking that the surface really is modal. A row
  asks `isSavingId(id)`/`isDeletingAccountId(id)` through a Riverpod `select`,
  so it rebuilds only when its OWN state flips. A brand-new person keys on `''`
  — correct, not a gap, since the invite sheet is modal. Never collapse this
  back to booleans, and never "fix" a busy-state bug by adding a flag at a call
  site instead.
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
- **The consent sentence LINKS to the terms, and the link is what makes the
  stamp mean anything** (2026-08-05, restored 2026-08-08 after a revert dropped
  it). Ticking the box stamps `termsAcceptedAt`, so the person must be able to
  read what they are accepting; the setup screen used to demand acceptance of
  terms that were published nowhere and tappable nowhere. `_ConsentRow`
  (`account_setup_screen.dart`) builds the sentence by locating
  `auth_termsOfServiceLink` **verbatim inside**
  `auth_termsAndLocationConsent` and turning that run into the link, so the two
  keys must stay consistent **in every locale** — a translation that rewords the
  phrase silently renders a plain sentence with no link (`indexOf < 0` falls
  back to one plain span on purpose: a missing link beats half a sentence or a
  `-1` substring crash). It is a `StatefulWidget` solely to own and dispose the
  `TapGestureRecognizer`; one built in `build` leaks on every rebuild. A tap on
  that run is claimed by the recognizer, so it opens the terms instead of
  toggling the checkbox; the rest of the tile still toggles.
  **The per-locale half is pinned by `test/l10n/new_success_strings_test.dart`**,
  which asserts the substring holds in every `supportedLocales` entry — the
  widget test in `account_setup_screen_test.dart` only ever exercises the
  default locale, so a French re-translation would otherwise drop the link with
  nothing failing.
  **Settings › Legal is the DURABLE route** — setup is shown once, only to a new
  employee, and never again, so `LegalSettingsCard` carries a Terms of Service
  row beside Privacy Policy. Both point at `AppUrls`
  (`privacyPolicy`, `termsOfService`); the sources are
  `docs/legal/privacy-policy.html` / `terms-of-service.html`, published to the
  `es-pro-legal` GitHub Pages repo, where **the privacy policy is the index** —
  which is why the terms page links to it by absolute URL rather than a relative
  `privacy-policy.html` that would 404. Neither page is bundled: if the Pages
  repo drifts from `docs/legal/`, the consent record points at the wrong text.
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
  it isn't derived from `allUsersStreamProvider`. **`employeesStreamProvider`
  is `autoDispose`** (2026-08-08): its consumers are the two transient
  appointment sheets plus the Dashboard, so without it opening the
  add-appointment sheet ONCE pinned a second live `users` listener for the rest
  of the session, alongside the always-on `watchAllUsers()`.
- **The dashboard's window is SPLIT: one live listener, one `.get()`.**
  `DashboardAggregator.liveRangeAround` (this ISO week through next Monday /
  the 3-day pending horizon) is watched; `historyRangeAround` (the seven
  settled weeks behind it) is read once through
  `AppointmentsRepository.fetchInRange`. Held as one range it was a **70-day**
  business-wide live listener capped at `_rangeStreamLimit`, so above ~14
  jobs/day the 8-week trends, busiest-weekday and Attention list were computed
  over a silent PREFIX. The two results **must be merged by doc id**
  (`DashboardAggregator.mergeById`, live wins) and never concatenated — each
  query reaches back to its own `fetchStart`, so they overlap by a fortnight.
  Adding a reducer that needs older data means widening the HISTORY half, not
  the live one.
- **ClientRecord legacy back-compat:** pre-Wave-reshape "business-only" client
  docs stored their name under `businessName` with an empty `name`.
  `ClientRecord.fromMap` handles it in **two** halves, and both are load-bearing:
  `name` falls back to `businessName` when blank (the documented legacy shape),
  AND the raw value is carried through onto `ClientRecord.businessName`, which
  `ClientSearchPolicy.index` indexes. The fallback alone is not enough — it only
  fires when `name` is empty, so a legacy doc holding a name AND a *different*
  business name was unfindable by the business. The one-time
  `backfillLegacyClientNames` function was removed, so these reads are the only
  thing keeping legacy business docs visible/searchable — keep them
  indefinitely; never strip either. **`businessName` is READ-ONLY**: no UI edits
  it and `toMap` must never emit it (pinned by a test), or every save would
  persist a field the app no longer owns. Don't instead add a second matcher
  over the raw map beside the policy — that is what had drifted before, matching
  in the instant local filter and then vanishing when the debounced read landed. (A doc missing
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
- **A client is ARCHIVED, not deleted** (owner decision 2026-08-03, which
  REVERSED the 2026-08-01 "never removed — no delete, no archive" rule and
  retired the `kShowTestingDeleteClient` `#pre-ship` hole with it —
  `lib/core/testing_flags.dart` is deleted).
  Archiving hides a client from the paginated list and the type filter but
  keeps it **searchable and bookable**: its `clientId` links on existing
  appointments are untouched, which is the whole point — deleting one orphaned
  its past visits, which keep the denormalized `clientName` but lose the link,
  so history silently detached.
  **`archived` must be on EVERY client doc, forever.** The list filters
  `where('archived', isEqualTo: false)` **server-side**, and Firestore excludes
  docs missing a filtered field — so a doc without it is invisible in the list
  while still turning up in search: a partial disappearance with no error
  anywhere. There are exactly two create paths and both stamp it: `_normalizedMap`
  (`firebase_clients_repository.dart`, via `ClientRecord.toMap`) and Wave
  `importCustomers` (`functions/wave/customers.js`). **The Wave UPDATE branch
  must never write it**, or every scheduled import un-archives everything; a
  test pins that half. Existing docs were backfilled by
  `functions/scripts/backfill-clients-archived.js` (idempotent, `--dry-run`),
  which must run against prod BEFORE the filtered query deploys.
  The filter is server-side **specifically so `fetchClientsPage` keeps returning
  a plain `List`**: the server still fills a whole page, so `items.last` stays
  the true cursor and the list's `pages.last.length < pageSize` end-of-list test
  stays valid. A Dart post-query filter would shorten a page the server actually
  filled and truncate the list permanently at the first archived client — never
  reintroduce one. Needs the `(archived, name, __name__)` composite index.
  **Delete survives only for junk data, and only through the `deleteClient`
  callable** (`functions/clients.js`), which refuses with
  `failed-precondition / client-has-history` when a **live `count()` aggregate**
  finds any appointment — deliberately NOT the denormalized `jobCount`, which is
  lazily backfilled and can be stale, missing or wrong. Rules cannot express
  "only when this client has no appointments" (no cheap foreign-collection
  count), so the callable is the only place that guarantee can live and
  **nothing deletes a client directly**.
  **`allow delete` on `/clients` is now WITHDRAWN** (2026-08-08). It had
  survived as a `#compat-1.37.1` shim entry for that build's ungated Delete
  button, and while it did the hole was real — an admin on the old build could
  orphan a client's job history, the very thing the callable's `count()` gate
  prevents. That is closed: the callable is the only delete path, in rules as
  well as in code. Never re-add the grant.
  `canDeleteClient`
  (`domain/policies/client_delete_policy.dart`) is **advisory UI only** — it
  keeps the swipe and the detail footer from offering what the server would
  refuse, and treats a null `jobCount` as unknown, which withholds. The Admin
  SDK bypasses rules, so console/support cleanup is unaffected.
  UI: `flutter_slidable` in `ClientsListView`'s item builder — **never inside
  `ClientTile`**, which the booking-flow client picker reuses and must not gain
  destructive actions. A full swipe commits **Archive only**; delete is never
  gesture-committed. Both surfaces route through the one `ClientActionsHost`
  mixin (`clients/widgets/views/client_actions_host.dart`) so the notices, the
  CLI-ARCH/CLI-DEL tags and the confirm copy can't drift; its two hooks are
  separate because the detail view must STAY OPEN after archiving (to offer
  Unarchive) and dismiss after deleting.
- **The clients type filter is a SEPARATE bounded read, never a filter over the
  paginated list.** `fetchClientsByType` scans the same cached 1000-doc window
  `searchClients` uses, so the chip row and its results cost no extra Firestore
  read inside the 2-minute TTL and need no composite index. `fetchArchivedClients`
  (the Archived chip) is the same shape over the same window, and the chips are
  ONE sealed `ClientsFilter` — "archived AND commercial" is unexpressible, not
  merely unhandled. The type filter **excludes archived clients** (the Archived
  chip is where they live); `searchClients` deliberately does **not** — archived
  clients stay findable and bookable, which is why the row badges them.
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
- **The Wave sync badge needs a LIVE doc read, and `ClientDetailView` is the one
  surface that has one** (2026-08-07). Every other client surface is a one-shot
  read — a paginated page, or the repository's cached scan window — and
  `wave.syncState` is function-owned: the `waveUpsertCustomer` trigger stamps
  `pending` *after* the save has already returned, and — as of 2026-08-13 —
  enqueues AND drains that job inline, in the same invocation, so it usually
  reaches Wave and flips to `synced` within seconds rather than on a poll (the
  `waveSyncWorker` scheduler that used to own this drain is deleted; see
  `functions/CLAUDE.md`). So the record a screen holds always
  predates the state the badge is trying to show, and the edit sheet pops back
  a `copyWith` of that same record, which carries the PRE-EDIT sync state
  through by design (it must — `waveSyncState` is not the form's to write).
  The badge therefore could never move in response to an edit: it sat on
  "Synced with Wave" while the push was still queued, and Settings ›
  "Sync with Wave" — correctly — reported nothing left to send, because the
  inline drain had already sent it within seconds of the save.
  `clientStreamProvider`
  (`clients_providers.dart`, an `autoDispose.family` over
  `ClientsRepository.watchClient`) is the fix; the view keeps the handed-in
  record as a **fallback**, so an offline or refused read leaves the detail on
  screen instead of blanking it. Don't "simplify" the badge back onto a
  passed-in record, and don't try to fix it by writing an optimistic `pending`
  client-side — that would fork `mappedFieldsHash`'s projection into Dart, and
  only the server knows whether an edit touched a Wave-mapped field.
  This listener deliberately does **not** patch the search/scan cache:
  `_patchWindow` merges `toMap()`, which omits `wave`, so the cached copy keeps
  a stale sync state on purpose.
- **A no-op push must HEAL the client's sync state, or the badge sticks
  forever.** `upsertCustomer`'s already-synced short-circuit
  (`functions/wave/customers.js`) returns `noop` without touching Wave — and it
  now clears a stale `pending`/`error` via `healSyncState` before it does. That
  state is reachable from an ordinary pair of edits: the first marks the doc
  `pending` and enqueues, the second puts the mapped fields BACK, and
  `shouldEnqueueClientWrite`'s rule 2 skips that write entirely — so the job the
  first edit left behind arrives with nothing to push, and nothing else ever
  clears the flag. `healSyncState` re-reads and re-hashes **inside the
  transaction** rather than trusting the caller's hash: an edit landing in that
  window must not be marked synced, or the badge claims Wave has data still
  sitting in the outbox — the exact lie it exists to remove. It writes
  `syncState`/`syncError` only, never `lastSyncedAt` (nothing reached Wave just
  now), and the write re-fires the trigger harmlessly — unchanged mapped fields
  return at rule 1. `tallyUpsert` still counts `noop` as nothing: no Wave
  mutation was made, and the admin must not be told a client was pushed.
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
- **`clients/{id}.name` IS WAVE'S FIELD, and it carries the client's phone
  number on the end** (owner call 2026-08-14): "Marc Tremblay (514) 555-1234".
  `toWaveCustomerInput` syncs it VERBATIM as the Wave customer name, and the
  invoicing workflow there identifies customers by number — Wave gets `phone`
  as its own field too, but the name is what shows on the customer list and on
  an invoice. **The app never renders it.** Every in-app surface reads
  `ClientRecord.displayName`, which strips the number off and then branches:
  **a BUSINESS shows its business name, a PERSON shows their `firstName` +
  `lastName`.** That branch is the whole point — those two halves mean
  different things on the two kinds of client (on a person they ARE the client,
  on a business they are only its contact person), so preferring them
  everywhere renders "Vogas Plumbing" as "Marc Tremblay" on the card for a
  commercial job. `ClientNamePolicy.isBusiness` owns the test: the
  `commercial`/`propertyManagement` types, **plus any doc carrying the legacy
  `businessName`** — those predate the `type` field, so they arrive `unset` and
  would otherwise be read as people. Every branch ends at the same three
  fallbacks in a different order, so a client missing the field its own branch
  prefers still renders something.
  This REVERSED `backfill-client-phone-from-name.js`, which ran against prod
  2026-08-08: it lifted the number out of `name` into `phone` and renamed
  `name` to "First Last" — correct for the app, but it renamed every one of
  those customers in Wave too. `backfill-client-name-with-phone.js` puts them
  back (idempotent, `--dry-run`, `--since` so it skips recently-added clients).
  The one owner is **`ClientNamePolicy`** (`clients/domain/policies/`),
  hand-mirrored as **`functions/client_name_utils.js`**; their tests share
  worked examples, so a divergence fails a test. Consequences that must stay in
  sync:
  **`composeStored` and `stripPhone` are inverses over the number and BOTH are
  idempotent** — that is what lets every ordinary save re-append without
  stacking a second copy, and what makes the backfill re-runnable. Both client
  sheets compose on save; the edit sheet seeds its name field from
  `displayName`, or the next save would hand a name-plus-number back to
  `composeStored` as if it were the base name.
  **`propagateClientEdits` must strip too** — it fans `clientName` onto future
  appointments, and the app writes the DISPLAY name at booking, so without
  `clientDisplayName` the two disagree and cards start showing the number.
  **The backfill's base name is the STORED `name`, never `displayName`** — a
  business carries the business in `name` and a CONTACT PERSON in first/last,
  and a doc whose `type` was never picked reads as a person, so writing the
  display name back would rename "Vogas Plumbing" to "Marc Tremblay" on real
  Wave invoices, unrecoverably from the doc. It reaches the first/last halves
  only when the stored name is empty once its own number is stripped — the junk
  case the 2026-08-08 rename was cleaning up.
  **The rules cap on `name` is 225, not 200** — the stored value is
  `TextLimits.personName` (200) + a space + `TextLimits.phone` (24), so a cap
  sized to the typed FIELD rejects every long client save with an opaque
  `permission-denied`. `text_limits_test.dart` pins the sum against the rules
  text; the two are exactly equal, so a bump on either side breaks it loudly.
  **A number typed or pasted into the NAME field is lifted into the phone
  field** (`liftPhoneFromNameField`, wired to both sheets' name `onChanged`) —
  the interactive form of the 2026-08-08 backfill, so the collection cannot
  drift back into holding undialable numbers. It is quiet unless the phone
  field is EMPTY and the name holds a clean 10-digit number, and a name that is
  nothing but the number keeps it (the field is required — emptying it reads as
  the paste having vanished).
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
  roster by a day. **That conversion therefore has ONE owner,
  `sundayIndexOf(day)` in `calendar/domain/month_grid.dart`** — it was private
  there and had grown three more hand-spellings (the dashboard's capacity
  reducer, `availabilityConflictPolicy`, the daily-load chart's bar labels),
  each with its own restatement of the "DateTime.sunday is 7" comment. Never
  write `day.weekday % 7` at a call site. Display order comes from
  `orderedWorkingDays`, whose cells carry their own `storedIndex` — a widget
  must write back through that, never through the visual position.
  `formatWorkingDays` (the detail page's DAYS row) takes its `labels`
  **Sunday-indexed and unrotated** (`weekdayAbbreviationsForLocale`), because it
  indexes them by `storedIndex`; passing a display-ordered list silently
  mislabels every day. **Naming a SET of stored day numbers as prose is
  `joinWeekdayNames(context, days)`** (beside `formatWorkingDays`), which
  resolves the labels itself precisely so that unrotated rule can't be got wrong
  at a call site — the dashboard's Attention list and My details both report
  availability conflicts and each carried an identical private copy.
  **The daily-cap picker is shared too: `showMaxJobsPicker` + `kMaxJobsOptions`**,
  same file. The admin Team sheet and My details offer the same
  `maxJobsPerDay` field, and a hand-mirrored option list plus `noCap` label rule
  is exactly the drift the `AvailabilityPanel` extraction had just ended one row
  over.
- **A user-doc rules cap must not be tighter than the widest value a shipped
  write path can produce.** `createEmployeeAccount` accepts `phone` up to 40
  chars while `TextLimits.phone` is 24, so `isValidUserData` caps phone at
  **40** — a tighter cap would make every server-created doc with a longer phone
  permanently un-updatable, including by `deactivateEmployee`. Rules caps mirror
  the *server* limit; the client caps with `TextLimits`. **Retiring a callable
  does NOT license tightening a cap it set**: the docs it created outlive it, so
  the 40 survives `createEmployeeInvite` (deleted 2026-08-08) on the strength of
  the rows still in the collection. Same reasoning for the
  P4b `emergencyPhone`: rules cap **40**, client caps `TextLimits.phone`.
  **The converse also holds: a client cap must not be LOOSER than the callable's,
  or the field silently accepts a value the callable rejects as
  `invalid-argument`** — which reaches the user as an unexplained "Something went
  wrong" they cannot fix by editing. That is why the `users` name halves use
  `TextLimits.employeeNameHalf` (**100**), matching `createEmployeeAccount` and
  `completeEmployeeSetup` exactly, rather than the 200-char `TextLimits.firstName`
  used for clients. `name` is the JOIN of those halves, so it legitimately
  reaches 201 — its server and rules caps are **250**, sized to the composed
  value and never to a half. Same reason for **`TextLimits.authEmail` (254)**:
  an employee's email is a sign-in identity and passes through
  `createEmployeeAccount`/`changeEmployeeEmail`, which both
  `requireString(..., 254)`, so the two employee sheets bind to it rather than
  to the 320-char `TextLimits.email` the client records use.
  **`test/core/validators/text_limits_test.dart` now reads `firestore.rules`
  (and `employee_accounts.js`) back and fails the build if a client cap ever
  exceeds its rules or callable cap.** Dart, CEL and JS cannot share a constant,
  so that test is the only mechanism turning this rule into something enforced
  rather than merely written down — four appointment pairs are currently
  EXACTLY equal, so a one-character bump on either side breaks every long save
  with an opaque `permission-denied`.
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
  `emergencyContactProvider`); `isAvailabilityOnlyChange()` no longer lists
  them, because P5's self-service clause governs the users doc and these are
  not on it; and a read
  failure on this path means "not entitled", so a surface must render it as
  *not shown*, never as *none on file*.
  **The rules now make a value on the parent doc unreachable, with NO migration
  (owner call 2026-08-04: nobody had entered one, so there was no data to move,
  and the feature is treated as clean-slate).** `allow create` bans both keys
  outright; `allow update` routes them through **`emergencyFieldNotSet(f)`**,
  which permits a write that leaves the field ABSENT and refuses one that
  leaves a value. That asymmetry is the whole design and must not be
  "simplified" into a plain denylist entry beside `uid`: the denylist form
  rejects any write that touches the key at all, which would reject the
  `FieldValue.delete()` scrub `updateEmployee` still sends on every save AND
  leave any doc that somehow carried the pair permanently un-updatable —
  including by `deactivateEmployee`, since a partial update presents every
  untouched field in `request.resource.data`. As written, an untouched legacy
  value simply passes through (so the doc stays updatable) and the client scrub
  heals it on the next save. The length caps in `isValidUserData` stay for that
  pass-through case — they are not dead. `functions/scripts/backfill-emergency.js`
  is **deleted**; it has nothing to do. Pinned by
  `test/core/security/emergency_contact_rules_test.dart`, which reads
  `firestore.rules` back (rules can't be unit-tested without the emulator).
- **`MyDetailsScreen` (Settings › My details) is the ONLY surface where a person
  edits their own record** — the employee detail and edit sheets are admin-only.
  It exists to exercise the two grants a person holds over their own data, and
  is scoped to **exactly** those: the `private/emergency` subcollection (admin
  OR owner) and P5's self-service clause. Everything else about a person is
  admin-owned, so a general profile editor here would fail with
  `permission-denied`. (It was emergency-contact-only until P5, 2026-08-10.)
  **It carries TWO save behaviours on purpose** (owner call, 2026-08-10), and
  they must not be unified in either direction. The **identity** fields (phone,
  emergency contact, emergency phone) sit behind a Save/Discard bar that appears
  only once the form is dirty — they are free-text, a half-typed phone number
  auto-committing is a bad write with no undo, and dirtiness is recomputed
  against the stored values rather than latched, so typing a change and typing
  it back reads as pristine again. **Availability** (days, hours, on-call)
  applies immediately, optimistically, rolling back and surfacing a notice on
  failure — a switch that needs confirming reads as broken. **The consequence to
  keep: an availability write must send the STORED phone, never the identity
  controller's text**, or toggling a day silently commits the half-typed number
  the bar exists to prevent. Pinned by a test.
  The admin-only SCHEDULING section is `maxJobsPerDay` and nothing else, written
  through the ordinary admin `updateEmployee` path because that field is not on
  the self allowlist — and it is **hidden** for a technician rather than
  disabled, since there is no path there that could ever succeed. Role, job
  title and crew colour deliberately stay on the Team sheet: an admin editing
  their own role from a self-service screen is a privilege-escalation shape with
  no product reason to exist.
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
- **Revoking a PERMISSION deletes nothing server-side, and the published privacy
  policy now says so** (2026-08-08 audit). `presence/location` is deleted only by
  `PresenceSyncController.unregister()` and `fcmTokens` only by
  `unregisterCurrentDevice()`, and both are reached from exactly three places:
  sign-out, self-service account deletion, and the server-side disable/delete
  bridge (`functions/bridge.js`). Losing the OS permission mid-stream only runs
  `_stop()`, which cancels the subscription and timers — no network call. That
  matters because **the stored fix keeps rendering on the admin live map**:
  `LiveMapAggregator.join` filters on missing/inactive user, never on freshness,
  and `staff_marker_icon.dart` has no staleness branch, so a months-old pin is
  visually identical to a live one (only the roster row and info card show the
  age). The policy used to promise deletion on revocation and promise the pin
  disappeared; owner call was to correct the TEXT rather than the code, so
  `docs/legal/privacy-policy.html` §6 and §8 now describe this behaviour
  exactly. **The two must stay in step**: if you ever wire permission-revocation
  into a delete, or add a freshness filter to the map, update those two sections
  in the same change — and republish (see below), or the site keeps describing
  the old behaviour.
- **`docs/legal/*.html` are SOURCES, not the published pages.** The live site is
  the separate `gvogas/es-pro-legal` GitHub Pages repo, where
  `privacy-policy.html` is published as **`index.html`** (which is why the other
  pages link to the privacy policy by absolute root URL — a relative
  `privacy-policy.html` 404s). The four files must stay **byte-identical** across
  the two repos; a 2026-08-08 audit found the support page still describing the
  signup-code flow deleted in P4c, months after the app stopped having it.
  Editing `docs/legal/` alone changes nothing a user can read.
- **A disabled or invited employee's colour is TAKEN.** `usedColors` reads
  `allUsersStreamProvider`, never `employeesStreamProvider` — the latter filters
  to `status == 'active'`, so a disabled employee's colour was offered again and
  two people ended up the same hue, which is what the appointment bar and the
  calendar dots key on.
- **`allow update` on `/users` has TWO branches as of P5 (2026-08-10), and the
  brackets around them are load-bearing.** It reads
  `(isAdmin() || (isSelf() && isAvailabilityOnlyChange())) && <denylist> &&
  <emergency guards> && isValidUserData(...)`. Without the outer parentheses the
  denylist and the validator bind to the self branch alone and an admin write
  skips both. `isSelf()` gates on `isActiveUser()` as well as
  `resource.data.uid == request.auth.uid`: a **disabled** account keeps its Auth
  credential until `syncUsersByUid` revokes it, and an **invited** one is
  mid-setup with `completeEmployeeSetup` owning its doc — neither may self-edit,
  and both must fall through to the admin branch.
  **`isAvailabilityOnlyChange()` uses `hasOnly`, so it is a whitelist of the
  ENTIRE diff, not a per-key permit**: one unnamed key rejects the whole write,
  which reaches the user as an opaque `permission-denied` on an ordinary save.
  `kSelfServiceUserFields`
  (`employees/domain/policies/self_service_fields.dart`) is its hand-mirror, and
  `test/features/employees/domain/self_service_fields_test.dart` reads the rules
  back and fails the build if the two drift — Dart and CEL cannot share a
  constant, so that test is the only thing enforcing it. Add a key to the RULES
  first, then to the Dart set; the reverse order ships a silent
  `permission-denied`. `travelAlertsEnabled` is on the list deliberately — a
  per-person notification preference is exactly the category it exists for.
  **`email` must never join it** — it is a sign-in
  identity, and Auth and Firestore move together through `changeEmployeeEmail`
  or not at all. Neither may `maxJobsPerDay`, `role`, `jobTitle`, `colorValue`
  or `status`: those stay admin-only on both branches.
  The client write path is `EmployeesRepository.updateSelfDetails`, deliberately
  **separate** from `updateEmployee` rather than a flag on it — that method's
  patch carries `role`, `email` and the emergency `FieldValue.delete()` scrub,
  every one of which the `hasOnly` would reject. It is a plain `update()`, not a
  transaction (one person, one device, no concurrent writer, and see the
  no-client-transactions rule). **Because the patch names every allowlisted key,
  each caller must pass through the values it isn't changing** — My details
  carries the stored `travelAlertsEnabled`, Settings carries the stored
  availability, and both carry the STORED phone rather than in-progress text.
  A guessed default there silently flips somebody's setting.
- **An employee's own sign-in email moves through `changeEmployeeEmail`'s SELF
  branch** (P5, 2026-08-10) — never a users-doc write, which is why `email` is
  off the self allowlist. `resolveEmailChangeCaller`
  (`functions/employee_accounts.js`, pure and jest-tested) is the one gate:
  an **active admin** may move any doc, an **active employee** may move their
  OWN, and nothing else gets through — disabled, invited, unknown role, missing
  bridge doc, or an employee naming somebody else's docId. Widening the callable
  past admins must never widen WHICH doc a caller can reach; that function
  exists to make the mistake hard to write. Guard order is auth → payload →
  identity → rate limit → work, and the per-caller budget stays: this rewrites a
  sign-in identity.
  **`isSelf` reports whether the caller IS the target, independent of role**,
  because it routes the notification: an admin edit tells the EMPLOYEE
  (`notifyEmailChanged`), a self edit tells the ACTIVE ADMINS
  (`notifyAdminsOfSelfEmailChange` → the shared `sendToActiveAdmins`, which P6's
  time-off requests will reuse — build new fan-outs on it rather than inlining
  the query). An admin editing their own row is a *self* change and must not be
  pushed a notice about what they just did. **The admin notice carries the NAME,
  never the address**: it lands on every admin's Lock Screen and an email is PII.
  Client side, `SelfEmailService` re-authenticates BEFORE calling — an
  unattended unlocked phone changing the sign-in address is the account-takeover
  primitive — and the sheet demands the address **twice**, because the Admin SDK
  sets it with no proof of control and a typo locks the person out until an
  admin undoes it. That ordering is pinned by
  `test/features/settings/services/self_email_service_test.dart` (`verifyInOrder`
  plus the half that matters: a thrown re-auth must `verifyNever` the callable),
  the same way `completeAccountSetup`'s password-then-activate order is.
  **The server restates it for a NON-ADMIN caller**: `assertFreshReauth`
  (`functions/security.js`, shared with `deleteAccount`) rejects a caller whose
  `auth_time` is over 5 minutes old, so a direct call cannot skip the client's
  ordering. **That gate keys on the caller's ROLE (`isAdmin`), never on
  `isSelf`** — the two are deliberately separate fields on
  `resolveEmailChangeCaller`'s result, because an admin editing their OWN
  roster row IS `isSelf` and yet arrives through `updateEmployee`, which has no
  re-auth step to satisfy. Keyed on `isSelf`, that save was rejected outright —
  and since `_changeAuthEmail` runs BEFORE the Firestore write, the whole edit
  (name, phone, colour, availability with it) died as an opaque `stale-auth`
  five minutes after sign-in. `isSelf` routes the NOTIFICATION and nothing
  else; don't collapse them. The durable budget is **5/hour per caller uid on
  BOTH branches**
  (down from the 20 it shared with account creation) — the freshness gate is
  what differs, not the budget: this rewrites a sign-in identity, so a
  compromised session of either role must not be able to walk the roster.
  **The ADMIN branch is deliberately NOT gated on freshness** — it is
  reached from `updateEmployee`, which has no re-auth step to satisfy, so the
  check would reject every admin email edit made minutes after sign-in. That
  residue is real and stated: an unattended *admin* session can still rewrite a
  colleague's address, bounded by `assertAdmin` and the budget. Closing it needs
  a re-auth prompt on the admin save path first. Firebase's `verifyBeforeUpdateEmail` is not the answer: it
  flips Auth OUTSIDE the callable and leaves `users.email` stale with no trigger
  to reconcile it — the exact desync the callable exists to end.
- **`travelAlertsEnabled` defaults to ON, and absent MUST read as ON.**
  `wantsTravelAlerts` (`functions/travel_utils.js`) and
  `EmployeeRecord.fromMap`'s `!= false` are the two halves; every users doc
  written before the field existed has no value, so an `undefined`-is-off
  reading would silence departure alerts fleet-wide — and the symptom is a push
  that never arrives, which nobody reports. Only an explicit `false` opts out.
  **It gates the ESCALATION to `leaveNow` only**: an opted-out assignee still
  gets the fixed 30-minute `reminder`, the same degradation a missing origin or
  a Routes failure already takes.
  **The flag must be read BEFORE the Routes call, not beside the `kind`
  choice** — `resolveReminderForAssignee` skips the whole
  `decideOrigin`/`computeTravelSeconds` block when it is off, so `travelSeconds`
  stays null and `computeLeadMinutes(null)` yields the fixed 30. Read only at
  `kind`, the escalation was suppressed but the LEAD TIME was still
  travel-derived, so an opted-out tech got the generic "Upcoming job" push up to
  `MAX_LEAD_MINUTES` (90) early on a long drive — and the business still paid
  Google Routes for an estimate that changed nothing. Pinned by
  `travel_utils.test.js` ("an opted-out assignee"), which asserts the sweep
  never calls `fetchImpl`. The toggle is in Settings › NOTIFICATIONS (a
  SERVER flag, unlike the device-local Live Activity switch beside it — the
  sweep picks the push kind, so a local preference could never reach it), and
  the row is hidden until the person's own record loads rather than rendered
  against a guessed default. `EmployeeRecord.toMap()` deliberately does NOT emit
  it: an admin save must leave it exactly as it was.

- **Calendar UI rendering rules live in `lib/features/calendar/CLAUDE.md`**
  (moved 2026-08-14) — the P2 month grid/pager/collapse rules, the
  `AppointmentCard` contract, and the agenda's closed-job sink. They are pure
  Flutter with no `functions/` twin, so they load only when working under that
  directory. Everything with a server-side mirror stayed here.
- **History carries its date on a LEFT RAIL, under a sticky month bar, and it
  builds its own slivers** (P7 Phase D, 2026-08-11 —
  `docs/plans/2026-08-11-history-restyle.md`). The rail is what leaves
  `AppointmentCard` untouched: the two rejected layouts both had to restyle the
  one shared card. Consequences, each of which was a real failure:
  **Each month is a `SliverMainAxisGroup`, not a bare
  `SliverPersistentHeader(pinned: true)` beside its list.** Repeated pinned
  headers **stack** — a year of history parks twelve bars across the top of the
  screen. A pinned header bounded by its own group scrolls away with its rows
  instead. Pinned by a test that reads the bars actually PAINTED in the
  viewport; a bar pushed out stays in the tree inside the cache extent, so
  presence alone proves nothing.
  **A sticky header cannot live inside `PagedListView`, so
  `AppointmentHistoryView` re-owns what ISP used to do** — the prefetch
  trigger, the new-page spinner/retry footer, and the one that is easy to miss:
  **`PagingController.refresh()` only RESETS the state, it does not fetch.**
  `_requestFirstPage` is what notices the reset and asks again; without it both
  pull-to-refresh and the first-page Retry leave the skeleton shimmering
  forever with no request in flight. Every `fetchNextPage()` from a builder
  goes post-frame — the controller assigns its own value synchronously, so
  calling it mid-build mutates a listenable during layout.
  **The first-page indicators must NOT gain a scroll wrapper.** `AppEmptyState`
  carries its own `SingleChildScrollView`, so wrapping it in a
  `RefreshIndicator`'s `CustomScrollView` leaves two controllerless primary
  scrollables under the screen's `PrimaryScrollScope` — the Scrollbar crash
  above. ISP did not scroll those states either; pull-to-refresh on an empty
  history is not a regression to "restore".
  **SEARCH renders FLAT and the rail changes shape there.** Search spans every
  appointment, so hits are not a contiguous run of days and month bars over
  them are noise — the rail therefore shows the **month** instead of the
  weekday, plus the **year** when the hit is not from the current one (read
  from `currentDayProvider`, never `DateTime.now()`). A chip filter alone keeps
  the month bars: only a text query goes flat.
  **There is ONE count, `18 JOBS · 2 CANCELLED`, and no per-month counts ever.**
  History is paginated, so a per-month figure could only report what had loaded
  and would climb while you read it. The cancelled clause is a SUBSET of the
  total, the same shape as the agenda's `4 JOBS · 1 DONE`, and search keeps the
  clause (`5 RESULTS · 1 CANCELLED`) — dropping it on one state reads as a
  different metric. The grouping, the tally and the two quick filters are the
  pure `clients/domain/history_grouping.dart`; the cancelled-vs-complete
  vocabulary lives with the rest of it in `appointment_status_values.dart`
  (`isCancelledStatusRaw` / `isCompletedStatusRaw`), never re-spelled as a
  `== 'cancelled'` at a call site. The quick-filter chips bind to the existing
  `statusLabel` ("Complete"/"Cancelled") — don't add history-specific status
  wording beside it. The **bold year separator is deleted**: the month bar
  already carries the year.
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

- **Feature-tour rules live in `lib/features/feature_tour/CLAUDE.md`**
  (moved 2026-08-14) — `TourScope`, the visibility gates, `isTargetRendered`,
  the `ready:` gate for data-dependent tabs, and the widget-test caveat.
  Remember here: an `AppDestination`/`TourForm` member name IS the tour's
  storage key, so renaming one replays or orphans that tour.

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
  **Both scan windows WARN at their cap** (2026-08-13), the same posture
  `_mapRangeSnapshot` already took for the range streams — they were the two
  bounded reads that truncated in silence. It matters most on clients: that
  window is `orderBy('name')`, so at the cap it is the alphabetically FIRST N
  clients, and everything past that point goes invisible to search, to the
  type-filter chips and to the Archived chip at once, with no error anywhere.
  It arrives gradually as the roster grows, which is the kind of failure
  nobody reports. Never add a bounded read here without the warn.
- **Client "Job history" section** (`ClientJobHistorySection`, admin-only client
  detail) reads via `fetchClientHistory` (`clientJobHistoryProvider`, an
  `autoDispose.family` that re-fetches on `onLocalWrite`). It orders
  `startTime` DESC on the **server** — `(clientId ASC, startTime DESC)`, added
  2026-08-13 — and the `orderBy` is what makes the `limit` mean anything. It
  filtered on `clientId` alone before that, on the reasoning that the automatic
  single-field index served it and Dart could sort the page: but with no
  `orderBy` Firestore falls back to `__name__` order, so a client with more
  visits than the cap got an **arbitrary** slice of its history, and sorting
  that slice newest-first afterwards made the wrong page look like the right
  one. (The composite index the old note said this would need already existed —
  `propagateClientEdits` added it.) Consequence to keep in mind: an
  `orderBy('startTime')` makes Firestore exclude a doc that has no `startTime`,
  so `getAppointmentById` is now the only read in that repository that can
  reach a legacy or console-written row missing one — which is what
  `_recordFrom`'s breadcrumb is left for.
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
  `isOfflineProvider`, pushes the standard offline notice and returns true so
  the caller returns. The block was copy-pasted at six sites. It takes no
  `tag`: notices carry no support code (2026-08-04), so a tag now lives only in
  the `logger.warn` label at the same site. `AccountSetupScreen` deliberately
  stays out — it surfaces offline through its own banner (`_bannerError`), not a
  notice. (This named "the two `accept_invite_*` screens" until 2026-08-11, both
  of which P4c deleted, so the rule pointed at nothing and the one live
  carve-out read as drift.) Controller-layer guards (`add_event`,
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
  isAdmin:)` per screen — don't re-inline it. **The app bar's `bottom:` slot
  uses `stepBarIf`**, the `PreferredSizeWidget` sibling of `stepIf`: without it
  that one slot escaped the class's ownership and Clients, History and Team each
  re-spelled the same six-line `has(id) ? TourShowcaseBar(...) : bar` block by
  hand.
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
- Cast callable responses loosely: `(value as Map?)?.cast<String, dynamic>()`,
  never `as Map<String, dynamic>?`. This started as an Android-only `TypeError`
  (that plugin returned nested objects as `Map<dynamic, dynamic>`), so it can no
  longer bite now that Android is gone — but it stays the convention: it is the
  same cost, and it doesn't depend on a plugin's choice of map type.
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

**A module that resolves a firebase-admin handle at load can't be tested, so
its decisions live in a pure `*_policy.js` sibling.** `maintenance.js` resolves
a Storage bucket at load and therefore throws on `require()` outside the
emulator — which is why the only unattended, irreversible deletion in the repo
(`purgeExpiredHistory`) had ZERO tests until 2026-08-04. Its orchestration now
lives in `maintenance_policy.js`, taking `db`/`deleteImages`/`now` injected,
the same split `notification_policy.js` ↔ `notification_utils.js` already uses.
Three rules there destroy data if they regress and are each pinned: the status
gate (only `done`/`cancelled` are ever purged — live work must survive at any
age), the ordering (images FIRST; a doc whose image cleanup failed is kept, or
the Storage bytes orphan with nothing pointing at them), and loop termination
(a full page that made no progress must end the loop, not respin it to the
1800 s timeout). Put a new unattended-deletion decision there, never in the
trigger module.

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

App Check simulator setup: debug builds use `AppleDebugProvider` (App Attest is
Release-only and fails on the Simulator), so run the app once → take the debug
token from the Xcode console, or read `GACAppCheckDebugToken` out of the
simulator app's preferences plist → register it in Firebase Console → App Check
→ the iOS app → Manage debug tokens. The token is per-install: re-register after
a full reinstall or a fresh simulator. An unregistered token causes all Firestore
writes and non-cached reads to fail with `permission-denied` while cached reads
still succeed, making the failure appear collection-specific. Full walkthrough:
`docs/IOS_MAC_BUILD.md` Phase E.

## Testing

- Catch overflow by pumping at a small-phone size with 2× text: set
  `tester.view.physicalSize` (260 logical px wide is the usual worst case) and
  wrap in a `MediaQuery` with `textScaler: TextScaler.linear(2)`. Each test file
  owns a local `_harness` helper for this — **there is no shared
  `_scaledHarness`**, despite what older plan docs call the pattern.
- Harness requirements, mocking rules and device-only caveats: the **Test
  Strategy** section of `docs/ARCHITECTURE.md`, mirrored by
  `.claude/rules/testing.md` — keep the two in step. **`.claude/` is COMMITTED
  as of 2026-08-14** (private repo, worked from both a Windows box and the Mac),
  so the rules, skills, agents, commands and hooks now reach every clone;
  before that date `.claude/` was gitignored and `docs/ARCHITECTURE.md` was the
  only copy anyone else could read. Only `.claude/settings.local.json` stays
  ignored, because it is machine-local. `testing.md` and `frontend.md` are
  `paths:`-scoped rather than `alwaysApply: true`, so they load only when
  working under `test/**` / `lib/**`.

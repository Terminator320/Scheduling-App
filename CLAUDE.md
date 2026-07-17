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
  open. Add the Crashlytics dSYM upload Run Script from the SPM checkout
  (`"${BUILD_DIR%/Build/*}/SourcePackages/checkouts/firebase-ios-sdk/Crashlytics/run"`),
  and set Build Settings → Debug Information Format to `DWARF with dSYM` for
  Release. `google_maps_flutter` uses the `google_maps_flutter_ios_sdk9`
  endorsed SPM override (Maps SDK 9.x, iOS 15+) — never fall back to the
  default CocoaPods-only `google_maps_flutter_ios`.
- Deployment target is **iOS 15.0** (set in the Xcode project, ≥ App Attest's
  14+ requirement). App Check uses **App Attest** (`AppleAppAttestProvider` in
  `main()`); don't lower the target below 14 or attestation silently fails on
  the runtime device. See `docs/plans/IOS_APP_STORE_HANDOFF.md` for the full
  Mac runbook.
- App Check via **App Attest** (not DeviceCheck) needs, on the Xcode side:
  the **App Attest** capability / entitlement
  (`com.apple.developer.devicecheck.appattest-environment`, set to `production`
  for Release), and App Attest **enabled in the Firebase Console** (Build →
  App Check → the iOS app — no `.p8` key required, unlike DeviceCheck). The
  console provider MUST match the code provider or attestation is rejected.
  App Attest fails on the iOS Simulator — verify on real hardware.
- `Info.plist` already declares `NSCameraUsageDescription`,
  `NSPhotoLibraryUsageDescription`, and `LSApplicationQueriesSchemes`.

## Commands

```bash
flutter pub get
flutter run
flutter analyze
flutter analyze 2>&1 | grep -E "error -|warning -"   # ~1000 info lints; filter for real issues
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
  see the visit). Resolve the active set the way `_seedSelectedEmployees` does
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
  queue — it's reentrancy-guarded (`_draining`), re-queues only the *unsent*
  paths on a transient failure (preserving `enqueuedAtMs` so a batch can't
  retry past the prune window), and `arrayUnion`-appends uploaded pictures so a
  concurrent edit or the batch's other half never clobbers them. `main.dart`
  drives the drain on the offline→online flip AND when the account doc first
  arrives (Storage rules need an authed user — a signed-out drain just
  re-queues). Method-channel plugin — device-only verification.
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
  through `AppointmentStatus.fromRaw(status).raw` before writing** — legacy
  `confirmed`/unknown docs exist, an unchanged status is re-written verbatim,
  and the rules reject anything off the allowlist (a raw write would fail the
  whole save/series-update with `permission-denied`). Done at the seed in
  `event_details_controller` and per-sibling in `appointment_series_editor`'s
  `propagate`. `UserStatus.fromRaw` is the matching mapper for account statuses
  (unknown/empty → `invited`).
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
  `docs/plans/INVITED_SIGNUP_REDESIGN.md`.
- **`watchEmployees()`** now filters `status == 'active'` — it no longer returns invited or
  disabled users. Use `watchAllUsers()` (admin-only) if all statuses are needed.
- **ClientRecord legacy back-compat:** pre-Wave-reshape "business-only" client
  docs stored their name under `businessName` with an empty `name`.
  `ClientRecord.fromMap` falls back `name ← businessName`, and the repository
  search index includes `businessName`, so those docs stay visible, searchable,
  and editable. The one-time `backfillLegacyClientNames` function was removed, so
  these two reads are now the *only* thing keeping legacy business-only docs
  visible/searchable — keep them indefinitely; never strip them. (A doc missing
  `name` entirely is excluded by the list/search `orderBy('name')`; the fallback
  only rescues docs whose `name` is present-but-empty.) `toMap` must NEVER emit
  `waveCustomerId`/`wave`; those are function-owned and `firestore.rules` rejects
  any client write that touches them.
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
`us-central1`). `index.js` is now a thin wiring surface that re-exports all 21
functions under their original names — the implementations are split into
domain modules: `security.js` (shared callable guards — `assertPayloadShape`,
`requireString`, `readSessionToken`, `enforceDurableRateLimit`, `assertAdmin`),
`bridge.js` (`syncUsersByUid`), `client_propagation.js`
(`propagateClientEdits`), `places.js`, `account.js`, `invites.js`
(invited-employee signup codes — `createEmployeeInvite` + `redeemSignupCode`,
backed by pure helpers in `signup_code_utils.js`), `maintenance.js`
(image validation + history purge; the pure JPEG/PNG magic-byte check lives in
`image_magic.js`), `notifications.js` (FCM push triggers, backed by
`notification_utils.js` and — for the travel-time reminder sweep —
`travel_utils.js`), and `wave/callables.js`. Shared `defineSecret` params live
in `params.js` (`GOOGLE_MAP_API_KEY`), imported by every consumer — a secret
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
directly.
- `syncUsersByUid` — Firestore trigger: mirrors `users/{id}` into `usersByUid/{uid}` bridge collection so security rules can resolve roles from auth UID alone.
- `placesAutocomplete` — proxies Google Places API (New) autocomplete. Requires App Check + auth + `assertAdmin` (address autocomplete is only surfaced on the admin-only appointment form, so gating on admin keeps a non-admin from scripting the billable API). Key in Secret Manager (`GOOGLE_MAP_API_KEY`).
- `placesGetDetails` — proxies Google Places API (New) place details. Same guards (App Check + auth + `assertAdmin`).
- `placesReverseGeocode` — proxies Google Geocoding API to convert a staff member's coordinates into a street address for the admin-only live staff map. Requires App Check + auth + `assertAdmin` + durable rate limit; returns only the top `formatted_address`; coordinates are never logged. Key in Secret Manager (`GOOGLE_MAP_API_KEY`).
- `validateUploadedImage` — Storage trigger: validates JPEG/PNG magic bytes for `appointments/*/images/*` uploads; deletes non-conforming files server-side.
- `propagateClientEdits` — Firestore `clients/{id}` update trigger: fans a client's name/phone/address edit onto that client's FUTURE appointments (the denormalized `clientName`/`clientPhone`/`address` copies). Per-appointment custom addresses (stored address ≠ client's previous address) and past/history visits are left untouched. Idempotent (absolute writes, `retry: true`); needs the `(clientId ASC, startTime ASC)` composite index. Pure helpers (`relevantClientChange`/`buildAppointmentPatch`) exported for unit tests.
- **Push notifications** (`notifications.js` + jest-testable `notification_utils.js`; functions + rules **deployed to prod 2026-07-11**; iOS-native APNs key + Push/App-Groups entitlements wired on the Mac 2026-07-11 — Firestore ledger TTL policy + on-device verify still pending, see the push-notifications plan): `notifyAppointmentChanges` (appointment write trigger → assignment/reschedule/cancel/unassign pushes; deliberately no `retry` — a duplicate push is worse than a missed one), `sendUpcomingJobReminders` (every 5 min, **travel-aware "time to leave" reminder** — `runTravelAwareReminderSweep` in `travel_utils.js`; per (job, assignee) it decides an origin [intervening job's address → fresh background-GPS presence ≤25 min → recently-ended job's address ≤4h → none], calls Google Routes API `computeRoutes` with `TRAFFIC_AWARE`, and fires at `startTime − driveTime − 10min`; **every failure path — no origin, empty address, any Routes error — degrades to the fixed 30-min `reminder` kind**, so it never regresses below the old behavior; `leaveNow` kind sets APNs `interruption-level: time-sensitive`. Reuses the existing `appointmentReminders/{id}_{startMs}_{employeeDocId}` ledger and key format, so claims from before the upgrade stay honored. Needs the Routes API enabled + added to the `GOOGLE_MAP_API_KEY` restriction), `sendDailyJobDigest` (18:00 Toronto), and `sendOverdueJobPrompts` (every 15 min, "job finished?" nudge for jobs past `endTime` but still open — server mirror of the display-only `overdue` state, keep in sync with `AppointmentRecord.displayStatus`). Recipients always filtered to active employees; tokens in `users/{docId}/fcmTokens/{token}` (per-device `locale` drives EN/FR text). Idempotency via Admin-SDK-only **per-recipient** ledgers `appointmentReminders/{id}_{startMs}_{employeeDocId}` and `appointmentOverduePrompts/{id}_{endMs}_{employeeDocId}` (create()-fails-if-exists; any claim — reminder OR overdue — with zero delivered pushes is released for retry, keyed per assignee so a late-registering token is retried without re-notifying an already-delivered assignee; both write `expiresAt` +7d for a console-enabled Firestore TTL). The overdue sweep queries `startTime` over 48h (24h eligibility + <24h max booking) — no new index; don't "simplify" it to an `endTime` query without adding one.
  - **Client side:** `PushRegistrationController` (`features/notifications`) registers this device's FCM token for active employees AND admins (`shouldRegisterPush` — admins register only for the timed nudges; the server withholds change-driven pushes from them), keyed by the users-doc id at `users/{docId}/fcmTokens/{token}`; `main.dart` drives `sync()` on every account-doc emission + on language change (re-upserts `locale`). A notification tap AND an iOS home-screen widget tap both deep-link to the appointment detail sheet.
  - **Live-location presence** (`features/presence`, `geolocator`, backs the travel-time reminders): `PresenceSyncController` mirrors `PushRegistrationController` (provider + `main.dart`-driven `sync()` on every account-doc emission, `_busy`/`_pendingResync` reentrancy) and owns a **background** `getPositionStream` for active employees AND admins (`shouldTrackPresence` — same audience as `shouldRegisterPush`; keep them in lockstep). It writes `users/{docId}/presence/location` (`{lat, lng, uid, updatedAt: serverTimestamp()}`, self-only rules, `updatedAt == request.time` so freshness can't be spoofed) throttled to 250 m of movement / ≥2 min per write, plus a 10-min heartbeat re-upsert so a *stationary* tracker stays fresh (server staleness window is `PRESENCE_STALE_MINUTES = 25` in `travel_utils.js` — a live heartbeat sits well inside it). OS location permission is the only switch: a `whileInUse`-only grant or a denial degrades silently (stream stops in background; server falls through its address→30-min chain). Torn down + presence doc deleted on sign-out/delete (beside `unregisterCurrentDevice`). Background stream is **device-only** verification (no geolocator channel tests). iOS needs `UIBackgroundModes: location` + both `NSLocation…UsageDescription` keys (already in `Info.plist`); the Time Sensitive Notifications entitlement (for `leaveNow`) is Mac-side. **Admin live staff map read path:** admins read ALL presence via a collection-group rule (`match /{path=**}/presence/{presenceId}` read if `isAdmin()`; the wildcard reserves the subcollection name `presence`); the client joins `collectionGroup('presence')` to `watchAllUsers()` on the admin-only Live map hub tab; `presenceStaleAfter` (Dart, `lib/features/presence/domain/live_map_aggregator.dart`, 25 min) must stay in sync with `PRESENCE_STALE_MINUTES` in `functions/travel_utils.js`; presence docs are server-purged by `syncUsersByUid` (`functions/bridge.js`) when a user doc is deleted or status leaves `'active'` (purge runs AFTER the auth-critical bridge write, isolated try/catch).
  - **iOS home-screen widget** (`features/home_widget` + `ios/ScheduleWidget`, `home_widget` package, iOS-only): `WidgetSyncService` writes a **two-day** payload into the App Group `group.net.vogas.scheduling` — `todayJobs` (remaining, non-terminal), `tomorrowJobs`, and a `rolloverAt` instant so WidgetKit flips today→tomorrow on-device with no app run (set only once today has no incomplete job left). The widget payload's `startTime` MUST be an absolute UTC instant (`toUtc().toIso8601String()`, …Z) — a bare local `toIso8601String()` has no zone designator and the Swift `ISO8601DateFormatter` can't parse it. The Dart builder (`buildWidgetPayload`, `widget_sync_service.dart`) and the server builder (`functions/widget_payload_utils.js`) are hand-mirrored — keep them and the Swift decoder in lockstep. **Known divergence:** the server resolves day boundaries in `America/Toronto`; the Dart mirror uses device-local midnight — harmless for this single-timezone (Quebec) business, but on an off-Toronto device the app-written and push-written payloads can disagree on which day a job is "today". Widget/notification taps use the `esproschedule://appointment?id=…` deep link.
  - **Widget refresh while the app is closed:** change-driven pushes carry a fresh `widgetPayload` + APNs `content-available`, so `firebaseMessagingBackgroundHandler` (`core/notifications/fcm_background_handler.dart`, registered via `FirebaseMessaging.onBackgroundMessage` in `main()`) rewrites the widget in a fresh OS-spawned isolate — without it the widget only updated while the app ran. It MUST stay a top-level `@pragma('vm:entry-point')` function, iOS-gated, and dependency-light (only the `home_widget` channel after `WidgetsFlutterBinding.ensureInitialized()`; NO `Firebase.initializeApp`/Firestore/Riverpod in the isolate).
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

Deploy: `firebase deploy --only functions,firestore:rules,storage`
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

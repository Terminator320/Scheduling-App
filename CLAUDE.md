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
  any client write that touches them. Every field `toMap` DOES emit is
  type/length-capped by `isValidClientData` in `firestore.rules` (name/business/
  first/last/phone/mobile/email plus the address family and a bounded `contacts`
  array) — add the matching rule cap when you add a new client field, or the
  write passes the app but a rules tightening later rejects it.
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
`us-central1`). `index.js` is now a thin wiring surface that re-exports all 21
functions under their original names — the implementations are split into
domain modules: `security.js` (shared callable guards — `assertPayloadShape`,
`requireString`, `requireNumberInRange` (finite number in `[min,max]`; rejects
`NaN`/`Infinity`), `readSessionToken`, `enforceDurableRateLimit`, `assertAdmin`),
`bridge.js` (`syncUsersByUid`), `client_propagation.js`
(`propagateClientEdits`), `places.js`, `account.js`, `invites.js`
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
- **Push notifications** (`notifications.js` + jest-testable `notification_utils.js`; functions + rules **deployed to prod 2026-07-11**; iOS-native APNs key + Push/App-Groups entitlements wired on the Mac 2026-07-11; the two ledger collections' Firestore **TTL policies were enabled 2026-07-11** — on-device verify is the only push item still pending; see the archived push-notifications plan): `notifyAppointmentChanges` (appointment write trigger → assignment/reschedule/cancel/unassign pushes; deliberately no `retry` — a duplicate push is worse than a missed one), `sendUpcomingJobReminders` (every 5 min, **travel-aware "time to leave" reminder** — `runTravelAwareReminderSweep` in `travel_utils.js`; per (job, assignee) it decides an origin [intervening job's address → fresh background-GPS presence ≤25 min → recently-ended job's address ≤4h → none], calls Google Routes API `computeRoutes` with `TRAFFIC_AWARE`, and fires at `startTime − driveTime − 10min`; **every failure path — no origin, empty address, any Routes error — degrades to the fixed 30-min `reminder` kind**, so it never regresses below the old behavior; `leaveNow` kind sets APNs `interruption-level: time-sensitive`. Reuses the existing `appointmentReminders/{id}_{startMs}_{employeeDocId}` ledger and key format, so claims from before the upgrade stay honored. The per-employee origin-context read is bounded by `CONTEXT_QUERY_MAX` (`travel_utils.js`), ordered `endTime` ASC so the cap keeps the just-ended/imminent jobs `decideOrigin` actually uses — don't remove the `.limit()` or the query re-reads every future appointment each sweep. Its `endTime` upper bound is `TRAVEL_WINDOW_MS + MAX_BOOKING_MS`, **not** the travel window: an intervening job can start inside the window and still run a full day longer, and narrowing the bound to the window silently drops it from `decideOrigin`'s first prong. The sweep also memoizes drive-time estimates per (job, assignee) for `ESTIMATE_TTL_MS` so a job sitting in the 90-min window isn't re-priced ~18 times to fire once — a cached estimate may only ever DEFER a Routes call (by `SKIP_MARGIN_MS`), never trigger a send; the fire decision is always made against a fresh response. Needs the Routes API enabled + added to the `GOOGLE_MAP_API_KEY` restriction), `sendDailyJobDigest` (18:00 Toronto), and `sendOverdueJobPrompts` (every 15 min, "job finished?" nudge for jobs past `endTime` but still open — server mirror of the display-only `overdue` state, keep in sync with `AppointmentRecord.displayStatus`). Recipients always filtered to active employees; tokens in `users/{docId}/fcmTokens/{token}` (per-device `locale` drives EN/FR text). Idempotency via Admin-SDK-only **per-recipient** ledgers `appointmentReminders/{id}_{startMs}_{employeeDocId}` and `appointmentOverduePrompts/{id}_{endMs}_{employeeDocId}` (create()-fails-if-exists; any claim — reminder OR overdue — with zero delivered pushes is released for retry, keyed per assignee so a late-registering token is retried without re-notifying an already-delivered assignee; both write `expiresAt` +7d for a console-enabled Firestore TTL — see the TTL-offset rule under Cloud Functions). The overdue sweep queries `startTime` over 48h (24h eligibility + <24h max booking) **ordered `startTime` DESC** (existing `(status, startTime DESC)` index) so the `OVERDUE_SWEEP_MAX` cap keeps the newest-overdue jobs, not the oldest — don't drop the `orderBy` or "simplify" it to an `endTime` query without adding an index. (Travel-aware sweep + audit hardening **deployed to prod 2026-07-18**.)
  - **Client side:** `PushRegistrationController` (`features/notifications`) registers this device's FCM token for active employees AND admins (`shouldRegisterPush` — admins register only for the timed nudges; the server withholds change-driven pushes from them), keyed by the users-doc id at `users/{docId}/fcmTokens/{token}`; `main.dart` drives `sync()` on every account-doc emission + on language change (re-upserts `locale`). A notification tap AND an iOS home-screen widget tap both deep-link to the appointment detail sheet.
  - **Live-location presence** (`features/presence`, `geolocator`, backs the travel-time reminders): `PresenceSyncController` mirrors `PushRegistrationController` (provider + `main.dart`-driven `sync()` on every account-doc emission, `_busy`/`_pendingResync` reentrancy) and owns a **background** `getPositionStream` for active employees AND admins (`shouldTrackPresence` **delegates to** `shouldRegisterPush`, so the presence audience can't drift from the push audience — never re-inline the predicate body). It writes `users/{docId}/presence/location` (`{lat, lng, uid, updatedAt: serverTimestamp()}`, self-only rules, `updatedAt == request.time` so freshness can't be spoofed) throttled to 250 m of movement / ≥2 min per write, plus a 10-min heartbeat re-upsert so a *stationary* tracker stays fresh (server staleness window is `PRESENCE_STALE_MINUTES = 25` in `travel_utils.js` — a live heartbeat sits well inside it). A *failed* write rolls the throttle clock back (`upsertLocation` returns `PresenceWriteResult.ok/failed/denied`) so a dropped write can't suppress the next fix and let the doc drift toward the staleness window; a **`denied`** result additionally calls `_stop()` — the rules gate presence on an active account, so a deactivated user's background stream would otherwise log a denied write every heartbeat until the app is killed (the 11-event Crashlytics spam of 1.32.0; next `sync()` on resume/account-emission re-runs the gate). Expected stream deaths (permission revoked / Location Services off, incl. the iOS `kCLErrorDomain error 1` surfaced as `PositionUpdateException`) are classified by `_isExpectedLocationLoss` and logged WITHOUT a Crashlytics error record. OS location permission is the only switch: a `whileInUse`-only grant or a denial degrades silently (stream stops in background; server falls through its address→30-min chain). Torn down + presence doc deleted on sign-out/delete (beside `unregisterCurrentDevice`). Background stream is **device-only** verification (no geolocator channel tests). iOS needs `UIBackgroundModes: location` + both `NSLocation…UsageDescription` keys (already in `Info.plist`); the Time Sensitive Notifications entitlement (for `leaveNow`) is Mac-side. **Admin live staff map read path:** admins read ALL presence via a collection-group rule (`match /{path=**}/presence/{presenceId}` read if `isAdmin()`; the wildcard reserves the subcollection name `presence`); the client joins `collectionGroup('presence')` to `watchAllUsers()` on the admin-only Live map hub tab; `presenceStaleAfter` (Dart, `lib/features/presence/domain/live_map_aggregator.dart`, 25 min) must stay in sync with `PRESENCE_STALE_MINUTES` in `functions/travel_utils.js`. **Staleness is surfaced as TEXT only** — the freshness labels in the info card + roster (`LiveMapAggregator.isStale`/`freshnessOf`); the **map marker itself is never dimmed/greyed** (the `staleDocIdsProvider` + marker-dimming path was removed 2026-07-19, and `StaffMarkerIconRenderer` has no `stale` param), so don't reintroduce pin greying. Presence docs are server-purged by `syncUsersByUid` (`functions/bridge.js`) when a user doc is deleted or status leaves `'active'` (purge runs AFTER the auth-critical bridge write, isolated try/catch) — see the deactivation invariant under Cloud Functions for the rest of that purge. The map's **staff roster sheet** (`staff_roster_sheet.dart`) lists everyone sharing location; ordering, haversine distance, and nearest-city parsing are pure functions on `LiveMapAggregator` (`sortedByProximity`/`distanceMeters`/`cityFromAddress` — self row leads, rest nearest-first) so they test without the geolocator/Maps plugins. Location permission is gated by `LocationPermissionService` (`core/permissions`, `geolocator`; `whileInUse`/`always` both count as granted).
  - **iOS home-screen widget** (`features/home_widget` + `ios/ScheduleWidget`, `home_widget` package, iOS-only): `WidgetSyncService` writes a **two-day** payload into the App Group `group.net.vogas.scheduling` — `todayJobs` (remaining, non-terminal), `tomorrowJobs`, and a `rolloverAt` instant so WidgetKit flips today→tomorrow on-device with no app run (set only once today has no incomplete job left). The widget payload's `startTime` MUST be an absolute UTC instant (`toUtc().toIso8601String()`, …Z) — a bare local `toIso8601String()` has no zone designator and the Swift `ISO8601DateFormatter` can't parse it. The Dart builder (`buildWidgetPayload`, `widget_sync_service.dart`) and the server builder (`functions/widget_payload_utils.js`) are hand-mirrored — keep them and the Swift decoder in lockstep. **Known divergence:** the server resolves day boundaries in `America/Toronto`; the Dart mirror uses device-local midnight — harmless for this single-timezone (Quebec) business, but on an off-Toronto device the app-written and push-written payloads can disagree on which day a job is "today". Widget/notification taps use the `esproschedule://appointment?id=…` deep link.
  - **Widget refresh while the app is closed:** change-driven pushes carry a fresh `widgetPayload` + APNs `content-available`, so `firebaseMessagingBackgroundHandler` (`core/notifications/fcm_background_handler.dart`, registered via `FirebaseMessaging.onBackgroundMessage` in `main()`) rewrites the widget in a fresh OS-spawned isolate — without it the widget only updated while the app ran. It MUST stay a top-level `@pragma('vm:entry-point')` function, iOS-gated, and dependency-light (only the `home_widget` channel after `WidgetsFlutterBinding.ensureInitialized()`; NO `Firebase.initializeApp`/Firestore/Riverpod in the isolate).
  - **iOS Live Activities — "time to leave" card** (`features/live_activity` + `ios/ScheduleWidget/JobLiveActivity.swift`, `live_activities` package, iOS 17.2+, **built 2026-07-19; DEPLOYED to prod + on-device card-start VERIFIED on real hardware 2026-07-20. The Lock Screen card renders and is started by the `leaveNow` sweep end-to-end; the Dynamic Island presentation is still unverified — the test device is a base iPhone 14, which has no Dynamic Island (Pro-only hardware)**): a Lock Screen / Dynamic Island card started by the travel-aware `leaveNow` sweep and ended when the job completes. **FCM cannot send Live Activity pushes** (they need `apns-push-type: liveactivity` on topic `net.vogas.scheduling.push-type.liveactivity`), so this is the one path with a **direct APNs HTTP/2 client** (`apns_client.js`, ES256 provider JWT cached and re-minted at 50 min; secrets `APNS_AUTH_KEY`/`APNS_KEY_ID`/`APNS_TEAM_ID`). **APNs environment: `sendLiveActivityPush` tries the PRODUCTION host, then retries the SANDBOX host on a `BadDeviceToken` response** (added 2026-07-20). This is load-bearing for *any* dev-signed build: a `flutter run` build ships an `aps-environment: development` provisioning profile, so its push-to-start token is a SANDBOX token that the production host rejects with `BadDeviceToken` → the card would never start (the plain `leaveNow` push still works because FCM auto-routes APNs environments; the direct client does not). The retry only fires when the production push did NOT deliver, so a production (TestFlight/App Store) token that succeeds on the first host is never re-sent — no duplicate-card risk. Don't remove the sandbox fallback thinking "prod only." **Every Live Activity path is additive and best-effort** — no token, no secrets, iOS < 17.2, Live Activities disabled, or any APNs failure all degrade to the existing `leaveNow` push, which fires independently and is unchanged; nothing in the reminder pipeline gains a new way to fail. Keep it that way. The start hangs off `deliverRecipientOnce`'s **return value** (`kind === 'leaveNow' && delivered > 0`) so it inherits that ledger's exactly-once claim — a start placed before the claim double-fires on a collision. **`liveActivityCards/{employeeDocId}` (Admin-SDK-only) is load-bearing, not a convenience:** a push-*started* activity's id is minted by ActivityKit and its attributes can't be read back, so the device physically cannot stamp `appointmentId` on its own token row — the server owns that association, and update/end resolve through the marker (resolving by employee alone would let a cancel on next week's job kill the card for the job the tech is driving to). The travel→on-site flip is **clock-derived on both sides** (mirrors `AppointmentRecord.displayStatus`); **no `markInProgress` write path exists or should be added**. Both the flip and the end are **server-owned**: `runOnSiteFlipPass` must run on every sweep — not only when there are travel candidates, since a tech whose job already started is by definition no longer a candidate — and completion ends the card via `endCardOnCompletion` in the appointment write trigger. The client must never end cards off its own status write (`endAllActivities()` is device-wide, so completing job B would kill the card for job A). "Complete" is a **deep link** into the appointment sheet, never a new authenticated write surface in the extension. Card text is built server-side in EN/FR from the `_MESSAGES`-shaped table in `live_activity_utils.js` — never `NSLocalizedString` in Swift, which would fork translations outside the ARBs. `buildContentState`/`buildAttributes` and `ios/ScheduleWidget/LiveActivitiesAppAttributes.swift` are hand-mirrored. **The ActivityAttributes type MUST be named exactly `LiveActivitiesAppAttributes`** (renamed from `JobActivityAttributes` 2026-07-19): the `live_activities` Flutter plugin registers the push-to-start AND per-activity update-token streams against `Activity<LiveActivitiesAppAttributes>` — a type of that exact name — so the device token the server pushes to only resolves when the name agrees in three places: the widget struct, the widget's `ActivityConfiguration(for:)`, and the server's `ATTRIBUTES_TYPE` (`live_activity_utils.js`). Rename any one and every push-to-start/update/end fails silently (degrades to the plain `leaveNow` push). Because the plugin (linked into Runner) owns token observation against its own copy of that type, the widget's `LiveActivitiesAppAttributes.swift` lives ONLY in the ScheduleWidget extension target — **do NOT add it to the Runner target** (the plugin, not app-native code, drives `pushToStartTokenUpdates`). **Xcode integration landed 2026-07-19** — the `WidgetBundle` `@main` hosts `JobLiveActivity` and the whole `ios/ScheduleWidget/` group builds clean at the new iOS 18.0 floor (the earlier "stay at 15.0, no bump" plan was superseded — the Directions button's returnable `OpenURLIntent` is iOS 18+, so the app moved to 18; every Live Activity path is still `@available(iOS 17.2, *)`-gated internally). `APNS_AUTH_KEY`/`APNS_KEY_ID`/`APNS_TEAM_ID` now exist in Secret Manager (created 2026-07-19), so a deploy no longer fails at secret binding. **Deployed to prod + card-start verified on device 2026-07-20** (via the sandbox fallback above; the missing `firestore:indexes` — see below — were the reason the first attempts produced only the push and no card, exactly as this file warned). **Only the two functions that bind `APNS_SECRETS` may read them** — `notifications.js` splits `liveDeps()` (no `apnsAuth`) from `liveActivityDeps()` (with it), because reading a secret param a function didn't bind logs a "No value found for secret parameter" warning on *every* invocation; the digest and overdue sweeps are Firestore-only and must keep using `liveDeps()`. Device-side capability (iOS 17.2+, ActivityKit available, Live Activities not switched off in iOS Settings) is probed in exactly one place — `LiveActivityRegistrationController.canHostCards()`, which never throws — and backs both `_ensurePlugin()` and the Settings row's `liveActivitySupportedProvider`; don't re-probe the plugin anywhere else. **The user's opt-out cannot be a local flag alone:** the card is *push-started* by the server, so `liveActivityEnabledProvider` (SharedPreferences, device-local, **default on**) only stops a later `sync()` from re-registering — the Settings toggle itself must call `unregister()` to end the live card and delete this device's token rows. `unregister()` deletes the push-to-start row **by kind, via query** (`deleteTokensOfKind`) and re-resolves the users-doc id when `_docId` is unset — the row's doc id IS a token this session may never have seen, and a cold start with the preference already off returns from `_syncGuarded` before `_docId` is set. A cold-start `sync()` MUST `await` the preference's `ready` future before acting on it, or the optimistic `true` default silently re-registers an opted-out device. Two **composite indexes are what make the feature work at all** — `liveActivityTokens` `(kind, employeeDocId)` at COLLECTION_GROUP scope and `liveActivityCards` `(phase, startTime)`; without them every registry query fails `FAILED_PRECONDITION`, the best-effort catch swallows it, and the card silently never appears. Deploy `firestore:indexes` with the functions. Mac runbook + device checklist: `ios/ScheduleWidget/LIVE_ACTIVITY_README.md`.
  - **Siri App Intents snapshot** (`features/siri` + `ios/SiriIntents`, iOS-only, **Phases 1–3: Dart + Swift landed 2026-07-19; the `SiriIntents` App Intents extension target was created + embedded in Runner 2026-07-19 and builds clean (bundle id `net.vogas.scheduling.SiriIntents`, entitlements `SiriIntentsExtension.entitlements` sharing the App Group, iOS 18.0). Phase-1 read intents (count / today / next), Phase-2 date intents (`TomorrowScheduleIntent` deterministic, `DayScheduleIntent` for any in-window day), and the Phase-3 `NthAppointmentIntent` ("read a specific appointment" → Siri prompts for a position) are all code-complete and pass the App Intents metadata compiler; on-device Siri phrase verification still pending — see `ios/SiriIntents/README.md`. Phases 2–3 added NO Dart/schema change (the snapshot already carries all 8 buckets). Note: a `Date` OR `Int` parameter cannot be interpolated into a spoken App Shortcut phrase (Siri only allows AppEnum/AppEntity there), so `DayScheduleIntent` and `NthAppointmentIntent` carry no such value in their phrases and Siri resolves it via its own locale-aware follow-up prompt ("For what day?" / "Which appointment?") — this prompt→answer is the only in-session multi-turn App Intents supports (there is no free-form "and tomorrow?" session), so don't "fix" it into a phrase parameter. A new `.swift` in `ios/SiriIntents/` must be hand-added to the target in `project.pbxproj` (all four sections)**): `ScheduleSnapshotService` writes a **today + 7 days** payload into the *same* App Group `group.net.vogas.scheduling` under a **separate key `schedule_snapshot`** (the widget's `schedulePayload` is untouched; the snapshot deliberately does NOT call `HomeWidget.updateWidget` — nothing renders it). Role-aware: employees get `myAppointmentsProvider`, admins the business-wide `appointmentsInRangeProvider`. Both off-screen schedule mirrors (this and the home-screen widget) resolve *who* they're for through the single `activeUserIdentityProvider` (`features/auth/application/active_user_identity_provider.dart` — active-status gate, employee-or-admin, `retryAsync(findUserByUid)` for the post-sign-in token lag); it returns `(role, docId)` and returning null is what wipes both mirrors on sign-out. Route any new mirror through it rather than re-deriving the identity. Both must also `ref.watch(currentDayProvider)` (`core/utils/`) for their day bucketing instead of a bare `DateTime.now()` — their appointment streams only re-emit on a write, so an app resident across midnight otherwise keeps publishing yesterday's buckets and Siri answers "no appointments today" while jobs exist. `buildScheduleSnapshot` (`siri/domain/schedule_snapshot.dart`) and the Swift `ScheduleSnapshot.swift` decoder are hand-mirrored — change one, change both, and bump `version` on both sides of a schema change. Cancelled visits and **records with a null/empty `id` are dropped at build** (Phase-4 write actions resolve their target by that id). **Sign-out wipes the snapshot implicitly** — `scheduleSnapshotProvider` emits `data(null)` and `main.dart`'s `_listenForSnapshotSync` calls `clearSnapshot()`; don't add an explicit sign-out clear (same contract as the widget). The App Group stays readable while the device is locked, so the payload carries **only the fields the intents speak** (client name, times, address, status) — never notes, phone, or pictures. **Phases 1–3 keep the extension Firebase-free and network-free**; Phase 4 breaks that deliberately as its own reviewed increment (it's also blocked on App Attest's bundle-ID binding — see the implementation plan).
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

**Firestore TTL policies must use expiration offset `0`.** Every collection that
writes an `expiresAt` (`appointmentReminders`, `appointmentOverduePrompts`,
`liveActivityTokens`, `liveActivityCards`, `rateLimits`, `signupCodes`) stores
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

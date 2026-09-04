# Mobile App Audit - 2026-09-03

Scope reviewed: Flutter app code, Firebase Auth, Firestore and Storage rules,
Cloud Functions, routing and navigation, state sync, image uploads,
notifications, location and presence, iOS platform code, dependency status, and
UX/accessibility patterns.

No code changes were made as part of the original audit. Follow-up remediation
changes were applied on 2026-09-03; see the implementation update below.

Verification:

- `flutter analyze`: clean, no issues found.
- Cloud Functions dependency check: only major-version updates available.

Implementation update - 2026-09-03:

- Fixed pending photo upload ownership and cleanup: queued uploads now carry the
  Firebase `uid` and employee document id, drain only for the matching signed-in
  user, and are cleared with staged files during device deregistration.
- Added explicit staff-map location sharing: `locationSharingEnabled` is a
  self-service user field, Settings exposes a separate switch, Firestore rules
  validate the field, and presence tracking is gated by the setting.
- Stopped background notification permission prompts: push sync now reads the
  current authorization status and only the explicit Settings action requests
  permission.
- Moved Places autocomplete to the durable Firestore-backed rate limiter and
  added coverage proving the limiter runs before upstream fetches.
- Replaced route argument force-casts with typed validation and a recoverable
  invalid-link screen.
- Added phone/mobile validation and a visible 50-contact UI cap for additional
  client contacts.
- Removed the audited compact tap-target settings from calendar filters and
  notification switches.
- Gated client archive/delete slide actions at the action builder for non-admin
  route states.
- Reduced raw UID logging in Functions by logging short hashes in the touched
  security/client paths.

Post-remediation verification:

- `flutter analyze`: clean.
- Targeted Flutter tests covering the changed app paths: passing.
- Focused Cloud Functions tests: 5 suites passed, 94 tests passed.
- `git diff --check`: clean apart from local CRLF warnings.

## Overall Assessment

The app has a strong foundation. Firestore and Storage rules are disciplined,
App Check is enabled, Crashlytics is wired, offline Firestore persistence is on,
auth flows are careful, and the UI already includes many good mobile patterns:
adaptive layouts, loading states, empty states, offline feedback, text scaling,
high contrast themes, and reduced-motion transitions.

The main production-readiness risks are not broad cleanup issues. They are
specific lifecycle, privacy, and scale concerns:

- Pending photo uploads can survive account exit.
- Location presence tracking starts automatically and is not clearly gated by a
  user-facing location-sharing setting.
- Several repository searches rely on capped client-side scans that can become
  incomplete as the business grows.

## 1. Critical Issues

No confirmed Critical issues were found.

The audit did not identify open Firestore rules, unauthenticated privileged
Cloud Functions, plaintext password storage, or a credential exposure that
directly grants backend access.

## 2. High-Priority Improvements

### High - Pending Photo Uploads Can Survive Sign-Out or Account Switch

Status: Fixed in the 2026-09-03 remediation pass.

Relevant code:

- `lib/features/calendar/data/appointment_image_upload_service.dart:61`
- `lib/features/calendar/data/appointment_image_upload_service.dart:247`
- `lib/features/calendar/data/pending_upload_store.dart:65`
- `lib/features/calendar/data/pending_upload_store.dart:68`
- `lib/core/app/app_sync_listeners.dart:152`
- `lib/core/app/app_sync_listeners.dart:169`
- `lib/core/app/device_deregistration.dart:50`
- `lib/core/app/device_deregistration.dart:66`

Finding:

Appointment photos are queued for background upload and persisted under
`pending_photo_uploads`. The queue is drained when app sync listeners observe an
active account, but device deregistration clears image/client/appointment caches
without clearing the pending upload queue or staged files.

Why it matters:

If a user signs out while photos are still queued, those local files and queue
entries can remain on the device. A later signed-in account could trigger queue
draining. This is a privacy and data integrity risk, especially on shared
devices or admin devices.

Recommendation:

- Store queue ownership with the Firebase `uid` and employee document id.
- Drain queued uploads only when ownership matches the current signed-in user.
- Clear pending upload metadata and staged files on sign-out, account deletion,
  and device deregistration.
- Consider encrypting queue metadata or storing it in a protected local store.
- Exclude staged upload files from device backup if possible.

Remediation notes:

- `PendingUpload` now stores `ownerUid` and `ownerEmployeeId`.
- `AppointmentImageUploadService` resolves the current owner before staging,
  skips mismatched queue entries, and reports pending counts only for the
  current owner.
- `DeviceDeregistrationDeps` now includes the upload service, and
  `deregisterThisDevice` calls `clearPending()` to remove queued metadata,
  staged files, and related failure notices.
- Legacy ownerless queue entries are dropped on load.
- Encryption/protected-store and backup-exclusion follow-ups remain optional
  hardening work.

### High - Location Presence Tracking Is Automatic and Not Gated by Travel Alerts

Status: Fixed in the 2026-09-03 remediation pass.

Relevant code:

- `lib/features/presence/application/presence_sync_controller.dart:45`
- `lib/features/presence/application/presence_sync_controller.dart:111`
- `lib/features/presence/application/presence_sync_controller.dart:130`
- `lib/features/presence/application/presence_sync_controller.dart:166`
- `lib/features/settings/screens/settings_screen.dart:244`
- `lib/features/settings/screens/settings_screen.dart:262`

Finding:

Presence tracking is based on active signed-in user role/status. It does not
check `travelAlertsEnabled`. Sync can call `ensureLocation()` automatically,
which can lead to location permission being requested and location uploads
beginning without a clear, separate location-sharing action.

Why it matters:

Location is sensitive data. If users believe disabling travel alerts disables
location behavior, but presence still uploads for the staff map, the app risks
privacy confusion, lower trust, and App Store review friction.

Recommendation:

- Add a separate "Location sharing" or "Staff map location" setting.
- Gate presence uploads on that explicit setting.
- Request location permission only after an explanatory in-app action.
- Show last uploaded time and provide a "clear my location" action.
- Keep `travelAlertsEnabled` separate from broader live-location sharing.

Remediation notes:

- `EmployeeRecord` now includes `locationSharingEnabled`, defaulting to `false`.
- The field is self-service editable and validated by Firestore rules.
- Settings now shows a separate "Staff map location" switch.
- Presence tracking requires `locationSharingEnabled == true` in addition to the
  existing signed-in active admin/employee gate.
- Turning location sharing off calls presence unregister to clear the current
  location document.
- Last-uploaded-time UI and a dedicated clear-location action remain future
  product polish.

## 3. Medium-Priority Improvements

### Medium - Notification Permission Can Be Requested on Startup or Sign-In

Status: Fixed in the 2026-09-03 remediation pass.

Relevant code:

- `lib/main.dart:263`
- `lib/main.dart:293`
- `lib/main.dart:296`
- `lib/core/app/app_sync_listeners.dart:55`
- `lib/features/notifications/application/push_registration_controller.dart:74`
- `lib/features/notifications/application/push_registration_controller.dart:116`
- `lib/features/settings/screens/settings_screen.dart:279`

Finding:

Push registration sync runs during startup/account sync and calls
`requestPermission()`. Settings also has an explicit notification action, but the
background sync path can still trigger the OS permission prompt out of context.

Why it matters:

Mobile users are less likely to accept notification permissions when prompted
without explanation. It also makes onboarding feel less intentional.

Recommendation:

- Change background push sync to check existing authorization status only.
- Register/upsert FCM tokens only when already authorized.
- Request permission only from an explicit user action, such as the Settings
  notification row.

Remediation notes:

- `PushRegistrationController.sync()` now calls `authorizationStatus()` instead
  of `requestPermission()`.
- FCM registration proceeds only when the current status is already granted.
- The Settings notification row remains the explicit permission-request entry
  point.

### Medium - Client, History, and Conflict Search Use Capped Client-Side Scans

Status: Fixed in the 2026-09-03 follow-up pass.

Relevant code:

- `lib/features/clients/data/firebase_clients_repository.dart:50`
- `lib/features/clients/data/firebase_clients_repository.dart:147`
- `lib/features/clients/data/firebase_clients_repository.dart:291`
- `lib/features/calendar/data/firebase_appointments_repository.dart:53`
- `lib/features/calendar/data/firebase_appointments_repository.dart:56`
- `lib/features/calendar/data/firebase_appointments_repository.dart:568`
- `lib/features/calendar/data/firebase_appointments_repository.dart:570`
- `lib/features/calendar/data/firebase_appointments_repository.dart:610`
- `lib/features/calendar/data/firebase_appointments_repository.dart:722`
- `lib/features/calendar/data/firebase_appointments_repository.dart:728`

Finding:

Several high-value queries are implemented by scanning a capped number of
Firestore documents and filtering locally. Client searches cap at 5,000 clients,
history search caps at 5,000 terminal appointments, and appointment conflict
queries cap at 1,000 per chunk.

Why it matters:

At scale, users can receive incomplete search results. More importantly, capped
conflict checks can miss scheduling conflicts and allow double booking.

Recommendation:

- Move search and conflict detection to indexed server-side queries.
- Consider denormalized search fields, prefix indexes, or a dedicated search
  service.
- Add server-side conflict validation for appointment create/update.
- Surface cap-hit warnings to admins instead of only logging them.

Remediation notes:

- Client and history documents now carry bounded search-token arrays populated
  on app writes and by `functions/scripts/backfill-search-tokens.js`.
- `searchClients` and `searchHistory` are Cloud Functions callables backed by
  `array-contains-any` indexes, with role-scoped history access.
- Appointment conflict reads now route through `findAppointmentConflicts`, a
  server-side callable that authorizes the caller and checks overlap centrally.
- Remaining hardening option: make appointment create/update themselves
  callable-owned so direct Firestore writes cannot bypass conflict validation.

### Medium - Google Places Autocomplete Rate Limit Is Per Instance

Status: Fixed in the 2026-09-03 remediation pass.

Relevant code:

- `functions/index.js:4`
- `functions/places.js:23`
- `functions/places.js:136`
- `functions/places.js:160`
- `functions/security.js:159`

Finding:

Cloud Functions `maxInstances` is set to 10, while Places autocomplete uses an
in-memory rate bucket. Each function instance has its own bucket, so effective
request capacity can multiply across instances.

Why it matters:

Autocomplete calls are billable. A compromised admin session or runaway client
could make more requests than intended.

Recommendation:

- Use the durable Firestore-backed limiter already implemented in
  `functions/security.js`.
- Optionally keep an in-memory fast path, but enforce a durable ceiling.

Remediation notes:

- `placesAutocomplete` now uses `enforceDurableRateLimit()` with the caller uid
  before calling Google Places.
- The old per-instance in-memory autocomplete bucket was removed.
- Tests cover limiter enforcement before fetch and non-admin requests not
  burning billable or limiter work.

### Medium - iOS Deployment Target Is Very High

Status: Accepted. Owner decision: keep iOS 18.

Relevant code:

- `ios/Runner.xcodeproj/project.pbxproj:676`
- `ios/Runner.xcodeproj/project.pbxproj:740`
- `ios/Runner.xcodeproj/project.pbxproj:762`
- `ios/Runner.xcodeproj/project.pbxproj:800`
- `ios/Runner.xcodeproj/project.pbxproj:845`
- `ios/Runner.xcodeproj/project.pbxproj:887`

Finding:

The iOS deployment target is set to `18.0` across build targets.

Why it matters:

This excludes users on older but still common iOS versions. If the target is
intentional, this is fine; if not, it unnecessarily reduces device
compatibility.

Recommendation:

- Confirm the product requirement for iOS 18.
- If possible, lower to the oldest iOS version compatible with the app's Live
  Activities, App Intents, Firebase, and Maps requirements.

Remediation notes:

- The iOS 18.0 floor is intentional because the project relies on the current
  Live Activity/App Intents behavior documented in `ios/CLAUDE.md` and
  `docs/IOS_MAC_BUILD.md`.

### Medium - Route Argument Force-Casts Can Red-Screen

Status: Fixed in the 2026-09-03 remediation pass.

Relevant code:

- `lib/routes/app_routes.dart:83`
- `lib/routes/app_routes.dart:95`
- `lib/routes/app_routes.dart:114`
- `lib/routes/app_routes.dart:123`
- `lib/routes/app_routes.dart:133`
- `lib/routes/app_routes.dart:149`

Finding:

Several routes use `settings.arguments! as ...`. If a route is pushed without
the expected arguments, the app can throw instead of recovering.

Why it matters:

Malformed deep links, stale notification routes, or future programmer mistakes
can cause visible crashes/red screens.

Recommendation:

- Add typed route helper methods.
- Validate route arguments inside `onGenerateRoute`.
- Return a recoverable error screen or redirect to a safe screen for invalid
  route state.

Remediation notes:

- Arg-required routes now use a typed `_args<T>()` helper.
- Invalid or missing args return `InvalidRouteScreen` instead of throwing during
  route generation.
- Test coverage exercises every arg-required route.

### Medium - Phone and Mobile Fields Are Not Format-Validated

Status: Fixed in the 2026-09-03 follow-up pass.

Relevant code:

- `lib/features/clients/domain/policies/client_form_validator.dart:13`
- `lib/features/clients/domain/policies/client_form_validator.dart:24`
- `lib/features/clients/widgets/sections/additional_contacts_section.dart:224`
- `firestore.rules:525`

Finding:

The client form validator explicitly notes that phone/mobile values are not
format-checked.

Why it matters:

Invalid phone numbers reduce trust and can break tap-to-call, search,
deduplication, and external sync behavior.

Recommendation:

- Normalize phone numbers before save.
- Validate minimum usable length and allowed characters.
- Keep formatting flexible for users, but store a normalized value for reliable
  behavior.

Remediation notes:

- Client phone, mobile, and additional-contact phone fields now validate minimum
  usable digit count and allowed characters.
- Add/edit client sheets surface phone validation errors inline.
- Save-time normalization now stores bare digits for phone, mobile, and
  additional-contact phone fields before Firestore writes.

### Medium - Additional Contacts Can Exceed Rule Limits Before Save

Status: Fixed in the 2026-09-03 remediation pass.

Relevant code:

- `lib/features/clients/widgets/client_form_state.dart:10`
- `lib/features/clients/widgets/client_form_state.dart:29`
- `lib/features/clients/widgets/sections/additional_contacts_section.dart`
- `firestore.rules:550`

Finding:

The UI allows adding additional contacts without a visible limit, while
Firestore rules limit contacts to 50.

Why it matters:

Users can spend time entering data that only fails at save time with a backend
permission error.

Recommendation:

- Disable "Add contact" at 50 contacts.
- Show a clear user-facing limit message.
- Keep the Firestore rule cap as backend enforcement.

Remediation notes:

- `kMaxAdditionalContacts` centralizes the 50-contact rule.
- The form state refuses additions at the cap.
- The additional contacts section disables add controls and shows a visible
  "Maximum 50 contacts" message.

## 4. Low-Priority and Polish Improvements

### Low - Some Controls Use Compact Tap Targets

Status: Partially fixed in the 2026-09-03 remediation pass.

Relevant code:

- `lib/features/calendar/screens/main_calendar_screen.dart:640`
- `lib/features/calendar/screens/main_calendar_screen.dart:662`
- `lib/features/settings/widgets/cards/notifications_settings_card.dart:101`
- `lib/features/settings/widgets/cards/notifications_settings_card.dart:123`

Finding:

Some controls use `MaterialTapTargetSize.shrinkWrap` or compact sizing.

Why it matters:

Small targets are harder to use on mobile, especially one-handed or in the
field.

Recommendation:

- Increase touch targets toward platform-recommended sizes.
- Keep visual density compact only where the actual hit area remains generous.

Remediation notes:

- Removed the audited `MaterialTapTargetSize.shrinkWrap` usage from compact
  calendar filters and notification switches.
- A repo-wide scan still shows other compact controls outside the originally
  cited audit locations; those should be reviewed separately if broader
  accessibility hardening is desired.

### Low - Bundled Config Is Named `dev/.env`

Status: Fixed in the 2026-09-03 follow-up pass; Google Cloud key restriction
review remains an owner-side operational check.

Relevant code:

- `pubspec.yaml`
- `lib/main.dart`
- `lib/firebase_options.dart`
- `ios/Runner/AppDelegate.swift`
- `dev/firebase.local.example.json`

Finding:

The app used to bundle and read `dev/.env` as a runtime asset. That included
Firebase identifiers and the iOS Maps SDK API key.

Why it matters:

Firebase client API keys are not secrets, but the iOS Maps key is billable and
must be restricted. Shipping a file named `dev/.env` in production also creates
configuration ambiguity.

Recommendation:

- Confirm Google Cloud restrictions for the Maps key: bundle ID, API scope, and
  quotas.
- Prefer production-specific build config or `--dart-define` for release
  values.
- Avoid shipping production apps with a config path named `dev`.

Remediation notes:

- `flutter_dotenv` and the bundled `dev/.env` asset were removed.
- Firebase client config now comes from compile-time `--dart-define` values.
- The iOS Maps key is provided to native Google Maps through a Flutter method
  channel from `IOS_MAPS_API_KEY`.

### Low - Android Support Is Ambiguous

Status: Accepted. Owner decision: iOS-only.

Relevant code:

- `.metadata:18`
- `.gitignore:101`
- `pubspec.yaml:178`
- `pubspec.yaml:185`
- `lib/firebase_options.dart:33`

Finding:

Android appears ignored/disabled in several places, but Flutter metadata and
Firebase options still reference Android.

Why it matters:

Ambiguous platform support increases maintenance risk and can lead to stale
configuration or accidental unsupported builds.

Recommendation:

- If iOS-only is intentional, remove or clearly guard Android support paths.
- If Android is still supported, restore Android as a tracked, tested platform.

Remediation notes:

- Runtime Firebase options now explicitly throw `UnsupportedError` on Android.
- `pubspec.yaml` already keeps Android splash/icon generation disabled.
- The ignored local `android/` folder, if present on a workstation, is not part
  of the tracked supported platform surface.

### Low - Destructive Client Actions Should Be Gated at the Action Builder

Status: Fixed in the 2026-09-03 remediation pass.

Relevant code:

- `lib/features/clients/screens/clients_screen.dart:113`
- `lib/features/clients/screens/clients_screen.dart:144`

Finding:

Admin-only access is mostly enforced by navigation/UI and backend rules, but
destructive list actions should also be guarded where actions are constructed.

Why it matters:

Defensive UI gating prevents confusing failed actions if a route is reached in
an unexpected state.

Recommendation:

- Gate archive/delete slide actions directly on `isAdmin`.
- Keep backend rules and callable guards as the final authority.

Remediation notes:

- `ClientsListView` now wraps rows in `Slidable` only for admin users.
- Non-admin route states render plain `ClientTile` rows without archive/delete
  actions.

### Low - High-Impact Appointment Actions Could Use Undo

Status: Fixed in the 2026-09-03 follow-up pass.

Finding:

Appointment status changes are optimized for speed.

Why it matters:

Fast field workflows are good, but accidental status changes can create
operational confusion.

Recommendation:

- Add undo snackbars or confirmation for high-impact transitions such as
  marking an appointment done.

Remediation notes:

- Mark-complete success notices now include an Undo action.
- Undo calls `restoreAppointmentStatus`, a Cloud Function that validates the
  active caller is an admin or assigned employee and restores the previous open
  status while clearing `completedAt`.

## 5. Security Improvements

### Keep

- App Check activation in `lib/main.dart:137`.
- Crashlytics integration in `lib/main.dart:121`.
- Firestore offline persistence in `lib/main.dart:109`.
- Role-based Firestore rules in `firestore.rules`.
- Appointment image access restrictions in `storage.rules`.
- Callable guards and durable rate limiting in `functions/security.js`.
- Secure local storage for auth-adjacent state.
- Secret Manager use for server-side Google Places calls.

### Improve

- Consider encrypting pending image upload queue metadata.
- Bind background upload work to the signed-in account that created it. (Done.)
- Add explicit location-sharing consent and settings. (Done.)
- Restrict the shipped iOS Maps SDK key.
- Move autocomplete to durable rate limiting. (Done.)
- Reduce raw UID logging in warnings. (Partially done for the touched
  security/client paths.)
  - `functions/security.js:249`
  - `functions/security.js:282`
  - `functions/clients.js:63`

## 6. Performance Improvements

### Keep

- `IndexedStack` plus `TickerMode` in the hub layout.
- Cached history/search windows.
- Debounced address autocomplete.
- Reverse-geocode success/failure caching.
- Image memory and disk caches.
- Foreground location throttling with upload gaps and distance filters.

### Improve

- Replace capped local scan-window searches with indexed/server-side search.
- Add server-side appointment conflict validation.
- Review retained tab memory when Calendar, Clients, Employees, and Live Map
  have all been opened.
- Add user-visible handling when data caps are reached.
- Consider explicit read timeouts and retry UX for long Firestore reads.

## 7. UI and UX Improvements

### Keep

- Adaptive master-detail layouts.
- Calendar split view and responsive collapse behavior.
- Good loading, empty, and error states.
- Offline banner and connectivity-aware write handling.
- High contrast themes.
- Text scaling support.
- Reduced-motion route transitions in `lib/routes/app_routes.dart:209`.
- Contextual address autocomplete and retry affordances.

### Improve

- Move notification and location permission prompts behind explanatory UI.
  (Done for notification prompt behavior and location-sharing consent gating.)
- Increase compact control tap targets. (Partially done for audited controls.)
- Add route-level recovery instead of red-screen failures. (Done.)
- Surface incomplete-result/cap-hit warnings where users can see them.
- Add undo or confirmation for destructive or high-impact actions.

## 8. Code-Quality and Architecture Improvements

### Keep

- Clear repository/domain separation.
- Centralized validators and domain policies.
- Strong architecture documentation in `docs/ARCHITECTURE.md`.
- Firebase rules with extensive comments.
- Cloud Functions guard helpers.
- Clean analyzer result.

### Improve

- Add typed navigation APIs to avoid repeated `settings.arguments!` casts.
  (Done for audited route generation paths.)
- Add ownership-aware lifecycle cleanup for all background jobs. (Done for
  pending image uploads.)
- Resolve iOS-only vs Android support ambiguity.
- Move scale-sensitive search and scheduling checks out of client-side scans.
- Add automated accessibility/golden tests for small screens, high contrast, and
  large text.

## 9. Dependency Findings

### Flutter and Dart Dependencies

Based on `flutter pub outdated --no-transitive` from the project root:

| Package | Current | Upgradable | Resolvable | Latest | Recommendation |
| --- | ---: | ---: | ---: | ---: | --- |
| `cloud_firestore` | `6.6.0` | `6.6.0` | `6.9.0` | `6.9.0` | Upgrade with the Firebase package family. |
| `cloud_functions` | `6.3.3` | `6.3.3` | `6.4.0` | `6.4.0` | Upgrade with the Firebase package family. |
| `firebase_app_check` | `0.4.5` | `0.4.5` | `0.4.7` | `0.4.7` | Upgrade with the Firebase package family. |
| `firebase_auth` | `6.5.4` | `6.5.4` | `6.6.1` | `6.6.1` | Upgrade with the Firebase package family. |
| `firebase_core` | `4.11.0` | `4.11.0` | `4.14.0` | `4.14.0` | Change the exact pin in `pubspec.yaml` to a caret constraint. |
| `firebase_crashlytics` | `5.2.4` | `5.2.4` | `5.3.0` | `5.3.0` | Upgrade with the Firebase package family. |
| `firebase_messaging` | `16.4.1` | `16.4.1` | `16.6.0` | `16.6.0` | Upgrade with the Firebase package family. |
| `firebase_storage` | `13.4.3` | `13.4.3` | `13.5.0` | `13.5.0` | Upgrade with the Firebase package family. |
| `google_maps_flutter_ios_sdk9` | `2.18.6` | `2.18.11` | `2.18.11` | `2.18.11` | Safe lockfile-level upgrade candidate. |
| `home_widget` | `0.9.3` | `0.9.4` | `0.9.4` | `0.9.4` | Safe lockfile-level upgrade candidate. |
| `flex_color_picker` | `3.8.0` | `3.8.0` | `3.8.0` | `4.0.0` | Major upgrade; handle separately. |
| `flutter_secure_storage` | `10.3.1` | `10.3.1` | `11.0.0` | `11.0.0` | Major upgrade; test auth/session storage carefully. |
| `permission_handler` | `12.0.3` | `12.0.3` | `12.0.3` | `13.0.1` | Major upgrade; test notification, contacts, photo, and location permission flows. |
| `smooth_page_indicator` | `2.0.1` | `2.0.1` | `3.0.0` | `3.0.0` | Major upgrade; test onboarding/showcase UI. |
| `build_runner` | `2.15.1` | `2.15.1` | `2.15.1` | `2.16.1` | Dev-only major/minor maintenance; run code generation and tests. |
| `freezed` | `3.2.5` | `3.2.5` | `3.2.5` | `4.0.1` | Major upgrade; test generated models and serialization. |
| `very_good_analysis` | `10.3.0` | `10.3.0` | `10.3.0` | `11.0.0` | Major upgrade; expect new lint findings. |
| `intl` | `0.20.2` | `0.20.2` | `0.20.2` | `0.20.3` | Leave for now; likely constrained by Flutter/localizations. |

Recommended Flutter upgrade order:

1. Run a safe lockfile update for `google_maps_flutter_ios_sdk9` and
   `home_widget`.
2. Upgrade the Firebase packages together as a coordinated FlutterFire bump.
3. Run `flutter analyze` and the test suite.
4. Handle major upgrades one at a time, especially `flutter_secure_storage`,
   `permission_handler`, and `freezed`.

Recommended Firebase target constraints:

```yaml
firebase_core: ^4.14.0
firebase_auth: ^6.6.1
cloud_firestore: ^6.9.0
firebase_storage: ^13.5.0
firebase_app_check: ^0.4.7
firebase_crashlytics: ^5.3.0
cloud_functions: ^6.4.0
firebase_messaging: ^16.6.0
```

### Cloud Functions Dependencies

Based on `npm outdated --depth=0` from `functions/`:

| Package | Current | Wanted | Latest | Priority |
| --- | ---: | ---: | ---: | --- |
| `eslint` | `8.57.1` | `8.57.1` | `10.9.1` | Low |
| `firebase-admin` | `13.10.0` | `13.10.0` | `14.3.0` | Low |
| `jest` | `29.7.0` | `29.7.0` | `30.5.1` | Low |

These are major-version upgrades, not urgent patch-level fixes.

Recommendation:

- Schedule a maintenance pass.
- Upgrade one package at a time.
- Read migration notes before each major upgrade.
- Run the full Cloud Functions test suite after each package upgrade.

## 10. Features Worth Adding

- Explicit location-sharing privacy screen with:
  - enabled/disabled state
  - last uploaded time
  - pause sharing
  - clear my location
- Offline drafts or retry queue for appointment/client edits.
- Admin diagnostics for:
  - pending photo uploads
  - notification token health
  - capped search windows
  - failed external syncs
- Undo for archive/delete/status-change actions.
- More granular notification preferences.
- Accessibility test coverage for:
  - large text
  - high contrast
  - small screens
  - reduced motion

## Prioritized Fix Order

1. Done - Fix pending photo upload ownership and cleanup.
2. Done - Add explicit location-sharing consent and gate presence uploads.
3. Done - Stop automatic notification permission prompts during startup/account
   sync.
4. Done - Add server-side or indexed appointment conflict validation.
5. Done - Replace capped client/history search scans with scalable search.
6. Done - Move Places autocomplete to durable rate limiting.
7. Done - Add route argument validation and typed route helpers.
8. Done - Add phone validation, additional-contact UI limits, and phone
   save-time normalization.
9. Done/accepted - Review iOS deployment target and Android support posture.
10. Open - Schedule dependency major-version upgrades.

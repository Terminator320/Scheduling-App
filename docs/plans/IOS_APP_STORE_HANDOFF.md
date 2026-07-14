# iOS App Store Handoff — Mac Runbook

Written 2026-07-08 · branch `moblie` · v1.25.1+44 · launch scope: **App Store only**
(status re-verified against the committed Xcode project on 2026-07-11, branch
`notification`, v1.29.0+48 — the iOS project tasks in steps 3 and 9 are already
done in-repo; the remaining `[ ]` items are console/hardware/App-Store-Connect).
(Android stays a dev-only target on the Windows box — see
`docs/audits/CODEBASE_AUDIT.md` for the full readiness audit; its Play items are
parked as N/A).

Everything below is ordered. Steps 0 happens on the Windows box; everything
else happens on the Mac. Server-side work is already done and verified live:
App Check is **enforced on every callable** in production, and the deployed
Firestore/Storage rules match the repo. That means a misconfigured iOS App
Check provider doesn't degrade gracefully — **every callable fails** — so the
App Attest steps are the critical path.

---

## 0. Before leaving the Windows box

- [x] **Commit + push `moblie`** so the Mac clone has: the
  `AppleAppAttestProvider` swap in `lib/main.dart`, the proguard cleanup, the
  updated audit report, and this handoff doc.
- [x] **CLAUDE.md is gitignored** (`.gitignore:20`) — committing it needs
  `git add -f CLAUDE.md`. (`.claude/` rules/skills are also ignored at
  `.gitignore:151` and will NOT be on the Mac unless force-added too.)
- [x] **Carry these gitignored files out-of-band** (AirDrop/USB — not email):
  - `dev/.env` → `dev/.env` (all 7 keys incl. `IOS_API_KEY`/`IOS_APP_ID`; it's
    a bundled asset — the app won't boot without it)
  - `ios/GoogleService-Info.plist` → `ios/` **root** (NOT `ios/Runner/` — the
    Xcode project references it at the root group and it's already in the
    Resources build phase)
  - `android/app/google-services.json` — NOT needed for iOS builds; skip.

## 1. Mac environment

- [x] **Xcode** — latest stable (Firebase iOS SDK 12.x requires Xcode 16.2+;
  deployment target is iOS 15.0). Sign into the Apple ID for team
  **H5XWLU87AX**; Developer Program membership must be active.
- [x] **Flutter 3.44.1 stable** — match the Windows box version to avoid
  `Package.resolved`/codegen churn. `flutter doctor` until clean.
- [x] **No CocoaPods.** The project uses **Swift Package Manager** — there is
  no Podfile and never will be. Ignore any older notes mentioning
  `pod install` or `${PODS_ROOT}`. Xcode resolves `firebase-ios-sdk` (pinned in
  `Package.resolved`) on first open.
- [x] **Do NOT run `flutterfire configure`.** `lib/firebase_options.dart`
  already builds iOS options from `dev/.env` (`IOS_API_KEY`, `IOS_APP_ID`) with
  `iosBundleId: net.vogas.scheduling` — re-running it would rewrite the file
  into the literal-values style and break the env-based setup.

## 2. Clone, restore, first run

- [x] `git clone` → `git checkout moblie` → drop the two carried files into
  place (step 0).
- [x] `flutter pub get`. l10n regenerates automatically on build
  (`generate: true`; `lib/l10n/.gen/` is gitignored — `flutter gen-l10n` runs
  it manually if the IDE complains before the first build).
- [x] **Smoke run on the Simulator is fine at this stage** — debug builds use
  `AppleDebugProvider`. On first run, the console prints an App Check **debug
  token**: register it in Firebase Console → App Check → apps → iOS app →
  Manage debug tokens. (Unregistered token symptom: every callable and
  non-cached Firestore read fails `permission-denied` while cached reads work —
  looks collection-specific, isn't.)

## 3. Xcode one-time project tasks

Open `ios/Runner.xcworkspace`.

> **Status (verified against committed project 2026-07-11):** the three project
> tasks below are already DONE in `ios/Runner/Runner.entitlements` and
> `Runner.xcodeproj/project.pbxproj` — App Attest env = `production`, the
> Crashlytics dSYM Run Script (SPM path + 5 input files, dependency-analysis
> off), and Release `DEBUG_INFORMATION_FORMAT = dwarf-with-dsym`. Also present:
> Push Notifications (`aps-environment = production`) and App Groups on both
> Runner and the widget extension. Left as reference / verify-don't-redo.

- [x] **App Attest capability** — `Runner.entitlements` has
  `com.apple.developer.devicecheck.appattest-environment = production`.
  (A `development` value breaks attestation on TestFlight/App Store builds.)
- [x] **Crashlytics dSYM upload Run Script** — Build Phases, **last** phase.
  SPM path (not the CocoaPods one):

  ```
  "${BUILD_DIR%/Build/*}/SourcePackages/checkouts/firebase-ios-sdk/Crashlytics/run"
  ```

  Input files:
  ```
  ${DWARF_DSYM_FOLDER_PATH}/${DWARF_DSYM_FILE_NAME}
  ${DWARF_DSYM_FOLDER_PATH}/${DWARF_DSYM_FILE_NAME}/Contents/Resources/DWARF/${PRODUCT_NAME}
  ${DWARF_DSYM_FOLDER_PATH}/${DWARF_DSYM_FILE_NAME}/Contents/Info.plist
  $(TARGET_BUILD_DIR)/$(UNLOCALIZED_RESOURCES_FOLDER_PATH)/GoogleService-Info.plist
  $(TARGET_BUILD_DIR)/$(EXECUTABLE_PATH)
  ```
  Uncheck "Based on dependency analysis". Commit the pbxproj change.
- [x] **Release "Debug Information Format" = DWARF with dSYM File** — confirmed
  in `project.pbxproj` (Release/Profile = `dwarf-with-dsym`, Debug = `dwarf`).
- [x] **Signing sanity check** — automatic signing, team H5XWLU87AX, bundle
  `net.vogas.scheduling` are already in the project; once signed into the team
  it should Just Work.
- [x] **iPad: KEEP (decided 2026-07-08).** `TARGETED_DEVICE_FAMILY = "1,2"`
  stays as-is — the app ships for iPhone **and** iPad. Consequences: the
  listing needs an iPad screenshot set, App Review will test on iPad, and the
  step-5 hardware verification should include an iPad (or at minimum the
  split/master-detail layouts at tablet width) — the `isSplitLayout` nav-rail +
  two-pane chrome is the surface iPad users get.

## 4. Firebase Console (any browser)

- [x] App Check → apps → **iOS app → register App Attest** as the attestation
  provider. No `.p8` key — that's DeviceCheck, which this app does not use.
  The console provider MUST match the code (`AppleAppAttestProvider`,
  `lib/main.dart:100`).
- [x] Keep the debug-token registrations for the Simulator/dev devices.

## 5. Verify on real hardware (App Attest does NOT work on the Simulator)

- [x] `flutter run --release` on a physical iPhone.
- [x] Sign in, then **exercise a callable end-to-end** to prove attestation —
  e.g. type an address in the appointment form (`placesAutocomplete`) or open
  Settings → Wave section as admin (`waveGetConnection`). If App Attest is
  misconfigured, these fail while plain Firestore reads may still work.
- [x] Device-only feature sweep (never covered by the test harness): camera
  capture, photo-library picker, contacts save-flow, biometric app-lock
  (Face ID — usage description already declared), map launching, phone/email
  launchers.
- [x] Both locales: flip the device to French and spot-check (EN/FR parity is
  clean in code — this is a rendering sanity pass).

## 6. Archive + upload

- [ ] `flutter build ipa` (or Xcode Product → Archive → Organizer →
  Distribute). Upload via Organizer or Transporter.
- [ ] **TestFlight internal testing first.** TestFlight builds are store-signed
  so App Attest works there. Do NOT use Firebase App Distribution for iOS —
  sideloads can't mint verified App Check tokens and are blocked by design.
- [ ] Post-upload: Crashlytics console shows the build's dSYMs processed (no
  "missing dSYM" banner) — that proves the step-3 Run Script works.

## 7. App Store Connect

- [x] App record: **ES Pro**, bundle `net.vogas.scheduling`. Provide **French
  metadata alongside English** (Quebec audience; the app itself is bilingual).
- [ ] **Privacy questionnaire** — the repo half is done
  (`PrivacyInfo.xcprivacy` tracked; `ITSAppUsesNonExemptEncryption=false` so no
  export-compliance prompt at upload). Declare in the questionnaire: account
  email + name/phone (users), customer contact data (clients in Firestore:
  name/phone/address/email), photos (appointment images), crash data
  (Crashlytics). Data is linked to identity (account-based); **no tracking**
  (matches `NSPrivacyTracking = false`).
- [x] **Privacy policy authored + hosted (live 2026-07-11)** —
  `docs/legal/privacy-policy.html`, published at
  `https://gvogas.github.io/es-pro-legal/`; the app links it from
  Settings → Legal via `AppUrls.privacyPolicy`
  (`lib/core/constants/app_urls.dart`).
- [x] Paste that URL into the App Store Connect "Privacy Policy URL" field
  at submission (App Store Connect requires one for any account-based app).
- [x] **Demo account for App Review** — signup is invite-only (one-time codes),
  so App Review cannot self-register. Create a dedicated demo account
  (employee role is safest; admin if you want them to see the full app) and put
  the credentials in the Review notes. Don't hand Review a real customer's
  data view — consider a demo dataset.
- [ ] **Account deletion requirement** — already satisfied: in-app account
  deletion exists (`deleteAccount` callable + ACCT-DEL flow). Mention it in
  Review notes if asked.
- [x] Screenshots: 6.9" and 6.5" iPhone sets **plus a 13" iPad set** (iPad is
  kept — see step 3). Age rating questionnaire, support URL.

## 8. What's intentionally NOT here

The rest of the audit's findings and the parked Play items live in
`docs/audits/CODEBASE_AUDIT.md` — notably the two Low security notes
(debug-signing fallback: dormant while Android is dev-only; `functions/`
transitive npm advisories: `npm audit fix` whenever convenient). Nothing in
that report blocks the steps above.

## 9. Push Notifications + iOS Widget (Mac steps)

Everything Windows-buildable already landed (branch `notification`): FCM Cloud
Functions (`functions/notifications.js` + `notification_utils.js`), Firestore
rules for `fcmTokens` / `appointmentReminders`, the Flutter client
(`push_notification_service.dart`, `fcm_token_repository.dart`,
`push_registration_controller.dart`, main.dart wiring), the widget data-sync
(`home_widget/application/widget_sync_service.dart`), and the pre-authored
Swift widget (`ios/ScheduleWidget/ScheduleWidget.swift`). These Mac-only steps
remain.

### Push notifications
- [x] **APNs Auth Key** — created + noted Key ID / Team ID (2026-07-11).
- [x] **Firebase** — `.p8` uploaded to Cloud Messaging for the iOS app
  `net.vogas.scheduling` (2026-07-11).
- [x] **Xcode capability** — **Push Notifications** added to Runner;
  `Runner.entitlements` committed (2026-07-11). `aps-environment` corrected
  from `development` → **`production`** (2026-07-11) so TestFlight/App Store
  builds hit the production APNs gateway.
- [x] **`UIBackgroundModes` → `remote-notification`** committed in
  `ios/Runner/Info.plist` (no Mac action — it's in-repo). Required so the
  change-driven pushes, which now ride with `content-available`, wake the app
  in the background to rewrite the home-screen widget with the app closed (see
  "Wake-on-push widget refresh" below). **Never** run `flutterfire configure`.
  SwiftPM pulls `FirebaseMessaging` automatically on first open.
- [x] Functions + rules deployed 2026-07-11 (all 4 push functions +
  `deleteAccount` re-deploy + `firestore:rules`).
- [x] Firestore **TTL policies** enabled on the `expiresAt` field of BOTH
  ledger collections (`appointmentReminders` and `appointmentOverduePrompts`)
  (2026-07-11) — ledger docs self-delete ~7 days after creation.

### iOS home-screen widget
- [x] **Widget Extension target** — `ScheduleWidget` extension added with the
  pre-authored `ios/ScheduleWidget/ScheduleWidget.swift` (2026-07-11).
- [x] **App Groups** — `group.net.vogas.scheduling` added to **BOTH** Runner
  and the ScheduleWidget extension (2026-07-11).
- [x] Extension deployment target set to **iOS 15.0** (matches Runner).

### Device verification (physical iPhone — App Attest fails on Simulator)
- [x] Employee sign-in → a `users/{docId}/fcmTokens/{token}` doc appears in the
  console; sign-out deletes it. (Admins get no prompt and no token doc.)
- [x] Admin creates / reschedules / cancels / unassigns an appointment → the
  correct localized push arrives with the app **killed**.
- [x] Appointment starting ~28 min out → a reminder within ~5 min; an
  `appointmentReminders/{id}_{startMs}` ledger doc is written; move the time →
  a fresh reminder under the new key (no duplicate for the old one).
- [x] Digest: seed a job for tomorrow, then trigger `sendDailyJobDigest` from
  the console (or wait for 18:00 America/Toronto) → one summary push.
- [x] Overdue prompt: seed a job whose `endTime` passed a few minutes ago,
  status still `pending`/`in_progress` → "Job finished?" push within ~15 min;
  an `appointmentOverduePrompts/{id}_{endMs}` ledger doc is written; a second
  sweep sends nothing; marking it Done before the sweep suppresses it.
- [x] FR-language device receives French text (the token's `locale` field).
- [ ] Tapping a notification from killed/background surfaces the calendar hub.
- [ ] Add the widget in all three sizes → today's jobs render; a job rolls off
  the small widget once it starts; sign-out clears the widget.
- [ ] **Wake-on-push widget refresh** — with the employee's app **fully closed
  or backgrounded**, have an admin assign / reschedule / cancel a job for a
  later time today. The home-screen widget updates to reflect it **without
  opening the app** (`content-available` wakes
  `firebaseMessagingBackgroundHandler`, which rewrites the App Group payload).
  The visible push still shows alongside. iOS throttles background wakes under
  Low Power Mode — allow a short delay. A FR-language device shows the widget
  chrome in French (the push carries a per-token-locale payload).

### Known deferrals (documented, not bugs)
- **Deep-link on notification tap**: the tap surfaces the calendar hub at the
  stack root; jumping to the specific `data.appointmentId` is a future link.
- **Android foreground banner**: FCM shows no banner while the app is
  foregrounded on Android (background/killed delivery works). Android is the
  dev harness only, so this is accepted.
- **Series bulk edits** write N appointment docs → N pushes; accepted for v1
  (each is a real change).

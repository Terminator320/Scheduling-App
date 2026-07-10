# iOS App Store Handoff — Mac Runbook

Written 2026-07-08 · branch `moblie` · v1.25.1+44 · launch scope: **App Store only**
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

- [ ] **Xcode** — latest stable (Firebase iOS SDK 12.x requires Xcode 16.2+;
  deployment target is iOS 15.0). Sign into the Apple ID for team
  **H5XWLU87AX**; Developer Program membership must be active.
- [ ] **Flutter 3.44.1 stable** — match the Windows box version to avoid
  `Package.resolved`/codegen churn. `flutter doctor` until clean.
- [ ] **No CocoaPods.** The project uses **Swift Package Manager** — there is
  no Podfile and never will be. Ignore any older notes mentioning
  `pod install` or `${PODS_ROOT}`. Xcode resolves `firebase-ios-sdk` (pinned in
  `Package.resolved`) on first open.
- [ ] **Do NOT run `flutterfire configure`.** `lib/firebase_options.dart`
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

- [ ] **App Attest capability** — Runner target → Signing & Capabilities →
  `+ Capability` → App Attest. This creates `Runner.entitlements` (none exists
  today) with `com.apple.developer.devicecheck.appattest-environment`. Set the
  value to **`production`** (a `development` value breaks attestation on
  TestFlight/App Store builds). **Commit the new entitlements file and the
  pbxproj change.**
- [ ] **Crashlytics dSYM upload Run Script** — Build Phases → `+` → New Run
  Script Phase, dragged to be the **last** phase. SPM path (not the CocoaPods
  one):

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
- [ ] **Verify Release "Debug Information Format" = DWARF with dSYM File**
  (Build Settings → Runner target → Release/Profile). Flutter's template
  default usually already is — verify, don't assume.
- [ ] **Signing sanity check** — automatic signing, team H5XWLU87AX, bundle
  `net.vogas.scheduling` are already in the project; once signed into the team
  it should Just Work.
- [x] **iPad: KEEP (decided 2026-07-08).** `TARGETED_DEVICE_FAMILY = "1,2"`
  stays as-is — the app ships for iPhone **and** iPad. Consequences: the
  listing needs an iPad screenshot set, App Review will test on iPad, and the
  step-5 hardware verification should include an iPad (or at minimum the
  split/master-detail layouts at tablet width) — the `isSplitLayout` nav-rail +
  two-pane chrome is the surface iPad users get.

## 4. Firebase Console (any browser)

- [ ] App Check → apps → **iOS app → register App Attest** as the attestation
  provider. No `.p8` key — that's DeviceCheck, which this app does not use.
  The console provider MUST match the code (`AppleAppAttestProvider`,
  `lib/main.dart:100`).
- [ ] Keep the debug-token registrations for the Simulator/dev devices.

## 5. Verify on real hardware (App Attest does NOT work on the Simulator)

- [ ] `flutter run --release` on a physical iPhone.
- [ ] Sign in, then **exercise a callable end-to-end** to prove attestation —
  e.g. type an address in the appointment form (`placesAutocomplete`) or open
  Settings → Wave section as admin (`waveGetConnection`). If App Attest is
  misconfigured, these fail while plain Firestore reads may still work.
- [ ] Device-only feature sweep (never covered by the test harness): camera
  capture, photo-library picker, contacts save-flow, biometric app-lock
  (Face ID — usage description already declared), map launching, phone/email
  launchers.
- [ ] Both locales: flip the device to French and spot-check (EN/FR parity is
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

- [ ] App record: **ES Pro**, bundle `net.vogas.scheduling`. Provide **French
  metadata alongside English** (Quebec audience; the app itself is bilingual).
- [ ] **Privacy questionnaire** — the repo half is done
  (`PrivacyInfo.xcprivacy` tracked; `ITSAppUsesNonExemptEncryption=false` so no
  export-compliance prompt at upload). Declare in the questionnaire: account
  email + name/phone (users), customer contact data (clients in Firestore:
  name/phone/address/email), photos (appointment images), crash data
  (Crashlytics). Data is linked to identity (account-based); **no tracking**
  (matches `NSPrivacyTracking = false`).
- [ ] **Privacy policy URL** — App Store Connect requires one for any
  account-based app. None exists in the repo; this needs to be authored and
  hosted before submission.
- [ ] **Demo account for App Review** — signup is invite-only (one-time codes),
  so App Review cannot self-register. Create a dedicated demo account
  (employee role is safest; admin if you want them to see the full app) and put
  the credentials in the Review notes. Don't hand Review a real customer's
  data view — consider a demo dataset.
- [ ] **Account deletion requirement** — already satisfied: in-app account
  deletion exists (`deleteAccount` callable + ACCT-DEL flow). Mention it in
  Review notes if asked.
- [ ] Screenshots: 6.9" and 6.5" iPhone sets **plus a 13" iPad set** (iPad is
  kept — see step 3). Age rating questionnaire, support URL.

## 8. What's intentionally NOT here

The rest of the audit's findings and the parked Play items live in
`docs/audits/CODEBASE_AUDIT.md` — notably the two Low security notes
(debug-signing fallback: dormant while Android is dev-only; `functions/`
transitive npm advisories: `npm audit fix` whenever convenient). Nothing in
that report blocks the steps above.

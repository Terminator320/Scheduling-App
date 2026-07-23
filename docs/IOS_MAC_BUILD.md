# First iOS Build on a Mac — Set-by-Set

The config side of the iOS port is **done** (deployment target 18.0 in
`project.pbxproj` and `AppFrameworkInfo.plist`, `Info.plist` +
`PrivacyInfo.xcprivacy` in place, `main.dart` already using
`DefaultFirebaseOptions.currentPlatform`). What's left is Mac-only: native
tooling, the two gitignored secret files, the Crashlytics build phase, the App
Attest capability, and device verification.

> **This project uses Swift Package Manager — there is no `Podfile` and never
> will be.** Ignore any older notes mentioning `pod install` / `${PODS_ROOT}`.
> Xcode resolves `firebase-ios-sdk` (pinned in `Package.resolved`) on first open.

Bundle id: `net.vogas.scheduling`. iOS Firebase app:
`1:914958291749:ios:c0f5d0899187badf0d00cc`.

**One-time:** Phases A, B, and the Xcode steps in D/E.
**Every build:** Phases C and F.

---

## Phase A — One-time machine setup

1. Install **Xcode 16.2+** from the App Store. Launch once, accept the license,
   let it install components. Then:
   ```bash
   sudo xcodebuild -license accept
   xcode-select --install        # command-line tools
   ```
2. Install **Flutter 3.44** (match the Windows SDK), add it to PATH, then:
   ```bash
   flutter doctor                 # resolve any iOS-toolchain ✗ it reports
   ```
3. **Clone the repo** to the Mac.

## Phase B — Carry over the gitignored secrets (NOT in git)

These are gitignored — a fresh clone won't have them. Transfer via
AirDrop/USB/secure channel; **never commit them**:

| File | Needed for |
|---|---|
| `dev/.env` | Firebase client config (incl. `IOS_API_KEY` / `IOS_APP_ID`) |
| `ios/GoogleService-Info.plist` | iOS Firebase — lives at the `ios/` **root**, not `ios/Runner/` |
| `android/app/google-services.json` | only if also building Android on the Mac |

- Confirm `dev/.env` contains **`IOS_API_KEY`** and **`IOS_APP_ID`** —
  `firebase_options.dart`'s iOS block reads them. Do **not** re-run
  `flutterfire configure` — it rewrites `firebase_options.dart` into the
  literal-values style and breaks the env-based setup.
- If `GoogleService-Info.plist` is lost: re-download from Firebase Console → the
  iOS app above (bundle `net.vogas.scheduling`) and drop it at `ios/`.

## Phase C — Flutter deps (no Pods)

```bash
flutter pub get
flutter gen-l10n                                          # generated l10n is gitignored
dart run build_runner build --delete-conflicting-outputs # only if freezed models changed
```

No `pod install` step exists. The Swift Package dependencies (`firebase-ios-sdk`,
pinned in `ios/Runner.xcodeproj/.../swiftpm/Package.resolved`) are resolved by
Xcode automatically the first time you open the project — it may take a minute
on first open while it fetches the packages.

## Phase D — Xcode config (the Mac-only GUI bits)

1. Open the **project** (SPM needs no workspace):
   ```bash
   open ios/Runner.xcodeproj
   ```
   Wait for *Package Dependencies* to finish resolving in the left navigator.
2. **Signing:** Runner target → *Signing & Capabilities* → select your Apple
   Developer **Team**. Bundle id is already `net.vogas.scheduling`.
3. **Add the App Attest capability** (App Check uses App Attest in Release —
   `AppleAppAttestProvider` in `main()`): *Signing & Capabilities* → `+ Capability`
   → **App Attest**. This adds the entitlement
   `com.apple.developer.devicecheck.appattest-environment`; set it to
   **`production`** for the Release configuration. The console provider must
   match (see Phase G) or attestation is rejected. The app targets iOS 18.0
   (well above App Attest's 14+ requirement); App Attest **fails on the
   Simulator** — verify on real hardware.
4. **Add the Crashlytics Run Script phase** (not present yet): Runner target →
   *Build Phases* → `+` → *New Run Script Phase*, placed **after** the Flutter
   build phases. NOTE: per CLAUDE.md the dSYM upload phase is wired on **all
   three** code-bearing targets (Runner, ScheduleWidgetExtension, SiriIntents) —
   the two extension phases pass `-gsp "${PROJECT_DIR}/GoogleService-Info.plist"`
   and need `ENABLE_USER_SCRIPT_SANDBOXING = NO`. See `APP_STORE_SUBMISSION.md`
   for the full three-target runbook.
   - **Script** (SPM checkout path, not `${PODS_ROOT}`):
     ```
     "${BUILD_DIR%/Build/*}/SourcePackages/checkouts/firebase-ios-sdk/Crashlytics/run"
     ```
   - **Input Files:**
     ```
     ${DWARF_DSYM_FOLDER_PATH}/${DWARF_DSYM_FILE_NAME}/Contents/Resources/DWARF/${TARGET_NAME}
     $(SRCROOT)/$(BUILT_PRODUCTS_DIR)/$(INFOPLIST_PATH)
     ```
5. **dSYM build settings** (Runner target → *Build Settings*): *Debug
   Information Format* = `DWARF with dSYM File` for the Release
   configuration, so Crashlytics gets symbol files to upload.
6. **Verify** the deployment target shows **iOS 18.0** (set on all targets in
   `project.pbxproj` and `AppFrameworkInfo.plist`; the Siri App Intents
   extension needs 16 and the Live Activity `OpenURLIntent` needs 18, so the
   whole app is on an 18.0 floor).

## Phase E — App Check debug token (Simulator / dev builds)

Debug builds use `AppleDebugProvider` (see `main.dart`), so on a simulator or
dev device App Check runs off a registered debug token — App Attest is Release-only.

1. Run on a simulator/dev device, watch the Xcode console for the **App Check
   debug token** line.
2. Register it: Firebase Console → *App Check* → your iOS app → *Manage debug
   tokens*. Re-register after a full reinstall — the token regenerates. An
   unregistered token makes writes + non-cached reads fail `permission-denied`
   while cached reads still succeed (looks collection-specific, isn't).

## Phase F — Build, run, verify on a real device

```bash
flutter run        # pick the iOS simulator/device
```
Walk the **device-only checklist** (none covered by the test harness):
- Camera capture (`image_source_picker.dart`)
- Gallery / OS photo picker
- **Face ID app-lock** (`NSFaceIDUsageDescription` declared)
- **Save-to-contacts** (`NSContactsUsageDescription`)
- Image upload pipeline (compress → upload) and image cleanup on delete
- **App Attest** on a **real device** in a Release build (fails on Simulator)
- **Admin live staff map** — needs `IOS_MAPS_API_KEY` in `dev/.env` (blank key →
  the map renders blank; see `AppDelegate.swift`)
- **Push notifications** — assignment/reminder/overdue pushes + tap deep-link
- **Background GPS presence** (`geolocator`) — powers the "time to leave" reminder
- **iOS Live Activities** — the "time to leave" Lock Screen card (iOS 17.2+;
  Dynamic Island needs Pro hardware)
- **Siri App Intents** — the read intents (count / today / next / a specific day)

## Phase G — Before TestFlight / App Store (not for dev builds)

1. **Enable App Attest in the Firebase Console** (Build → App Check → the iOS
   app) so the console provider matches the code's `AppleAppAttestProvider`. No
   `.p8` key is required for App Attest (unlike DeviceCheck). A mismatch between
   the console provider and the code provider is rejected as `permission-denied`.
   (All Cloud Function callables already enforce App Check — nothing to flip in
   `functions/`; the old pre-ship `enforceAppCheck: false` carve-out was retired
   in 1.25.1.)
2. Bump `+BUILD` in `pubspec.yaml` + add a `CHANGELOG.md` entry, then **Archive**
   in Xcode (*Product → Archive*) and upload.
3. **Verify Crashlytics symbolication:** on the first TestFlight build,
   trigger a test crash and confirm the symbolicated report appears in the
   Firebase Crashlytics console within ~10 minutes (proves the Run Script
   phase + dSYM settings from Phase D are correct).

## App Store compliance notes (only if the app changes)

Neither applies today — recorded so they aren't forgotten:

- **App Tracking Transparency:** if an analytics/ads SDK with cross-app
  tracking is ever added, present the ATT prompt and add
  `NSUserTrackingUsageDescription` to `Info.plist`. (`PrivacyInfo.xcprivacy`
  currently declares `NSPrivacyTracking: false`.)
- **Sign in with Apple:** required by Apple as soon as any third-party
  sign-in provider (Google, Facebook, …) is offered. Not required for the
  current Firebase email/password-only auth.

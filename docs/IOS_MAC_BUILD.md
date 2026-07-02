# First iOS Build on a Mac — Set-by-Set

The config side of the iOS port is **done** (deployment target 15.0 in
`project.pbxproj` and `AppFrameworkInfo.plist`, `Info.plist` +
`PrivacyInfo.xcprivacy` in place, `main.dart` already using
`DefaultFirebaseOptions.currentPlatform`). What's left is Mac-only: native
tooling, the generated `Podfile` (see Phase C), the two gitignored secret
files, the Crashlytics build phase, and device verification.

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
2. Install **CocoaPods**:
   ```bash
   sudo gem install cocoapods     # or: brew install cocoapods
   ```
3. Install **Flutter 3.44** (match the Windows SDK), add it to PATH, then:
   ```bash
   flutter doctor                 # resolve any iOS-toolchain ✗ it reports
   ```
4. **Clone the repo** to the Mac.

## Phase B — Carry over the gitignored secrets (NOT in git)

These are gitignored — a fresh clone won't have them. Transfer via
AirDrop/USB/secure channel; **never commit them**:

| File | Needed for |
|---|---|
| `dev/.env` | Firebase client config (incl. `IOS_API_KEY` / `IOS_APP_ID`) |
| `ios/Runner/GoogleService-Info.plist` | iOS Firebase |
| `android/app/google-services.json` | only if also building Android on the Mac |

- Confirm `dev/.env` contains **`IOS_API_KEY`** and **`IOS_APP_ID`** —
  `firebase_options.dart`'s iOS block reads them.
- If `GoogleService-Info.plist` is lost: re-download from Firebase Console → the
  iOS app above (bundle `net.vogas.scheduling`).

## Phase C — Flutter + Pods

```bash
flutter pub get
flutter gen-l10n                                          # generated l10n is gitignored
dart run build_runner build --delete-conflicting-outputs # only if freezed models changed
flutter build ios --config-only                           # generates ios/Podfile on first run
cd ios && pod install                                     # first native install
```

`ios/Podfile` is **not committed** — the Flutter tool generates it on the
first iOS build. After it appears, edit it before `pod install`:

- Uncomment/set `platform :ios, '15.0'` (must match the 15.0 deployment
  target in `project.pbxproj` / `AppFrameworkInfo.plist`).
- `permission_handler` needs its macros in the `post_install` hook so only
  the used permissions compile in — inside `post_install do |installer|`,
  per target add:

  ```ruby
  target.build_configurations.each do |config|
    config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] ||= [
      '$(inherited)',
      'PERMISSION_CAMERA=1',
      'PERMISSION_PHOTOS=1',
    ]
  end
  ```

Then commit the resulting `Podfile` (and `Podfile.lock`).

## Phase D — Xcode config (the Mac-only GUI bits)

1. Open the **workspace**, not the project:
   ```bash
   open ios/Runner.xcworkspace
   ```
2. **Signing:** Runner target → *Signing & Capabilities* → select your Apple
   Developer **Team**. Bundle id is already `net.vogas.scheduling`.
3. **Add the Crashlytics Run Script phase** (not present yet): Runner target →
   *Build Phases* → `+` → *New Run Script Phase*, placed **after** the Flutter
   build phases.
   - **Script:**
     ```
     ${PODS_ROOT}/FirebaseCrashlytics/run
     ```
   - **Input Files:**
     ```
     ${DWARF_DSYM_FOLDER_PATH}/${DWARF_DSYM_FILE_NAME}/Contents/Resources/DWARF/${TARGET_NAME}
     $(SRCROOT)/$(BUILT_PRODUCTS_DIR)/$(INFOPLIST_PATH)
     ```
4. **dSYM build settings** (Runner target → *Build Settings*): *Debug
   Information Format* = `DWARF with dSYM File` for the Release
   configuration, so Crashlytics gets symbol files to upload.
5. **Verify** the deployment target shows **iOS 15.0** (set in
   `project.pbxproj` and `AppFrameworkInfo.plist`; keep the generated
   `Podfile` in sync — see Phase C).

## Phase E — App Check debug token

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

## Phase G — Before TestFlight / App Store (not for dev builds)

1. **Flip App Check back on** — in `functions/index.js`, the two `TODO(pre-ship)`
   lines (`enforceAppCheck: false` on `deleteAccount` and `resolveMyInvite`).
   Set both to `true`, then redeploy:
   ```bash
   cd functions && npm run lint
   firebase deploy --only functions
   ```
   ⚠️ This blocks sideloaded App Distribution testers — only do it for the store
   build.
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

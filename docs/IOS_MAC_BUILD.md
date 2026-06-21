# First iOS Build on a Mac — Set-by-Set

The config side of the iOS port is **done** (deployment target 15.0 in all three
places, committed `Podfile` with the permission-handler macros, `Info.plist` +
`PrivacyInfo.xcprivacy` in place). What's left is Mac-only: native tooling, the
two gitignored secret files, the Crashlytics build phase, and device
verification.

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
cd ios && pod install                                     # first native install
```

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
     ```
4. **Verify** the deployment target shows **iOS 15.0** (already set in `Podfile`,
   `project.pbxproj`, `AppFrameworkInfo.plist` — keep all three in sync).

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

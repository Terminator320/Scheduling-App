# iOS Release Checklist

This file lives at the repo root and tracks iOS-only work that is deferred until a Mac is available. Everything here is non-blocking for Android releases.

Grep for `TODO(ios)` in the codebase to find inline markers that should be addressed alongside the items below.

## Configuration (must run on Mac)

- [ ] Run `flutterfire configure` to populate iOS values in `lib/firebase_options.dart` and drop `ios/Runner/GoogleService-Info.plist`. After this, swap `DefaultFirebaseOptions.android` → `DefaultFirebaseOptions.currentPlatform` in `lib/main.dart`.
- [ ] First `pod install` will generate `ios/Podfile`. Set `platform :ios, '13.0'` (minimum supported by current Firebase iOS SDK).
- [ ] If `permission_handler` is ever added: in the generated `ios/Podfile` add a `post_install` hook setting `GCC_PREPROCESSOR_DEFINITIONS` with `PERMISSION_CAMERA=1`, `PERMISSION_PHOTOS=1`.
- [ ] Place `GoogleService-Info.plist` (downloaded by `flutterfire configure`) into `ios/Runner/`, then drag it into the Runner target in Xcode.
- [ ] Verify Firebase init order in `ios/Runner/AppDelegate.swift` — `FirebaseApp.configure()` must be called in `didFinishLaunchingWithOptions` before `GeneratedPluginRegistrant.register`.

## Privacy / App Store compliance

- [ ] Create `ios/Runner/PrivacyInfo.xcprivacy` (Apple requirement since May 2024). Declare:
  - `NSPrivacyAccessedAPITypes`: file timestamp APIs (used by image picker), user defaults (used by SharedPreferences), system boot time (used by Crashlytics).
  - `NSPrivacyCollectedDataTypes`: email address (auth), name (employee/client profiles), photos (appointment images), precise location only if the future Maps integration captures it.
  - `NSPrivacyTracking`: `false`.
  - Template reference: https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
- [ ] If any analytics SDK with cross-app tracking is ever added: present an App Tracking Transparency (ATT) prompt and add `NSUserTrackingUsageDescription` to `Info.plist`.
- [ ] If a third-party sign-in provider (Google, Facebook, etc.) is ever added: implement "Sign in with Apple" — Apple requires it whenever any other third-party provider is offered. Not required today since the app uses Firebase email/password only.

## Crashlytics + dSYM

- [ ] In Xcode, add a Run Script build phase with command `"${PODS_ROOT}/FirebaseCrashlytics/run"` and the following Input Files:
  - `$(DWARF_DSYM_FOLDER_PATH)/$(DWARF_DSYM_FILE_NAME)/Contents/Resources/DWARF/$(TARGET_NAME)`
  - `$(SRCROOT)/$(BUILT_PRODUCTS_DIR)/$(INFOPLIST_PATH)`
- [ ] Build Settings → Debug Information Format = `DWARF with dSYM file` for Release.
- [ ] Build Settings → Enable Bitcode = `NO` (Apple removed support in Xcode 14+).

## Project settings (Xcode)

- [ ] Set deployment target to 13.0 in project settings to match Podfile.
- [ ] Configure code signing — Apple Developer account, team ID, provisioning profiles, App Store Connect record.

## Verification on Mac

When all of the above are done:
- [ ] `flutter build ios --release` succeeds.
- [ ] TestFlight build distributed; trigger a test crash and verify dSYM symbolication appears in Firebase Crashlytics within ~10 minutes.

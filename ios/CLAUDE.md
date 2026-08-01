# iOS (ios/)

Loaded when working under `ios/`. Root context: `../CLAUDE.md`.

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
- **Deep-link tap URLs must keep the `homeWidget` query item.** The three iOS
  producers (`ScheduleWidget.swift`, `LiveActivitiesAppAttributes.swift`,
  `SiriIntents/ScheduleSnapshot.swift`) emit
  `esproschedule://appointment?id=…&homeWidget`; the `home_widget` plugin's
  `isWidgetUrl` claims a URL only when that query item is present, and nothing
  else consumes the scheme (`FlutterDeepLinkingEnabled` is `false` and
  `AppDelegate` has no `open url` override), so dropping the param silently
  turns taps into plain app launches (fixed 2026-07-29). Retire the param only
  together with the `home_widget` tap channel, when the P4b `app_links`
  dispatcher lands (docs/plans/2026-07-29-redesign-program.md). Swift-side, so
  Mac-only verification: widget row / Live Activity tap → appointment sheet.

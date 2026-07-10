# Codebase Audit — 2026-07-08 · App Store Readiness

Scope: whole repo (`lib/`, `functions/`, rules, `test/`) **plus** the release
surface prior audits never covered: `android/` + `ios/` build config, store
requirements, and the **live deployed Firebase state**.
Baseline: `moblie` @ `0d6e094` (v1.25.1+44). One uncommitted user change landed
mid-audit (`lib/main.dart`: `AppleDeviceCheckProvider` → `AppleAppAttestProvider`)
and is accounted for below.

## Verdict

**The code is ready. The release pipeline is not.** Zero bugs, zero code-side
security blockers, App Check enforcement and current rules verified live in
production. What stands between this repo and launch is process: iOS archive
tasks that need a Mac, App Check console config, and App Store Connect
paperwork.

> **Launch scope (decided 2026-07-08): App Store ONLY.** Android remains a
> dev/test target on this Windows box but is never published to Play. The
> `android/` folder and Android Firebase app stay — they are the local dev
> harness, not shipped surface. Play-specific findings below are re-marked
> **N/A (Play)** and only matter if a Play release is ever revisited.

## Summary

- **Scanned:** full static scan (`flutter analyze`, `dart fix --dry-run`,
  Functions ESLint — all clean), deep review of the delta since the 2026-07-07
  audit (`efac0d6..HEAD`, 19 files), security ship-gate pass over
  `functions/` + rules + manifests, Android/iOS store-config audit, and live
  probes of the deployed backend.
- **Auto-fixed (safe, in the diff): 1** — dead R8 keep rule for the removed
  `flutter_image_compress` package (`android/app/proguard-rules.pro`; package
  absent from `pubspec.lock`, rule provably inert). Also archived yesterday's
  report to `CODEBASE_AUDIT_2026-07-07.md`.
- **Reported for your decision:** ⚠️ 7 pre-ship actions · 🔴 2 security (both
  Low) · 🟠 0 bugs · 🔵 3 improvements.
- **Verification:** `flutter analyze` clean (errors/warnings: 0) · Functions
  ESLint pass · deployed functions + rules verified live (below). No Dart or
  Functions source was changed by this audit.

## Deployed-state verification (new this audit)

- **App Check enforcement is LIVE.** Every callable probed without tokens
  returns the platform-level `{"message":"Unauthenticated"}` 401 — the code
  path (`auth-required`) is never reached, which only happens with
  `enforceAppCheck: true` deployed. The 2026-07-07 memory note "flip not yet
  deployed" is now stale: **the deploy has happened.**
- **Firestore rules:** deployed copy is byte-identical to local
  `firestore.rules`.
- **Storage rules:** deployed copy matches local `storage.rules`.
- All 14 functions present in `us-central1` (validateUploadedImage in
  `us-east1`), nodejs24.

## Auto-applied cleanups (review the diff)

| File:line | Change | Why |
|---|---|---|
| `android/app/proguard-rules.pro:35-36` | Removed `-keep class com.fluttercandies.image_compress.**` | plugin removed from deps; rule inert |
| `docs/audits/` | `CODEBASE_AUDIT.md` → `CODEBASE_AUDIT_2026-07-07.md` | archive convention |

> Nothing below this line was auto-changed.

## ⚠️ Pre-ship checklist (act before release — App Store only)

- [ ] **1. Commit the App Attest provider swap.** `lib/main.dart:100`
  (`AppleAppAttestProvider`) is currently **uncommitted**; CLAUDE.md was updated
  to match. Commit it before cutting the store build.
- [ ] **2. Firebase Console App Check must match the code.** Enable
  **App Attest** for the iOS app (no `.p8`; that's DeviceCheck) and, on the Mac,
  add the App Attest capability/entitlement
  (`com.apple.developer.devicecheck.appattest-environment` = `production` for
  Release). Enforcement is already live server-side, so a store build with an
  unconfigured provider loses **all** callables. App Attest doesn't work on the
  Simulator — verify on real hardware. (Android dev builds are unaffected:
  `kDebugMode` uses `AndroidDebugProvider` with registered debug tokens.)
- [ ] **3. iOS archive tasks (BLOCKED — needs a Mac).** Add the Crashlytics
  dSYM upload Run Script phase — the project uses **Swift Package Manager**, so
  the script lives in the firebase-ios-sdk checkout (`upload-symbols`), *not*
  `${PODS_ROOT}/FirebaseCrashlytics/run`; set Release Debug Information Format
  to DWARF with dSYM; archive + upload. Signing itself is configured (team
  `H5XWLU87AX`, automatic, deployment target 15.0 — satisfies App Attest's 14+).
- [ ] **4. Carry `ios/GoogleService-Info.plist` to the Mac out-of-band.** It
  exists at the `ios/` root (where the Xcode project references it, and it IS in
  the Resources phase) but is gitignored — a fresh clone won't have it.
- [ ] **5. App Store Connect paperwork.** The **privacy questionnaire**
  (email/identifiers/crash data). `PrivacyInfo.xcprivacy` and
  `ITSAppUsesNonExemptEncryption=false` are already in the repo — those halves
  are done.

### N/A (Play) — parked unless a Play release is ever revisited

- **Android upload keystore / `key.properties`** — absent from disk;
  `android/app/build.gradle.kts:69-73` falls back to debug signing. Irrelevant
  while Android is dev-only (debug builds are exactly what dev uses).
- **Release `appbundle` R8 smoke test** — R8/minify only runs in Android
  release builds, which no longer ship.
- **Play Data Safety form** and **Play Integrity registration** (would need the
  Play app-signing SHA-256, which only exists after a Play upload).

## 🔴 Security findings (review required)

### S1 — Release build silently falls back to debug signing · severity: low (N/A while Play is off the table) · confidence: high
- **Where:** `android/app/build.gradle.kts:69-73`
- **Risk:** Process, not exploit: a fresh machine or CI produces a debug-signed
  "release" with no error; Play rejects it at upload (key mismatch), so the
  failure surfaces late and confusingly. With the Apple-only launch decision
  (2026-07-08) Android never builds for release, so this is dormant — recorded
  for a future Play revisit.
- **Fix (if ever needed):** Replace the fallback with
  `throw GradleException("key.properties missing — release builds require the upload keystore")`
  (optionally gated behind `-PallowDebugSigning` for local smoke builds).

### S2 — Transitive npm advisories in `functions/` · severity: low · confidence: high
- **Where:** `functions/package-lock.json` — `npm audit --omit=dev`: 1 High
  (form-data < 2.5.6, CRLF injection GHSA-hmw2-7cc7-3qxx) + 9 Moderate, all
  transitive under `firebase-admin`/`@google-cloud/*`.
- **Risk:** Minimal in this call graph — no first-party function builds
  multipart requests from user input — but a High advisory shouldn't ship
  un-triaged.
- **Fix:** `cd functions && npm audit fix` (non-breaking); the remaining uuid
  chain needs firebase-admin@14 — defer that breaking bump.

## 🟠 Bug findings

**None.** The full delta since the 2026-07-07 audit was reviewed line-by-line:
the 141-line `month_year_picker.dart` change is pure re-indentation
(`git diff -w` ≈ empty), removed tokens (`AppColors.disabled`,
`AppColors.darkDisabled`, `AppRadius.r4`, `AppDuration.slow`) have zero
remaining references, new tokens `r20`/`r24` exactly match the literals they
replaced, and the extracted Functions helpers (`isReauthStale`,
`hasValidImageMagic`) are logic-identical to the inline code they came from.
All 8 callables set `enforceAppCheck: true` with payload validation
(`assertPayloadShape`/`requireString`) and durable rate limits intact.

## 🔵 Areas to improve (review required)

### I1 — Doc drift: env keys and stale iOS notes · impact: low · confidence: high
- **Where:** `CLAUDE.md` "Required environment" (says 5 keys; code reads 7 —
  `IOS_API_KEY`, `IOS_APP_ID` added in `lib/firebase_options.dart:28-29`) and
  the iOS Phase-0 notes (a `Podfile` will never exist — the project uses Swift
  Package Manager with `firebase-ios-sdk 12.15.0` pinned; iOS Firebase options
  are already populated, so the "re-run flutterfire configure" step is done).
- **Suggested improvement:** Update the two CLAUDE.md passages so the Mac
  handoff doesn't chase steps that no longer exist.

### I2 — `pubspec.yaml:2` description is "Paul App" · impact: low · confidence: high
- Internal-only (not shipped to stores), but it's the last trace of the old
  name. One-line fix whenever convenient.

### I3 — No `<monochrome>` layer in the adaptive icon · impact: N/A (Play) · confidence: high
- **Where:** `android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml`
- Android 13+ themed icons render a grey default without it. Moot for an
  Apple-only launch; parked with the other Play items.

## Notes / uncertainties

- **Play Integrity / App Attest console registration state could not be
  verified from this box** — the Firebase Console App Check page must be checked
  by eye (pre-ship item 4). Everything else deploy-side was verified directly.
- The App Attest entitlement file isn't in the repo (no
  `Runner.entitlements`); adding the capability is a Mac/Xcode step (item 4).
- `dev/.env` was verified by key **names** only (all 7 present, none
  placeholder); contents were never read or printed.
- Store assets (screenshots, feature graphic, listing copy) weren't audited —
  console-side, out of repo scope.

## Ship-gate PASS list (verified, for the record)

versionCode/Name 44/1.25.1 from pubspec · minSdk 24 / target+compileSdk 36
(≥ Play's requirement) · minify+shrink+proguard on, Crashlytics mapping upload
wired · manifest: 4 justified permissions, `allowBackup=false`,
no cleartext/debuggable, single exported activity · adaptive + legacy icons ·
`ITSAppUsesNonExemptEncryption=false` · all four iOS usage descriptions ·
`PrivacyInfo.xcprivacy` tracked + in Resources phase · Xcode team/bundle id
real, deployment target 15.0 · Crashlytics Dart wiring
(`FlutterError.onError`, `PlatformDispatcher.onError`, zone) · l10n EN/FR
parity (`untranslated.json` = `{}`) · zero `TODO(pre-ship)`/`FIXME` in shipping
code · no secrets tracked in git (`dev/.env`, `google-services.json`,
`GoogleService-Info.plist`, keystores all ignored; plist has zero commits in
history) · rules default-deny with all documented clauses intact.

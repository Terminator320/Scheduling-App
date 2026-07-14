# App Store Submission Checklist — ES Pro

`net.vogas.scheduling` · team `H5XWLU87AX` · v1.25.1+44 · **App Store only**
Companion to `IOS_APP_STORE_HANDOFF.md` (full runbook) and
`docs/audits/CODEBASE_AUDIT.md` (readiness audit). Work top to bottom.

Legend: `[x]` done/verified · `[ ]` to do · ⚠️ blocker

---

## A. App Check / App Attest chain — ✅ COMPLETE
- [x] Code provider is `AppleAppAttestProvider` (`lib/main.dart:100`, committed).
- [x] App Attest capability added → `ios/Runner/Runner.entitlements` exists and
  is wired via `CODE_SIGN_ENTITLEMENTS` on all three configs.
- [x] Entitlement `com.apple.developer.devicecheck.appattest-environment` =
  **`production`** (was `development` — fixed).
- [x] Firebase Console → App Check → iOS app → **App Attest registered** (no
  `.p8`). Code + entitlement + console all agree.
- [x] Server-side enforcement verified live (every callable requires App Check).

## B. Crashlytics dSYMs — ✅ COMPLETE
- [x] "Crashlytics dSYM upload" run-script phase present, SwiftPM path,
  **last** build phase, dependency-analysis off, clean 5 Input Files.
- [x] Release + Profile `DEBUG_INFORMATION_FORMAT = dwarf-with-dsym`.
- [ ] After first upload: Crashlytics console shows **no "Missing dSYMs"**
  banner (proves the script ran). *(verify in step E)*

## C. Commit the config changes
- [ ] Commit uncommitted work: `Runner.entitlements`, `project.pbxproj`,
  `pubspec.yaml`, `CLAUDE.md`. (If Xcode is open, close/reopen first so it
  doesn't clobber the on-disk pbxproj/entitlements edits.)
- [ ] Push `moblie`.

## D. Clean build baseline (first store cut)
- [ ] `flutter clean && flutter pub get`
- [ ] Xcode → **Product → Clean Build Folder** (⇧⌘K)

## E. Verify on REAL hardware (App Attest fails on Simulator)
- [ ] `flutter run --release` on a physical iPhone.
- [ ] Sign in, then exercise a callable end-to-end to prove attestation:
  address autocomplete (`placesAutocomplete`) **or** Settings → Wave as admin
  (`waveGetConnection`). Success = App Attest working.
- [ ] Device-only sweep (never covered by tests): camera capture, photo-library
  picker, contacts save-flow, Face ID app-lock, map launch, phone/email launch.
- [ ] iPad pass (iPad is a shipped target): check split/master-detail layouts at
  tablet width.
- [ ] Flip device to **French**, spot-check both locales render.

## F. Archive + upload
- [ ] `flutter build ipa` (or Xcode → Product → Archive → Organizer).
- [ ] Upload via Organizer or Transporter.
- [ ] **TestFlight internal testing first** (store-signed → App Attest works).
  Do NOT use Firebase App Distribution for iOS (sideloads can't mint App Check
  tokens — blocked by design).
- [ ] Confirm Crashlytics console: no "Missing dSYMs" banner (closes B).
- [ ] Smoke-test the TestFlight build on device: sign in + one callable.

## G. App Store Connect — record & metadata
- [ ] App record: name **ES Pro**, bundle `net.vogas.scheduling`.
- [ ] **French metadata alongside English** (Quebec audience; app is bilingual).
- [ ] Screenshots: iPhone **6.9"** + **6.5"** sets **and** a **13" iPad** set.
- [x] Age-rating questionnaire completed (2026-07-11).
- [x] Support URL set in App Store Connect (2026-07-11) —
  `https://gvogas.github.io/es-pro-legal/support.html` (page live).

## H. App Store Connect — compliance (content blockers)
- [x] **Privacy policy authored + hosted (live 2026-07-11)** —
  `docs/legal/privacy-policy.html`, published at
  `https://gvogas.github.io/es-pro-legal/`, linked in-app via
  `AppUrls.privacyPolicy`.
- [x] Privacy Policy URL set in App Store Connect (2026-07-11) —
  `https://gvogas.github.io/es-pro-legal/`.
- [x] **Demo account for App Review created (2026-07-14).** Signup is
  invite-only (one-time codes), so Review can't self-register — a dedicated
  demo account exists. Still to do at submission: **paste its email + password
  into App Store Connect → App Review Information → Sign-In Required** (creds
  live there, NOT in the repo). Prefer a demo dataset over a real customer's
  data.
- [ ] ⚠️ **Privacy questionnaire — needs a Location update before submit.**
  Completed 2026-07-11, but **background GPS presence was added 2026-07-13**
  (`4d9f000`, `1e0828a`) — *after* the questionnaire — so the current
  declaration is missing Location. Add in App Store Connect → App Privacy:
  - **Location → Precise Location**, **Linked to the user** (stored per-uid at
    `users/{docId}/presence/location`), purpose **App Functionality**
    (travel-time "time to leave" reminders), **not** used for tracking.
  - The privacy *policy* webpage already covers this (section 2.4, updated
    2026-07-13); only the ASC questionnaire/nutrition label is stale.
  - `PrivacyInfo.xcprivacy` has an empty `NSPrivacyCollectedDataTypes` — left
    as-is on purpose (ASC questionnaire is authoritative; Firebase ships its own
    SDK manifests; required-reason APIs are declared). Not a rejection risk.
  Declaration as of 2026-07-11 (add Location to this):
  - Data Linked to You: Contact Info (Name, Phone, Email, Physical Address);
    Identifiers (Device ID = FCM push token, App Functionality, **not** tracking).
  - Data Not Linked to You: User Content (Photos); Diagnostics (Crash Data).
  - Tracking = No throughout (matches `NSPrivacyTracking = false`). Over-declared
    Usage Data/Product Interaction, Contacts, and Performance Data were removed —
    the app has no analytics/Performance SDK and only writes a contact card.
  - [x] Repo half done: `PrivacyInfo.xcprivacy` tracked;
    `ITSAppUsesNonExemptEncryption=false` (no export-compliance prompt).
  - [x] Privacy policy updated + re-hosted 2026-07-11 (push notifications + iOS
    widget); live at `https://gvogas.github.io/es-pro-legal/`.
- [x] **Account deletion** requirement satisfied (`deleteAccount` callable +
  in-app ACCT-DEL flow) — mention in Review notes if asked.

## I. Submit
- [ ] Attach the reviewed build, complete "App Review Information" (demo creds +
  notes), submit for review.

---

## Not blocking / parked
- **S2** — `functions/` transitive npm advisories (1 High, all transitive):
  `cd functions && npm audit fix` whenever convenient. Not shipped in the app.
- **N/A (Play)** — keystore, Data Safety, Play Integrity, monochrome icon,
  R8 smoke test. Android is dev-only; ignore unless a Play release is revisited.

# Audit follow-ups (manual / device-verified steps)

One item from the codebase audit can't be completed safely from a headless
environment — it needs GCP billing access. Written here ready to apply.

---

## 1. Bundle the Inter font (startup latency) — MOOT, superseded by P1

> **Superseded 2026-07-30.** This item was implemented 2026-07-02 (bundled
> static weights, `allowRuntimeFetching = false`), but P1's brand refresh
> (2026-07-30) dropped Inter and `google_fonts` entirely — neither the
> dependency nor `GoogleFonts.*` calls remain in `lib/` or `pubspec.yaml`.
> There is nothing left to device-verify; the plan below is kept only for
> history and must not be re-applied.

**Problem.** `lib/core/theme/themes.dart` uses `GoogleFonts.inter*`. With no
bundled copy, `google_fonts` fetches the Inter TTF from Google's CDN on first
launch before it can paint text — a network round trip on the cold-start path
(onboarding → splash → login). After the first fetch it's cached, so this only
hurts the very first run per install, but that's the run that matters most.

**Fix — bundle the static weights so there's no runtime fetch.**

1. Download the four static weights the theme uses (Regular 400, Medium 500,
   SemiBold 600, Bold 700). Source: the Inter release
   (https://github.com/rsms/inter/releases) → `Inter Desktop/` or the
   `extras/ttf/` folder, or Google Fonts' "Download family". You want real
   static instances named exactly:
   - `Inter-Regular.ttf`
   - `Inter-Medium.ttf`
   - `Inter-SemiBold.ttf`
   - `Inter-Bold.ttf`

2. Put them under `assets/fonts/` (create the folder).

3. Declare the family in `pubspec.yaml` under the existing `flutter:` key:

   ```yaml
   flutter:
     fonts:
       - family: Inter
         fonts:
           - asset: assets/fonts/Inter-Regular.ttf
             weight: 400
           - asset: assets/fonts/Inter-Medium.ttf
             weight: 500
           - asset: assets/fonts/Inter-SemiBold.ttf
             weight: 600
           - asset: assets/fonts/Inter-Bold.ttf
             weight: 700
   ```

4. Tell `google_fonts` to never hit the network — it will then resolve the
   bundled family by name. In `main()` (before `runApp`), add:

   ```dart
   import 'package:google_fonts/google_fonts.dart';
   // ...
   GoogleFonts.config.allowRuntimeFetching = false;
   ```

   `GoogleFonts.inter*` calls in `themes.dart` stay as-is; with fetching off and
   the family bundled, they load from the asset bundle.

5. **Verify on a device** (this is the part that can't be checked headlessly):
   `flutter run` on a *fresh* install with networking disabled — all text must
   render in Inter (not the platform default). If text falls back, the asset
   filenames/weights don't match what `google_fonts` expects; re-check step 1.

> Do **not** set `allowRuntimeFetching = false` without completing steps 1–3 —
> it would blank/fallback all app text.

---

## 2. Hard budget cap for Google Maps Platform (cost control)

**Problem.** The Places proxies (`placesAutocomplete`, `placesGetDetails` in
`functions/index.js`) cost real money per call. `placesGetDetails` now uses the
durable Firestore limiter, and `placesAutocomplete` keeps the per-uid in-memory
limiter (latency-sensitive, high volume). Neither is a *spend* ceiling — the
only true backstop is a GCP budget, and a plain budget **alert** just emails
you; it doesn't stop spend.

**Fix — a budget that programmatically disables billing (kill switch).** This
needs the billing-account ID and `roles/billing.admin`, so run it yourself.

1. Create a budget with a Pub/Sub topic for programmatic response:

   ```bash
   gcloud billing budgets create \
     --billing-account=BILLING_ACCOUNT_ID \
     --display-name="Maps Platform monthly cap" \
     --budget-amount=50USD \
     --filter-projects=projects/schedulingapp-88727 \
     --threshold-rule=percent=0.5 \
     --threshold-rule=percent=0.9 \
     --threshold-rule=percent=1.0 \
     --all-updates-rule-pubsub-topic=projects/schedulingapp-88727/topics/billing-alerts
   ```

2. Deploy the standard "cap disable" Cloud Function that listens on that topic
   and calls `cloudbilling.projects.updateBillingInfo` to detach billing when
   `costAmount >= budgetAmount`. See Google's reference:
   https://cloud.google.com/billing/docs/how-to/notify#cap_disable_billing_to_stop_usage

   (Detaching billing halts the project — appropriate for a runaway-cost
   emergency. If you'd rather throttle than halt, disable only the Maps APIs via
   `serviceusage.services.disable` instead.)

3. Set a sensible `--budget-amount` for expected Maps usage and confirm the
   `billing-alerts` Pub/Sub topic exists (`gcloud pubsub topics create
   billing-alerts`).

Until this is in place, the in-code limiters bound per-user abuse but not total
monthly spend.

---

## 3. Upgrade `flutter_contacts` 1.x → 2.x (device-verified)

> **✅ DONE.** `pubspec.yaml` now pins `flutter_contacts: ^2.2.2` and the 2.x API
> changes were reconciled in `contact_export_launcher.dart`. Step 2 (on-device
> verification of the four contact flows) remains the one device-only check, as
> with item 1. Original plan kept below for history.

**Problem.** `flutter_contacts` is pinned at `^1.1.9+2`; 2.x is current. The
plugin backs the save-to-contacts quick action and the client→phone-contact
edit-sync (`contact_export_launcher.dart`), both of which are **device-only
verifiable** per `.claude/rules/testing.md` (method-channel plugin, no unit
harness).

**Fix — upgrade with on-device verification.**

1. Bump `flutter_contacts: ^2.2.1` in `pubspec.yaml`, `flutter pub get`, and
   reconcile any 2.x API changes in `contact_export_launcher.dart`
   (`insertContact`, `getContact(withAccounts:)`, `updateContact`,
   `openExternalInsert`) and the `clientToContact` mapper.
2. On a real device, verify all four flows: save with permission granted
   (contact appears + link persists), save with permission declined (OS insert
   screen opens), edit-sync updates the linked contact without erasing its
   photo/account, and a deleted contact unlinks cleanly on the next sync.

---

## 4. Redesign invited-employee signup — `resolveMyInvite` deploy blocker

> **✅ DONE (2026-06-27).** Implemented as the one-time signup-code redesign — but
> NOT the "defer to first verified sign-in" sketch below. Instead: an admin-only
> `createEmployeeInvite` callable issues a per-invite code; `redeemSignupCode`
> validates it server-side and activates the account immediately (no email
> verification). `resolveMyInvite` was deleted, so the deploy blocker is gone.
> See `docs/archive/INVITED_SIGNUP_REDESIGN.md` (design) and
> `docs/archive/INVITED_SIGNUP_REDESIGN_PLAN.md` (implementation). The original sketch is
> kept below for history.

**Problem (DEPLOY BLOCKER).** The audit security fix made `resolveMyInvite`
(`functions/account.js`) return `{found:false}` whenever
`req.auth.token.email_verified !== true`, so an unverified caller can't learn
whether an invite exists or read its name/color/role. But `createEmployeeAccount`
(`lib/features/auth/services/auth_service.dart`) calls
`findInvitedEmployeeForCurrentUser()` → `resolveMyInvite` **immediately after
`register()`, before the email is verified**, to decide whether to send the
verification email or roll the account back. Once the updated functions deploy,
every invited-employee signup resolves to `null` → rollback →
`AuthFailureNotAuthorized`: **signup is fully broken**. It is not broken in
production today only because the functions aren't deployed yet.

The strict `email_verified` gate is intentional and **stays**. The signup flow
must stop depending on a pre-verification invite lookup. **Do not deploy the
`functions` target until this redesign lands** — deploying alone breaks signup.

**Redesign (defer to a follow-up branch).** Move invite resolution out of the
pre-verification path:

1. `createEmployeeAccount` keeps `register()` (and the `email-already-in-use`
   adopt path), but **stops calling `findInvitedEmployeeForCurrentUser()`**.
   Send `user.sendEmailVerification()` unconditionally, sign out, and return —
   the UI tells the user to check their email. No pre-check, no invite-based
   rollback (we can't know invite status pre-verification).
2. Resolve + activate (or clean up) entirely at first post-verification sign-in.
   `tryActivateInvitedEmployee` already gates on `emailVerified` and forces a
   fresh token, so on a verified token it calls `resolveMyInvite` and:
   - invite found → `activateEmployee` (as today);
   - invite **not** found → non-invited / wrong-email account: sign out and
     surface "not authorized"; optionally `user.delete()` the orphan (the caller
     is freshly signed in, so recent-login is satisfied).

**Consequences to handle in the redesign:**
- Anyone can now create an *unverified* Auth account for any email (no pre-gate).
  The orphan is harmless (no `users` doc → `SplashScreen`/login signs them out)
  but squats the email until cleaned up. Clean it at the first verified
  sign-in's "no invite" branch; for users who verify but never sign in the
  orphan persists — accept it, or add a scheduled unverified-orphan cleanup.
- The `email-already-in-use` → adopt → `findUserByUid` orphan-recovery path
  still applies for a verified-but-unprovisioned adopted account.
- Tests: `auth_service_test.dart` currently mocks
  `findInvitedEmployeeForCurrentUser` inside the `createEmployeeAccount` cases;
  after the redesign that expectation moves to the `tryActivateInvitedEmployee`
  path.
- Update the **CLAUDE.md "Employee activation flow" invariant** to describe the
  new flow (verification sent unconditionally at signup; invite resolution +
  cleanup at first verified sign-in).

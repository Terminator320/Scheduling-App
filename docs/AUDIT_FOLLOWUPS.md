# Audit follow-ups (manual / device-verified steps)

Two items from the codebase audit can't be completed safely from a headless
environment — one needs font binaries + on-device rendering verification, the
other needs GCP billing access. Both are written here ready to apply.

---

## 1. Bundle the Inter font (startup latency)

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

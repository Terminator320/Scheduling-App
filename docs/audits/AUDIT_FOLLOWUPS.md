# Audit follow-ups (manual / device-verified steps)

**One item is still open: §2, the Maps Platform budget cap.** It needs GCP
billing access, so it can't be completed from a headless environment; it is
written below ready to apply.

Items 1, 3 and 4 are closed and were compressed to a line each on 2026-08-15 —
their step-by-step plans described code that no longer exists, which made this
file read as three-quarters outstanding work. Where a superseded flow still has
historical value the record is in `docs/archive/`, not here.

---

## 1. Bundle the Inter font (startup latency) — MOOT

**Closed 2026-07-30, and unrepeatable.** It was implemented 2026-07-02 (bundled
static weights, `allowRuntimeFetching = false`), then P1's brand refresh dropped
Inter and `google_fonts` outright — neither the dependency nor any `GoogleFonts.*`
call remains in `lib/` or `pubspec.yaml`. There is nothing to device-verify and
nothing to re-apply.

---

## 2. Hard budget cap for Google Maps Platform (cost control)

**Problem.** The Places proxies (`placesAutocomplete`, `placesGetDetails` — they
live in `functions/places.js`; `index.js` only re-exports them) cost real money
per call. `placesGetDetails` now uses the
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

## 3. Upgrade `flutter_contacts` 1.x → 2.x — DONE

**Closed.** `pubspec.yaml` pins `flutter_contacts: ^2.2.2` and the 2.x API
changes were reconciled in `contact_export_launcher.dart`. One device-only check
is left over, as for every method-channel plugin here: on real hardware, verify
the four contact flows — save with permission granted (contact appears and the
link persists), save with permission declined (the OS insert screen opens),
edit-sync updating a linked contact without erasing its photo/account, and a
deleted contact unlinking cleanly on the next sync.

---

## 4. Redesign invited-employee signup — MOOT twice over

**Closed 2026-06-27, then closed again.** The `resolveMyInvite` deploy blocker
was resolved by the one-time signup-code redesign (not by the "defer to first
verified sign-in" sketch this item originally proposed), and `resolveMyInvite`
was deleted. That signup-code flow was itself replaced by P4c's admin-provisioned
accounts on 2026-08-02 and removed from the backend on 2026-08-08 with the
`#compat-1.37.1` shim — `createEmployeeInvite`, `redeemSignupCode`, `invites.js`
and the `signupCodes` rules block are all gone. Nothing in the original sketch
describes code that exists.

The historical record is `docs/archive/INVITED_SIGNUP_REDESIGN.md` and
`_PLAN.md`; the current flow is in `CLAUDE.md` and
`docs/plans/redesign-subdocs/2026-08-02-p4c-HANDOFF.md`.

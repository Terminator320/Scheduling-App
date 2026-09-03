# Audit follow-ups (manual / owner-only)

Everything that could be closed from the audit review has been removed from this
rolling follow-up list. The only remaining item needs GCP billing access.

## Hard budget cap for Google Maps Platform (cost control)

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

# `docs/CLOUD_FUNCTIONS.md` — refresh history before 2026-09-01

Trimmed out of the header of `docs/CLOUD_FUNCTIONS.md` on 2026-09-06, where the
stacked "Previously refreshed ..." block had reached nine entries. The four most
recent stayed there; these six are the older ones, frozen as written. They cover
2026-08-19 through 2026-08-29, across which the export list sat at 25.

Previously refreshed 2026-08-29 (release 1.54.0+83 — **the export list is unchanged at 25
and no row below moved**. The one server-side change is the retirement of
`createEmployeeAccount`'s `#compat-1.47.0` carve-out: `isAdmin` is out of the
`assertPayloadShape` allowlist and is now refused as `unexpected-field`. It was
deployed on its own on 2026-08-29 — a `functions`-only deploy, because retiring
a compat key is a backend change and cannot ride along with the app build that
stopped sending the field. The rest of the release is Flutter-only: the
calendar's holiday markers compute in Dart and reach no function, rule or
index. See `createEmployeeAccount` below for the full reasoning.)
Previously refreshed 2026-08-28 (release 1.53.0+82 — **the export list is unchanged at 25
and no row below moved**, but two behaviour changes here matter: the client
`jobCount` recount is now DEBOUNCED through the shared `recount_claim.js`
ledger and GATED on `mayShareABatch`, because a per-day run lands up to 16
writes carrying one `clientId`; and `client_address_utils.js` is a new pure
module owning `streetFromAddress`, which moved out of `wave/mappers.js` now
that `client_propagation.js` and the address backfill read it too. A
`firestore.rules` change rides with them — see the deployment-status note
below, it is NOT a ride-along deploy).
Previously refreshed 2026-08-25 (the 2026-08-25 audit — **no export, trigger, schedule,
secret or guard changed, and no row below moved**: the edits were dead-code
removal (`isOvernightRecord`, `TOKEN_TTL_MS`/`activityTokenExpiry`,
`IMPORT_FIELD_CAPS`'s export), the `{enforceAppCheck: true}` block lifted into
`security.js` as the shared `APP_CHECK` that `clients.js` and
`employee_accounts.js` now spread, and new jest coverage for `assertAdmin` —
the gate on 8 of 14 callables, which had been `jest.mock`'d in every suite, so
its real predicate had never once executed. Export list unchanged at 25).
Previously refreshed 2026-08-22 (the photo-subcollection CONTRACT step: `pictures[]`
retired, `appointment_image_tokens.js` and its deactivation-time token rotation
DELETED, `cascadeDeleteAppointmentImages` now deleting the Storage bytes as
well as the photo documents, the legacy `url` retired on a prod count of zero,
and `generateStartingPassword` given the symbol class that had account creation
down — export list unchanged at 25). Previously refreshed 2026-08-21
(simplified auth: `completeEmployeeSetup` lost its
`email_verified` guard and `createEmployeeAccount` stopped reading a role,
keeping `isAdmin` only as an accepted-and-ignored compatibility key — export
list unchanged at 25). Previously refreshed 2026-08-19 by auditing the source
against the app's call sites and
the live deployment (the iOS Live Activity stack added behind
`notifyAppointmentChanges` / `sendUpcomingJobReminders` — APNs secrets, direct
HTTP/2 client; `purgeExpiredHistory`'s timeout corrected to the 1800s scheduled
-trigger max; `sendUpcomingJobReminders` previously rebuilt into the
travel-aware "time to leave" sweep — `travel_utils.js`, Routes API,
`GOOGLE_MAP_API_KEY` shared via `params.js`).

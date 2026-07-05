# Wave Accounting Integration — Implementation Plan

> Status: **Design / pre-implementation.** The **Connect + Customers** scope
> (§§0–13) is grounded in Wave's **official developer docs** — auth, the GraphQL
> transport + variables rules, pagination, and the `customerCreate` /
> `customerPatch` / get-customer / Customer-schema shapes are all confirmed.
> `phone`/`mobile` on create is **assumed accepted** (with a `customerPatch` fallback
> if not). A few residual **[VERIFY]** items remain (the published-app OAuth reading,
> the archive mutation, an archived list-filter) — confirm each before coding.
> **Appendix A (invoicing)**
> is less settled and keeps its own **[VERIFY]**s.
>
> **Scope of this plan: Connect + Customers only.** Invoicing and invoice-status
> sync are a **later phase** — their design is parked in **Appendix A** (bottom of
> this doc) so it isn't lost, but nothing in §§0–13 builds it. The first milestone
> is small: authenticate to one Wave business and two-way-sync customers.

---

## 0. Read this first — the finding that changes the spec

### Single business → **no OAuth at all**

The app is one company's internal tool (`net.vogas.scheduling`). Its "clients" are
that company's customers. You connect **one** Wave account — the owner's — so the
backend authenticates with a single **Full Access Token** stored server-side, used
for every Wave call. There is **no OAuth, no per-user login, no token refresh, no
`state`, and no redirect URI**. (OAuth would only ever matter if the app became a
multi-tenant SaaS where many separate businesses link their own Wave books —
explicitly out of scope.)

> **App Store distribution does NOT require OAuth.** Wave's OAuth requirement is
> triggered by *whose Wave account the app touches* — not by where the app is
> distributed or how many people use it. The relevant Wave rule is "published or
> sold **for other Wave users to access *their* accounts**." Here, every Wave call
> hits **your one** account via a server-side token; your users never connect a
> Wave account (they sign in with Firebase, not Wave). So this stays a
> "personal/own-business application" even as a published App Store app. The **only**
> thing that flips it to OAuth: selling this to *other companies* who each link
> their *own* Wave books. (Apple doesn't require Wave OAuth either — App Store
> Review enforces Apple's sign-in rules, and "Sign in with Apple" only applies if
> you add a third-party *social login* like "Sign in with Wave", which you don't.)

> **[VERIFY — highest-stakes assumption.]** Wave's own pages are inconsistent
> here: the **Authentication** page states flatly that a Full Access Token is
> "strictly recommended for development purposes or personal applications only,
> and for any applications that will be **published or sold**, authentication must
> be via OAuth 2," while the **OAuth Guide** carries the narrower "for other Wave
> users to access *their* accounts" qualifier this plan relies on. The own-business
> reading is defensible and commonly used, but confirm it **in writing with Wave
> developer support** before committing to no-OAuth — the whole auth design (§6)
> rests on it. The risk is already contained structurally: all auth sits behind
> `getWaveToken()`, so a forced move to OAuth would be a localized swap, not a
> rewrite.

---

## 1. Verified Wave API facts (the spec to build against)

| Item | Value |
|---|---|
| GraphQL endpoint | `POST https://gql.waveapps.com/graphql/public` — JSON body `{ query, variables }` (`query` required, `variables` optional) + `Authorization: Bearer <token>` |
| Auth (this app) | **Full Access Token** (own business) sent as `Authorization: Bearer <token>` — no OAuth, no refresh, no redirect URI |
| Rate limits | ~**60 req/min per token**, ~**5,000 req/day per app** — design around this |
| Everything is scoped to a `businessId` | A token can expose **multiple** businesses — **select** the intended one at bootstrap, then cache its id (never blindly take the first) |
| Pagination | **limit/offset**: `page` (1-based) + `pageSize`; request `pageInfo{ currentPage totalPages totalCount }` and loop while `currentPage < totalPages` |
| Wave Pro | **Not required** for customer sync (only gates published OAuth apps; webhooks/invoicing — Appendix A — may differ) |

**Core mutations used by this scope** (shapes **confirmed from Wave docs**):
- `customerCreate(input: CustomerCreateInput!)` → `{ didSucceed, inputErrors{ code message path }, customer{ id name firstName lastName email address{…} currency{ code } } }` — input requires `businessId` + `name`.
- `customerPatch(input: CustomerPatchInput!)` → same result shape; input is `{ id, <only the fields to change> }` — **`id` only, no `businessId`**.

Invoicing/payment mutations (`invoiceCreate`, `productCreate`, `invoiceApprove`,
`moneyTransactionCreate`, …) and the webhook contract belong to the deferred
invoice phase — see **Appendix A**.

**Customer fields.** *Output* (query) object: `id` (the global Node id — **use this,
not the deprecated `internalId`**), `name` (required — name or business name),
`firstName`, `lastName`, `email`, `mobile`, `phone`, `fax`, `tollFree`, `website`,
`displayId` (user-defined "Account Number"), `currency{ code name symbol }`,
`internalNotes`, `isArchived`, `createdAt`/`modifiedAt`, `outstandingAmount`/
`overdueAmount` (`Money!`), `address{ addressLine1, addressLine2, city,
province{ code name }, country{ code name }, postalCode }`, `shippingDetails`.
**The *input* differs — don't mirror the output shape:**
`CustomerCreateInput`/`CustomerPatchInput` take **flat strings** `address.provinceCode`
(ISO-3166-2, e.g. `CA-QC`), `address.countryCode` (ISO-2, e.g. `CA`), and a top-level
`currency` string code (e.g. `CAD`) — not the nested `{ code name }` objects the query
returns. **There is no multi-contact concept and no per-customer tax field.**

Sources reviewed: Wave Developer Portal — Authentication / OAuth Guide, API
Reference, Building on GraphQL + Variables + Pagination guides, the Customer schema
reference, the `customerCreate` / `customerPatch` / get-customer / list-customers
operations, and the Webhooks Setup Guide — plus Wave Community and the Knit /
Apideck integration guides.

---

## 2. Recommended architecture

```
Flutter app  ──(callable, App Check)──►  Cloud Functions  ──(GraphQL + Bearer token)──►  Wave
   │                                          │
   │  watches Firestore (sync state, ids)     │  writes back ids/sync state
   ▼                                          ▼
                       Cloud Firestore
```

- **Flutter** never sees a Wave secret and never calls Wave directly. It calls
  **callables** and **watches Firestore** for results (matches the existing
  Places-proxy + Secret-Manager pattern in `functions/index.js`).
- **Cloud Functions** own every Wave call (authenticated with the Full Access
  Token) and retries. Region `us-central1`, project `schedulingapp-88727`.
- **Firestore** is the system of record for the *app's* view of customers; after
  the seed import, the app re-syncs one-way (App → Wave). (Authority split in §11.)
- **Async, not inline.** A client save must not block on Wave. Writes to Wave go
  through an **outbox** (`waveSyncQueue` doc + a worker) so a slow/failed Wave call
  never fails the user's action and is retried with backoff (§9).

This mirrors conventions already in the repo: secrets via `defineSecret`,
callables guarded by `assertPayloadShape` → typed validation → durable rate
limit, App Check enforcement, service classes for all Firestore writes, typed
`Failure` families surfaced via the notice service.

> Inbound Wave→App eventing (the HMAC webhook) arrives with the invoice phase
> (**Appendix A**); customer sync is one-way out and needs no webhook.

---

## 3. Firebase data model (Firestore)

Add Wave fields to existing docs rather than parallel collections.

### `clients/{clientId}` (reshaped — Wave-aligned, see §7)
`ClientRecord` gains Wave-aligned fields so every Wave customer field the app uses
maps to exactly one `ClientRecord` field **in both directions** (direct 1:1 —
`name`, `firstName`, `lastName` are three separate fields, mirroring Wave). Wave
fields the app doesn't map (`fax`, `tollFree`, `website`, `displayId`,
`internalNotes`, `currency`, `shippingDetails`) are **preserved untouched** —
`customerPatch` only updates the fields it's sent — so a customer round-trips
losslessly even though the app doesn't store those fields. **Firestore is the read
layer** — the app never reads clients from Wave; Wave is touched only on the seed
import and on write-back.
```jsonc
{
  "waveCustomerId": "string|null",   // link to Wave; null = app-only, not yet pushed
  "name": "string",                  // = Wave `name` (the customer/display name, required)
  "firstName": "string", "lastName": "string",   // = Wave firstName/lastName (separate fields)
  "email": "string", "phone": "string", "mobile": "string",   // mobile NEW
  "address": "string",               // single combined line = Wave addressLine1
  "city": "string", "province": "string",              // province = 2-letter (QC),
  "country": "string", "postalCode": "string",         // country = name (Canada); mapper ↔ Wave
  "contacts": [ /* app-only — Wave has no multi-contact */ ],
  "noFixedAddress": false,           // app-only
  "wave": {
    "syncState": "synced|pending|error",
    "syncError": "string|null",
    "lastSyncedAt": "timestamp|null",
    "lastSyncedHash": "string"       // hash of mapped fields; skip no-op patches
  }
}
```
> `waveCustomerId` is a **top-level** field (was `wave.customerId`) so lookups/queries
> stay simple; the `wave` sub-map keeps only sync bookkeeping.

### `wave/connection` (single doc — bootstrap metadata)
Holds **non-secret** metadata only. The token lives in Secret Manager
(`WAVE_FULL_ACCESS_TOKEN`), never here.
```jsonc
{ "businessId": "string", "businessName": "string",
  "bootstrappedAt": "timestamp" }
```
> The invoice phase (**Appendix A**) adds `serviceProductId` + `webhookId` here.

### `waveSyncQueue/{jobId}` (outbox — see §9)
```jsonc
{ "type": "customerUpsert", "refPath": "clients/abc",
  "payloadHash": "string", "attempts": 0, "nextAttemptAt": "timestamp",
  "status": "queued|inflight|done|dead", "lastError": "string|null",
  "idempotencyKey": "string" }
```

### `rateLimits/wave__<route>` — reuse the existing durable limiter.

`firestore.rules`: admins edit a customer's normal fields on `clients/{id}`, but
the `wave.*` bookkeeping **and** `waveCustomerId` are function-owned (written via
the Admin SDK, which bypasses rules) — so the client-update rule must **exclude
them** with a `request.resource.data.diff(resource.data).affectedKeys()` check,
exactly like the existing employee `status→'done'` rule. Everything else is **fully
client-denied** (`allow read, write: if false`, like `rateLimits`): `wave/*` (the
connection doc) and `waveSyncQueue/*`. No client can read or reset sync state.

---

## 4. Firestore schema vs. the brief's tables

The brief's flat `Customers/Jobs/Invoices` tables map onto existing collections —
**do not create parallel collections**, you'll fork the source of truth:

| Brief | This app |
|---|---|
| `Customers.waveCustomerId` | `clients/{id}.waveCustomerId` |
| `Jobs` / `Invoices.*` | `appointments/{id}` (+ a `wave.*` block) — **invoice phase, Appendix A** |

---

## 5. Cloud Function structure (`functions/index.js`)

New secret (Secret Manager, like `GOOGLE_MAP_API_KEY`): `WAVE_FULL_ACCESS_TOKEN`.
That's all for this scope — no client id/secret (no OAuth), and no
`WAVE_WEBHOOK_SECRET` yet (that arrives with the invoice webhook, Appendix A).

```
functions/
  index.js
  wave/
    auth.js         // getWaveToken() → reads WAVE_FULL_ACCESS_TOKEN
    client.js       // graphql(query, vars): fetch + Bearer; ALL args via vars (never inline); 429/5xx retry
    mappers.js      // client <-> Wave customer (single-line address, province/country codes, §7)
    customers.js    // upsertCustomer(clientId), importCustomers()
    worker.js       // outbox processor (Cloud Tasks or Firestore-trigger + backoff)
```

Exposed functions:

| Function | Type | Guards |
|---|---|---|
| `waveBootstrap` | callable (admin) **or** lazy on first call | App Check, auth, isAdmin → **idempotent get-or-create** of `wave/connection` (caches `businessId`; safe under concurrent first calls) |
| `waveImportCustomers` | callable (admin) | App Check, auth, isAdmin, durable rate limit |
| `waveUpsertCustomer` | Firestore trigger on `clients/{id}` write → enqueue outbox | server-side; **skips writes that touch only `wave.*` / `waveCustomerId`** (no self-trigger from the worker's write-back or the import) |
| `waveSyncWorker` | Cloud Tasks / scheduled | drains `waveSyncQueue` with backoff |

Every callable keeps the repo's pattern: `assertPayloadShape(req.data, allowed)`
→ typed field validation → `enforceDurableRateLimit('wave-<route>', uid, …)` →
work. **Flip `enforceAppCheck` to `true` before ship** (track with the existing
`TODO(pre-ship)` marker).

> The invoice phase (**Appendix A**) adds `invoices.js`, `webhook.js`, and the
> `waveOnJobDone` / `waveCreateInvoice` / `waveWebhook` functions, and extends
> `waveBootstrap` to also create the "Service" product and register the webhook.

---

## 6. Authentication — Full Access Token (no OAuth)

**One business → one Full Access Token on the backend. No OAuth anywhere.**

1. Create the Wave developer application (`developer-apps.waveapps.com/apps/`) and
   copy the **Full Access Token** from its page.
2. Store it in Secret Manager as `WAVE_FULL_ACCESS_TOKEN` (exactly like
   `GOOGLE_MAP_API_KEY`). Never in Flutter; never in a client-readable Firestore
   field.
3. `getWaveToken()` returns `WAVE_FULL_ACCESS_TOKEN.value().trim()`; every GraphQL
   call sends it as `Authorization: Bearer <token>`. **No authorize URL, no
   callback, no refresh, no `state`, no redirect URI, no deep-link return.**
4. First-use bootstrap (lazy, server-side): confirm the token with the cheap
   `query { user { id defaultEmail } }` whoami (fast fail → `WaveAuthInvalid` if
   revoked), then list businesses (`{ businesses{ edges{ node{ id name } } } }`).
   **A token can expose several businesses** (the docs' example returns `Personal`
   + `Smith Consulting`), so **select the intended one** — pass its name/id to
   `waveBootstrap` (or set it in config) and match it in the list; never blindly
   take the first edge. Persist the chosen `businessId` + `businessName` to the
   single `wave/connection` doc. (The invoice phase extends bootstrap to also create
   the "Service" product and register the webhook — Appendix A.)

The token doesn't expire on a clock the way an OAuth access token does. The only
maintenance: if it's ever revoked/rotated in the Wave portal, update the Secret
Manager value.

> **Reminder — "many app users" does not change this.** Every Wave call runs
> server-side under the one business token; individual employees/admins never sign
> into Wave. OAuth would matter only if the app became a multi-tenant SaaS (many
> separate businesses each linking their own Wave books) — out of scope. Keep all
> auth behind the single `getWaveToken()` helper so that hypothetical swap stays a
> one-file change.

---

## 7. Customer synchronization flow

**Clients live in Firestore (the read layer) — the app never reads clients from
Wave.** Wave is touched only twice: a **one-time bulk import** that seeds Firestore
from all Wave customers, and **write-back** (App → Wave) when a client is
created/edited. After the seed the app is authoritative for clients. Do **not**
subscribe to `customer.*` webhooks — that creates echo loops (your own write
bounces back).

### Field mapping (`mappers.js`) — bidirectional, now that the model is Wave-aligned
| ClientRecord (reshaped) | Wave customer |
|---|---|
| `name` | `name` (required — the customer/display name) |
| `firstName` / `lastName` | `firstName` / `lastName` (direct, separate fields) |
| `email` | `email` |
| `phone` / `mobile` | `phone` / `mobile` — **sent on `customerCreate`** (assumed accepted). Confirmed real, patchable fields (the get-customer query reads them back); the create doc's optional-field list omits them, so **if `customerCreate` rejects them, fall back to a follow-up `customerPatch`** right after create — same end state, two calls. |
| `address` (single combined line) | `address.addressLine1` (`addressLine2` empty — see below) |
| `city` | `address.city` |
| `province` (2-letter, e.g. `QC`) | input `address.provinceCode` — mapper **prepends `CA-`** → `CA-QC` (confirmed: Wave wants ISO-3166-2). On import, strip `CA-` from the returned `province.code` to store `QC`. |
| `country` (name, e.g. `Canada`) | input `address.countryCode` — mapper converts name → ISO-2 (`CA`). On import, map the returned `country.code`/`name` back to the stored name. |
| `postalCode` | `address.postalCode` |
| `contacts[]` | **app-only** — Wave has no multi-contact; not synced |
| `noFixedAddress` | **app-only** — not synced |
| tax | **unsupported on customer** — tax is applied per invoice line in Wave, by the user |

> Wave's `internalNotes` and `currency` are intentionally **not synced** (you don't
> need them) — leave them unset on create; Wave defaults a customer's currency to
> the business currency. Ignore both on import.

> **Single-line address — send the stored value as-is.** The app stores apt+street
> as one combined `-` line (e.g. `12-3450 Main St`) and only reformats it for
> *display*. Send the **stored** value to Wave verbatim — never the display form:
> ```
> addressLine1 = apt.isNotEmpty ? "${apt}-${address}" : address   // stored "-" form, unmodified
> ```
> Leave `addressLine2` empty; don't split apt out. (On import, Wave → App, fold the
> customer's `addressLine1` — **plus `addressLine2` if Wave has one**, joined as
> `"line1, line2"` — into the single `address`, so a Wave-entered second line isn't
> lost. App-created customers have an empty line2, so they round-trip byte-identical.)

> **Province/country — mapper converts, no form change.** The autofill already
> stores province as a 2-letter code (`QC`, via the Places `shortText` in
> `google_places_repository.dart`) and country as a name (`Canada`); both stay as-is.
> Wave's docs confirm the **input** wants ISO-3166-2 (`provinceCode: "CA-QC"`,
> `countryCode: "CA"`), so the `mappers.js` normalizer converts: **export**
> `QC`→`CA-QC` and `Canada`→`CA`; **import** strips `CA-` from `province.code` back to
> `QC` and maps `country` back to the stored name. The autocomplete, parser, and
> forms don't change.

### Create / update (App → Wave)
On client create or edit, enqueue `customerUpsert`. Worker (**hash-first**, in a
transaction):
1. **Already linked?** If `clients/{id}.waveCustomerId` is set, recompute the
   mapped-field hash; if it equals `wave.lastSyncedHash` → **no-op** (this is what
   absorbs the worker's own write-back and the import's writes without echoing to
   Wave, and what makes an unchanged edit free). If set but changed → `customerPatch`.
2. Else `customerCreate`. On `didSucceed`, write back `waveCustomerId`,
   `wave.syncState:'synced'`, `wave.lastSyncedHash`.
3. `didSucceed:false` → map `inputErrors` **by code** to a localized `WaveFailure`
   (never Wave's raw message), set `wave.syncState:'error'`, surface a notice.

> **No email-match dedup.** Because all new customers are created **through the app**
> (never directly in Wave) and the seed is a total wipe, no out-of-band Wave twin can
> exist to collide with — so there's no `waveCustomerIndex` and no email lookup. The
> only guard is **per-doc**: the `waveCustomerId` set on first create (in the
> transaction) means a given client doc creates exactly one Wave customer, even under
> double-tap/retry. (Two *separate* app client docs for the same person would map to
> two Wave customers — a data-entry matter, not a sync one.)

### Delete (App → Wave) — **don't hard-delete in Wave** (decided)
Wave is the financial system of record, and `customerDelete` (which exists) is
typically **blocked once a customer has invoices** (it will, after the invoice
phase). So an admin deleting a client in the app **removes only the local Firestore
doc; the Wave customer is left intact**. Optional tidy-up: **archive** it in Wave
instead (the customer carries an `isArchived` flag — **[VERIFY the archive mutation:
`customerPatch` vs. a dedicated one]**); never hard-`customerDelete` a customer that
may carry history. (A later re-import re-creates the local doc, since the customer
still exists in Wave — acceptable for a manual one-shot import.)

### Initial bulk import (seed)
`waveImportCustomers` uses Wave's **limit/offset pagination** — `page` (1-based) +
`pageSize` — requesting `pageInfo{ currentPage totalPages totalCount }` and looping
**while `currentPage < totalPages`**:
`query { business(id){ customers(page,pageSize,sort:[NAME_ASC]){ pageInfo{ currentPage totalPages totalCount } edges{ node{ id name firstName lastName email phone mobile isArchived address{ addressLine1 addressLine2 city province{ code } country{ code } postalCode } } } } } }`
Use **`pageSize: 100`** (drop to 50 if Wave rejects it — the exact cap is unknown but
non-blocking): the current book has **~650 customers → ~7 pages / ~7 requests**, far
under the 60/min limit, and the `currentPage < totalPages` loop adapts to whatever the
real cap and count are. Pass an explicit **`sort: [NAME_ASC]`** for deterministic
page order (offset paging is only stable under a fixed sort; Wave also offers
`MODIFIED_AT_DESC` etc. — the enabler for a *future* incremental delta re-sync, out
of scope here since customers are app-authoritative after the seed). It **upserts
every *active* Wave customer into Firestore** — **skip `isArchived` customers** (the
read layer mirrors active ones; **[VERIFY a list-query archived filter, else drop
them client-side]**) — in `WriteBatch`es of ≤500 (~650 ⇒ 2 batches), keyed by
`waveCustomerId`, writing
`wave.syncState:'synced'` + the mapped-field `lastSyncedHash` on each doc (so the
`waveUpsertCustomer` trigger no-ops and nothing echoes straight back to Wave). This
is the **seed** that
populates the app's read layer; it's idempotent on `waveCustomerId`, so re-running it
is safe (offset paging can skip/dupe only under concurrent mutation — a non-issue for
a one-shot admin seed, and a dupe just re-upserts). Admin-triggered, one-shot — not a
live stream.

**One-time migration ("clear → reshape → import") — confirmed.** Before launch the
app's `clients` **and** `appointments` (both **test data only** — nothing imported
from or pushed to Wave yet) are **cleared**, then clients are **seeded from Wave** —
no preservation, no merge, no risk. Because the wipe is total **and all new
customers are created through the app** (never directly in Wave), the seed needs no
merge/dedup and there's **no `waveCustomerIndex` at all** — every client is either
seeded (already linked) or app-created (linked on first push). (Clearing appointments
too avoids leaving them pointing at client doc-ids that no longer exist.) The model reshape
(§3) still ripples through `client_record.dart` (+ freezed regen),
`client_form_validator.dart`, the add/edit client forms (now first-name / last-name
/ customer-name fields), the client detail view, **`contact_export_launcher.dart`'s
`clientToContact` mapper** (so the new `firstName` / `lastName` / `mobile` reach
phone contacts), and their tests — land it as one change and keep `flutter analyze`
at zero.

---

## 8. Flutter service layer

No Wave SDK in Flutter — thin callable wrappers + Firestore watchers, in the
repo's manual-Riverpod + service-class style.

> **No GraphQL client in Flutter (no `graphql_flutter` / `graphql` / `gql`).**
> Wave's API is GraphQL, but Flutter never speaks it: every GraphQL call lives in
> Cloud Functions (§5 `wave/client.js`), and the app only calls App-Check-enforced
> **callables** and **watches Firestore** for results. Pointing `graphql_flutter`
> at Wave from the app would require shipping the Full Access Token in the client —
> the one thing §12 / `security.md` forbid — and pointing it at a Functions-hosted
> GraphQL gateway would duplicate the callable transport every other function
> already uses, for no gain. The server's `client.js` is a plain `fetch` POST +
> Bearer header (matching `placesAutocomplete`); if a Node GraphQL client is ever
> wanted there, it's `graphql-request` (Node) — **not** `graphql_flutter`, which is
> a Dart/Flutter package and can't run in the Node.js functions runtime anyway.

```dart
// lib/features/wave/data/wave_service.dart
class WaveService {
  WaveService({FirebaseFunctions? functions, AppLogger? logger})
      : _functions = functions ?? FirebaseFunctions.instanceFor(region: 'us-central1'),
        _logger = logger ?? AppLogger();

  // No OAuth screen — admin just triggers the one-time bootstrap.
  Future<WaveConnection> bootstrap() async {           // admin
    final res = await _call('waveBootstrap', {});
    return WaveConnection.fromMap((res as Map?)?.cast<String, dynamic>() ?? {});
  }

  Future<void> importCustomers() => _call('waveImportCustomers', {});

  Future<Object?> _call(String name, Map<String, dynamic> data) async {
    try {
      final r = await _functions.httpsCallable(name).call(data);
      return r.data;
    } on FirebaseFunctionsException catch (e, st) {
      _logger.warn('WAVE-$name ${e.code}', e, st);     // tag → Crashlytics
      throw WaveErrorMapper.map(e);                     // typed WaveFailure
    }
  }
}
```

Customer **sync state** is read by **watching Firestore** (the `wave.*`
projection), never by polling Wave — the functions keep Firestore current. New
providers are hand-written top-level finals (no `@riverpod`), per the repo
convention.

UI touchpoints (no connect/login screen — the token lives server-side): an admin
**Sync with Wave** / **Import customers** action in Settings, and a Wave-customer
indicator on the client form. (The invoice status chip + "Open invoice in Wave"
action arrive with **Appendix A**.)

---

## 9. Error handling & retry strategy

Typed family `WaveFailure` (sealed, `implements Exception`) at
`lib/features/wave/domain/wave_failure.dart`, mirroring `AuthFailure`:
`WaveAuthInvalid` (token missing/revoked), `WaveRateLimited`,
`WaveValidation(inputErrors)`, `WaveNetwork`, `WaveUnknown`. Surface via
`noticeServiceProvider.error(failure.toLocalizedMessage(context))` with new
`error_intro*` l10n keys (EN + FR in lockstep). Catch-site tags: **`WAVE-BOOT`,
`WAVE-CUST`** (so a screenshot maps to a Crashlytics line, per `error-handling.md`;
the invoice phase adds `WAVE-INV` / `WAVE-HOOK`).

Server-side handling:

| Failure | Handling |
|---|---|
| 401 / invalid token | Token missing or revoked in Wave → `WaveAuthInvalid`; alert the admin to update `WAVE_FULL_ACCESS_TOKEN` in Secret Manager. Not retryable. |
| 429 / rate limit | Exponential backoff with jitter in the worker; never retry inline on the user's tap |
| 5xx / network | Backoff + retry in the worker; cap attempts, then **dead-letter** (`status:'dead'`) + alert |
| `didSucceed:false` (`inputErrors`) | **Do not retry** (deterministic) — map `inputErrors` **by code** to a localized `WaveValidation` (not Wave's raw message), set `syncState:'error'`, surface the field error |
| Duplicate | Per-doc guard: the `waveCustomerId` set in the create transaction ⇒ later syncs patch, never re-create (handles double-tap/retry). No email-match needed (§7). |

**Outbox + worker** (`waveSyncQueue` + `waveSyncWorker`) is what makes this
robust: user actions write to Firestore and enqueue; the worker drains with
backoff. A Wave outage degrades to "customer sync pending," never a failed client
save. Best-effort, never-block semantics match the existing image-cleanup rule.

---

## 10. API request examples

```bash
# Envelope: POST JSON { query, variables } + Bearer token. Cheapest call —
# verify the token works ("whoami"):
curl -X POST https://gql.waveapps.com/graphql/public \
  -H "Authorization: Bearer $WAVE_FULL_ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{ "query": "query { user { id defaultEmail } }", "variables": {} }'

# Then fetch the business id (cached at bootstrap):
curl -X POST https://gql.waveapps.com/graphql/public \
  -H "Authorization: Bearer $WAVE_FULL_ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{ "query": "{ businesses(page:1,pageSize:10){ edges{ node{ id name } } } }", "variables": {} }'
```
```graphql
mutation CreateCustomer($input: CustomerCreateInput!) {
  customerCreate(input: $input) {
    didSucceed
    inputErrors { code message path }
    customer {
      id name firstName lastName email
      address { addressLine1 addressLine2 city
        province { code name } country { code name } postalCode }
      currency { code }
    }
  }
}
# variables — the INPUT uses flat codes (provinceCode/countryCode/currency),
# NOT the nested { code name } objects the query above returns:
# { "input": { "businessId": "<id>", "name": "Acme Co",
#   "firstName": "Jane", "lastName": "Doe", "email": "jane@acme.com",
#   "phone": "555-0100",   // assumed accepted on create; if Wave rejects, set via a follow-up customerPatch
#   "address": { "addressLine1": "12-3450 Main St",  // combined apt+street, line2 empty
#     "city": "Montreal", "provinceCode": "CA-QC",   // ISO-3166-2 (app stores "QC")
#     "countryCode": "CA", "postalCode": "H2X 1Y4" },
#   "currency": "CAD" } }   // optional — the app omits this (see §7); Wave defaults to the business currency
```

> **Pass every argument as a GraphQL variable (the `$` map), not inline — two
> reasons.** (1) **Best practice:** plain GraphQL *does* allow inline scalar/string
> literals (`hero(episode: JEDI)`), but
> [graphql.org](https://graphql.org/learn/queries/#variables) says to avoid
> hand-built query strings and pass a separate `vars` map so the client never
> manually escapes values — declared variables must be Scalar / Enum / **Input
> Object** types (so `CustomerCreateInput` rides in as `$input`). (2) **Wave
> additionally *requires* it:** Wave rejects `String`-typed args inline (only `ID`
> may be inline). Building each request from a `vars` map satisfies both and keeps
> `client.js` injection-safe — client / customer data never becomes query text.

Run an **introspection** query first to lock exact input types:
```graphql
{ __type(name:"CustomerCreateInput"){ inputFields{ name type{ name kind ofType{ name } } } } }
```

---

## 11. Synchronization rules & conflict resolution

| Event | Direction | Authority / loop guard |
|---|---|---|
| Bulk import (seed) | Wave → App (Firestore) | One-time full import populates the Firestore read layer; keyed on `waveCustomerId` |
| Customer created | App → Wave | App authoritative after seed; per-doc idempotency (`waveCustomerId` guard) — the app is the only creator, so no email-match needed |
| Customer updated | App → Wave | Hash-diff no-op; **no `customer.*` webhook** (no echo loop) |
| Customer deleted (app) | App → **no Wave delete** | Drop the local doc only; **leave the Wave customer intact** (financial SoR; `customerDelete` is blocked once invoices exist). Optionally archive (`isArchived`) instead. |

Rule of thumb: **clients live in Firestore (the read layer) — never read from
Wave.** After the one-time seed import, **customers = app-authoritative (one-way
out)**. This eliminates bidirectional conflict on any single field. (Invoice
authority — Wave-owned status/payment — is covered in **Appendix A**.)

---

## 12. Security considerations

- **No Wave secret in Flutter — ever.** The Full Access Token lives server-side
  only (Secret Manager). Matches `security.md`.
- **All Wave calls are backend-only**; Flutter calls App-Check-enforced callables.
  Flip `enforceAppCheck:true` before ship (the repo's `TODO(pre-ship)` pattern).
- **GraphQL-injection-safe by construction:** every Wave call passes its arguments
  as GraphQL **variables** (the `$` map), never string-interpolated into the query —
  which Wave also *requires* for `String`-typed args (only `ID` may be inline). So
  client / customer data never becomes executable query text.
- **Durable rate limiting** on Wave callables via the existing
  `enforceDurableRateLimit` (lighter caps for import). Respect Wave's 60/min — the
  worker paces calls.
- **Treat the Full Access Token as a high-value secret** — it grants full access
  to the business's books. Limit who can read the secret; if leaked, revoke/rotate
  it in the Wave portal and update the Secret Manager value.
- **Firestore rules** deny client writes to every `wave.*` projection; clients
  read only their own viewable docs' projection. Fully client-deny `waveSyncQueue`
  and `wave/connection`.
- **No PII/secret logging** — log Wave **ids and tags**, never tokens, full
  payloads, or customer PII (per `security.md`).
- Run the repo's `vibe-security` pass on the new functions before merge.

> The invoice phase (**Appendix A**) adds mandatory **webhook signature
> verification** (HMAC-SHA256 over the raw body, 5-min replay window, constant-time
> compare) and the `WAVE_WEBHOOK_SECRET`.

---

## 13. Deployment checklist

- [ ] Create the Wave developer application; copy the **Full Access Token**.
- [ ] Store `WAVE_FULL_ACCESS_TOKEN` in Secret Manager; grant the functions runtime
      access. (No client id/secret, no redirect URI — there's no OAuth.)
- [ ] Ship `firestore.rules` denying client access to `wave.*` / `waveSyncQueue` /
      `wave/connection`; add composite index(es) if any new queries need them.
- [ ] `cd functions && npm run lint` (Google ESLint, 80-char) before deploy.
- [ ] `firebase deploy --only functions,firestore:rules,firestore:indexes`.
- [ ] Run `waveBootstrap` once (admin); verify `wave/connection` has the **correct**
      business id (a token may expose several) + name.
- [ ] Register App Check debug token if testing on sideloaded builds; flip
      `enforceAppCheck:true` for production.
- [ ] Set a **GCP billing alert** (Wave is free, but guard the functions/egress).

## Testing checklist

- [ ] Unit: `mappers.js` (client ↔ Wave customer, **both directions**) — pure,
      table-driven, incl. province `QC`↔`CA-QC`, country name↔ISO-2, and the
      single-line address join (with `addressLine2` fold-in on import).
- [ ] Unit: idempotency — `customerUpsert` twice for one client doc → one Wave
      customer (`waveCustomerId` guard); `waveUpsertCustomer` no-ops on a
      `wave.*`-only write-back (no echo).
- [ ] Integration (Wave **sandbox/test business**): create customer; bulk-import
      (skips `isArchived`); edit a client → `customerPatch` reflected in Wave **and
      unsent fields (e.g. `fax`) preserved**; delete a client → local doc gone, Wave
      customer **untouched**.
- [ ] Error paths: `inputErrors` (no retry), 429 (backoff), invalid token →
      `WaveAuthInvalid`.
- [ ] Flutter widget: admin Sync/Import action; Wave-customer indicator on the
      client form. Reuse the repo's l10n + secure-storage test harness; keep
      `flutter analyze` at zero.

## Production-readiness checklist

- [ ] `WAVE_FULL_ACCESS_TOKEN` in Secret Manager; `waveBootstrap` authenticates to
      Wave and populates `wave/connection`.
- [ ] Bulk import seeds the Firestore read layer; re-running is idempotent.
- [ ] Idempotency proven for customer creation (`waveCustomerId` per-doc guard).
- [ ] Rate-limit pacing verified against 60/min without 429 storms.
- [ ] `enforceAppCheck:true`; all `TODO(pre-ship)` markers cleared.
- [ ] All `[VERIFY]` items confirmed against live introspection.
- [ ] CHANGELOG + version bump (MINOR — new feature) per the repo's versioning rule.

---

## Phasing (recommended build order)

1. **Connect (Full Access Token)** — put `WAVE_FULL_ACCESS_TOKEN` in Secret
   Manager; lazy bootstrap fetches/caches `businessId`. No OAuth.
2. **Clients** — reshape `ClientRecord` to the Wave-aligned model (§3); **bulk-import
   all Wave customers** to seed the Firestore read layer; then app→Wave upsert for
   new/edited clients (linked by `waveCustomerId`; outbox + retry).

**Later phases — see Appendix A:**
- **Invoices (customer + date)** — on Finish Job, create a DRAFT invoice with
  customerId + invoiceDate + a $0 placeholder line; write-back ids/url; "Open in
  Wave" action.
- **Status sync** — webhook ingestion → Firestore (`invoiceStatus`, amounts).

**Future / further out:**
- **App-side itemization** — a billing/line-item model + auto-populated line items
  (only if you stop finishing invoices by hand in Wave).
- **Automated payment capture** via `moneyTransactionCreate` (record payment in
  Wave; status flows back by webhook).
- **Multi-tenant + OAuth** — only if you sell the app to other companies so each
  links its own Wave books. Keep auth behind `getWaveToken()` to localize the swap.

---

## Appendix A — Invoicing & status sync (deferred, later phase)

> Parked here intact so the design survives — **nothing in §§0–13 builds it.** When
> you pick this up, re-confirm every **[VERIFY]** against live introspection and
> settle the items below first.

### Decisions & open risks to settle first
- **Webhooks may need Pro + OAuth.** Several third-party integration guides state
  Wave's **invoice webhooks require a Pro business and OAuth scopes**, and that
  webhook URLs are registered in the **business portal** (not via the token at
  bootstrap). If so, the Full-Access-Token + non-Pro model can't receive events —
  **fall back to a low-frequency polling reconcile** (re-query open invoices in
  `waveSyncWorker`, respecting the 60/min limit) as the *primary* status-sync
  mechanism. Confirm at bootstrap.
- **The app stores no money.** `AppointmentRecord` has no amounts, rates, line
  items, taxes, or totals (`materialsNeeded` is free text; employees carry a color,
  not a rate). So the app pre-fills **customer + date only** and the user finishes
  line items / amounts / tax in Wave. (Scope decision 2026-06-13.)
- **Wave has no "receipt" object.** Wave exposes **invoices**, not sales receipts;
  the paid-invoice PDF *is* the receipt. "Generate a receipt" = create invoice →
  approve → record a payment (`moneyTransactionCreate`, double-entry — out of scope;
  record payment in Wave by hand). The Full-Access-Token path itself needs no Pro.

### Extra Wave facts / mutations
- Webhooks: `x-wave-signature: t=<ts>,v1=<sig>`, HMAC-SHA256 over `"<ts>.<raw-body>"`,
  5-min replay window, **verify against the raw body — never re-serialized JSON**.
- `invoiceCreate(input: InvoiceCreateInput!)` → `{ didSucceed, inputErrors{...}, invoice{ id invoiceNumber pdfUrl viewUrl status } }`
- `productCreate(input: ProductCreateInput!)` → called **once** at bootstrap for the generic "Service" product (line items require a `productId`).
- Available but not used (the user approves/sends/taxes/records payment in Wave): `invoiceApprove`, `invoiceSend`, `salesTaxCreate` / `business.salesTaxes`, `moneyTransactionCreate`.
- Business must be on **new invoicing** (`isClassicInvoicing: false`) — `invoiceCreate` rejects classic-invoicing businesses. **[VERIFY at bootstrap]**
- The **customer** object exposes `overdueAmount` / `outstandingAmount` (`{ raw value }`) — a per-customer balance that could power a "customer owes $X" badge here (rides along with the existing customer read; no extra query). A single customer reads via `business(id){ customer(id){ … } }` (ID-typed vars) for reconciliation; the app's read layer is otherwise Firestore.

### Extra data model
`appointments/{appointmentId}` gains a `wave.*` block (the "job" ↔ invoice link):
```jsonc
{
  // ...existing AppointmentRecord fields...
  "wave": {
    "invoiceId": "string|null", "invoiceNumber": "string|null",
    "invoiceUrl": "string|null",        // viewUrl — "Open invoice in Wave"
    "invoicePdfUrl": "string|null",
    "invoiceStatus": "DRAFT|UNSENT|SENT|VIEWED|PARTIAL|PAID|OVERDUE|null",
    "amountDue": 0, "amountPaid": 0,    // populated by webhook once user fills it in
    "syncState": "pending|created|error", "syncError": "string|null",
    "createdInWaveAt": "timestamp|null"
  }
}
```
- `wave/connection` gains `serviceProductId` (the generic "Service" product for the
  placeholder line) and `webhookId`.
- `waveSyncQueue.type` gains `invoiceCreate`.
- **No `wave/catalog` collection** — the user itemizes + taxes in Wave, so the app
  caches no labor/material/discount products and no tax ids beyond the single
  `serviceProductId`. **[VERIFY whether `invoiceCreate` accepts an empty `items`
  array; if so, drop the placeholder line and `serviceProductId` entirely.]**

### Extra functions
- `invoices.js` — `createDraftInvoice(appointmentId)`: customerId + date + placeholder.
- `webhook.js` — verify signature, route `invoice.*` → Firestore.
- `waveOnJobDone` — Firestore trigger on `appointments/{id}` (status → `done`) →
  enqueue `invoiceCreate`, **idempotent on `appointmentId`** (covers admin **and**
  the employee `status:'done'` finish paths server-side; a double-tap can't create
  two invoices).
- `waveCreateInvoice` — callable (admin): manual create / retry only, same
  `appointmentId` idempotency key.
- `waveWebhook` — HTTPS: HMAC verify, 5-min window, idempotent.
- `waveBootstrap` extends to create the "Service" product and register the webhook;
  adds the `WAVE_WEBHOOK_SECRET`.

### Invoice creation flow ("Finish Job") — customer + date only
**Preconditions:** the customer exists in Wave (the invoice takes a `customerId`;
Wave renders the linked customer's **name and address** on the invoice — so the §7
customer sync is what populates both, and the app sets no name/address on the
invoice itself). One generic "Service" product exists. Business on new invoicing.

**Trigger:** appointment `status` → `done` fires `waveOnJobDone` server-side →
enqueue `invoiceCreate` keyed by `appointmentId`. (`waveCreateInvoice` is only a
manual create/retry for admins.)

**Mutation:**
```graphql
mutation CreateInvoice($input: InvoiceCreateInput!) {
  invoiceCreate(input: $input) {
    didSucceed
    inputErrors { code message path }
    invoice { id invoiceNumber pdfUrl viewUrl status }
  }
}
```
```jsonc
// variables — only customer + date carry app data; the line is a placeholder
{ "input": {
  "businessId": "<cached>",
  "customerId": "<clients/{id}.waveCustomerId>",   // → pre-fills the customer name + address
  "status": "DRAFT",                                 // user finishes it in Wave
  "invoiceDate": "2026-06-13",                        // appointment completion date
  "items": [
    { "productId": "<connection.serviceProductId>",  // $0 placeholder to satisfy
      "quantity": 1, "unitPrice": 0,                 // the non-empty items rule
      "description": "To be completed" }
  ]
} }
```
The placeholder line is harmless: the user overwrites its description/price or
deletes it and adds real lines when finishing the draft. (Optional: set `poNumber`
to the appointment number for a reference on the draft.)

**After create:** `didSucceed:true` → write `wave.invoiceId / invoiceNumber /
invoiceUrl (viewUrl) / invoicePdfUrl / invoiceStatus:'DRAFT'` back to the
appointment; surface **"Open invoice in Wave"** (the `viewUrl`) on the appointment
detail view. `didSucceed:false` → `WaveValidation`, `wave.syncState:'error'`,
notice (tag `WAVE-INV`). Date formatted `yyyy-MM-dd` in the business timezone.

### Invoice status sync (Wave → App)
Webhook `waveWebhook` (HTTPS):
1. Read `x-wave-signature: t=<ts>,v1=<sig>`. Reject if `|now - ts| > 5 min`.
2. Recompute `HMAC_SHA256(WAVE_WEBHOOK_SECRET, "<ts>.<RAW body>")`; compare in
   constant time. **Use the raw, unparsed body** — re-serialized JSON fails.
3. On `invoice.update` / `invoice.*`, fetch the invoice id from the payload, look
   up the `appointments` doc by `wave.invoiceId`, and update `wave.invoiceStatus`,
   `amountDue`, `amountPaid`. **Idempotent** (last-write-wins; ignore stale
   `modifiedAt`).
4. Subscribe to invoice events only (register during bootstrap). **Not** customer
   events.

Fallback (or primary, if webhooks need Pro/OAuth — see open risks): a low-frequency
reconcile in `waveSyncWorker` re-queries open invoices, respecting rate limits.

### Invoice synchronization rules
| Event | Direction | Authority / loop guard |
|---|---|---|
| Job finished | App → Wave invoice | Idempotent on `appointmentId`; transaction guards double-create |
| Invoice created | App → Firestore | Function writes back ids/status |
| Invoice status / payment | Wave → App | **Wave is authority**; webhook updates Firestore; app never overwrites Wave status |

The app only *creates* the invoice (customer + date + placeholder); from then on
Wave owns the line items, status, and payment, and the webhook is the **only**
writer of `wave.invoiceStatus` / `amountDue` / `amountPaid`.

### Invoice phase — extra checklist items (fold into §13 when built)
- [ ] Generic "Service" product created and id stored on `wave/connection`;
      business confirmed on **new invoicing** (`isClassicInvoicing:false`).
- [ ] `WAVE_WEBHOOK_SECRET` in Secret Manager; webhook live and signature-verified;
      status round-trips end-to-end (or polling reconcile wired if webhooks need Pro).
- [ ] Customer-exists guarantee before invoice (every billed client has a `waveCustomerId`).
- [ ] Unit: invoice input builder (customerId + invoiceDate + $0 placeholder; date
      `yyyy-MM-dd` in business tz); webhook signature verify (valid / tampered body
      / stale timestamp); idempotency — `invoiceCreate` twice for one `appointmentId`
      → one invoice.
- [ ] Flutter widget: invoice status chip + "Open in Wave" link.

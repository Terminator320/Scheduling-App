"use strict";

/**
 * @fileoverview Syncs Firestore `clients` docs with Wave Accounting customers.
 * `upsertCustomer` pushes App → Wave with a hash-gated create/patch, and
 * `importCustomers` does a one-time Wave → App seed, idempotent on
 * `waveCustomerId`. No Wave network call ever runs inside a Firestore
 * transaction. Transport failures surface as `WaveApiError`, a validation
 * rejection throws `WaveValidationError`, and this module never logs
 * customer PII, tokens, or Wave's raw error text.
 * @module wave/customers
 */

const {toWaveCustomerInput, mappedFieldsHash, fromWaveCustomer} =
  require("./mappers");
// Safe at module scope: `client.js` requires only `./auth`, lazily, so this
// closes no cycle. `retry_policy.js` and `errors.js` both already require this
// module AND that one.
const {WaveApiError} = require("./client");

// ---------------------------------------------------------------------------
// WaveValidationError
// ---------------------------------------------------------------------------

/**
 * Thrown when a Wave customer mutation returns `didSucceed:false` — a
 * deterministic, non-retryable failure the outbox worker dead-letters rather
 * than retries.
 */
class WaveValidationError extends Error {
  /**
   * @param {!Array<{code:string, message:string, path:(Array<string>|string)}>}
   *   inputErrors The `inputErrors` array returned by the Wave mutation.
   * @param {string=} message Optional sanitized summary message.
   */
  constructor(inputErrors, message) {
    super(message || sanitizeInputErrors(inputErrors));
    this.name = "WaveValidationError";
    /**
     * @type {!Array<{code:string, message:string,
     *   path:(Array<string>|string)}>}
     */
    this.inputErrors = Array.isArray(inputErrors) ? inputErrors : [];
    /** @const {boolean} Always non-retryable. */
    this.retryable = false;
  }
}

// ---------------------------------------------------------------------------
// GraphQL documents
// ---------------------------------------------------------------------------

// Shared customer selection set (plan §10). Currency is read back for
// display only — we never write it on input.
const CUSTOMER_FIELDS = `
  id
  name
  firstName
  lastName
  email
  address {
    addressLine1
    addressLine2
    city
    province { code name }
    country { code name }
    postalCode
  }
  currency { code }
`;

const CREATE_CUSTOMER = `
mutation CreateCustomer($input: CustomerCreateInput!) {
  customerCreate(input: $input) {
    didSucceed
    inputErrors { code message path }
    customer { ${CUSTOMER_FIELDS} }
  }
}`;

const PATCH_CUSTOMER = `
mutation PatchCustomer($input: CustomerPatchInput!) {
  customerPatch(input: $input) {
    didSucceed
    inputErrors { code message path }
    customer { ${CUSTOMER_FIELDS} }
  }
}`;

// One owner for the listing's page + node selection, so the full and delta
// documents below can't drift on what they read back.
const LIST_CUSTOMERS_BODY = `
      pageInfo { currentPage totalPages totalCount }
      edges {
        node {
          id
          name
          firstName
          lastName
          email
          phone
          mobile
          isArchived
          address {
            addressLine1
            addressLine2
            city
            province { code }
            country { code name }
            postalCode
          }
        }
      }`;

const LIST_CUSTOMERS = `
query ListCustomers($id: ID!, $page: Int!, $pageSize: Int!) {
  business(id: $id) {
    customers(page: $page, pageSize: $pageSize, sort: [NAME_ASC]) {${
  LIST_CUSTOMERS_BODY}
    }
  }
}`;

// Delta listing. `modifiedAtAfter` filters SERVER-SIDE, so Wave returns only
// what changed — strictly better than paging everything and stopping early.
// Confirmed against the live schema 2026-08-04 (see
// scripts/wave-introspect-customer-sort.js).
//
// This is a SEPARATE document rather than one query with a nullable `$since`:
// omitting a variable to make an argument "not present" is real GraphQL, but
// it is subtle third-party behaviour, and a server that instead read it as
// `modifiedAtAfter: null` would silently return nothing — a full import that
// imports zero customers and reports success. Two documents make that
// unrepresentable.
//
// Sort stays NAME_ASC: we page the entire filtered set either way, so
// MODIFIED_AT_ASC would buy nothing and gives the two documents a second
// difference to keep in step.
const LIST_CUSTOMERS_SINCE = `
query ListCustomersSince(
  $id: ID!, $page: Int!, $pageSize: Int!, $since: DateTime!
) {
  business(id: $id) {
    customers(
      page: $page, pageSize: $pageSize, sort: [NAME_ASC]
      modifiedAtAfter: $since
    ) {${LIST_CUSTOMERS_BODY}
    }
  }
}`;

// ---------------------------------------------------------------------------
// Error sanitization
// ---------------------------------------------------------------------------

// Maps Wave inputError codes to safe, app-owned messages — Wave's raw
// `message` is never surfaced verbatim.
const ERROR_CODE_MESSAGES = {
  "GENERIC_ERROR": "Wave rejected the customer data.",
  "MISSING_REQUIRED": "A required customer field is missing.",
  "NOT_FOUND": "The customer no longer exists in Wave.",
  "TOO_LONG": "A customer field is too long for Wave.",
  "TOO_SHORT": "A customer field is too short for Wave.",
  "INVALID_EMAIL": "The customer email address is not valid.",
  "INVALID_PHONE": "The customer phone number is not valid.",
};

/**
 * Builds a single sanitized message from a Wave `inputErrors` array, mapping
 * by `code` only (never Wave's raw `message`).
 * @param {Array<{code:string}>} inputErrors Wave input errors.
 * @return {string}
 */
function sanitizeInputErrors(inputErrors) {
  const errs = Array.isArray(inputErrors) ? inputErrors : [];
  const messages = [];
  for (const e of errs) {
    const code = e && typeof e.code === "string" ? e.code : "";
    const mapped = ERROR_CODE_MESSAGES[code];
    if (mapped && !messages.includes(mapped)) messages.push(mapped);
  }
  if (messages.length === 0) return "Wave rejected the customer data.";
  return messages.join(" ");
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

/**
 * Lazily requires `firebase-admin/firestore` so tests that inject `db`/`now`
 * never trigger it.
 * @return {{getFirestore: !Function, FieldValue: !Object}}
 */
function adminFirestore() {
  // eslint-disable-next-line global-require
  return require("firebase-admin/firestore");
}

/**
 * Reads the connected Wave `businessId` from the `wave/connection` doc.
 * @param {!Object} db Firestore instance.
 * @return {!Promise<string>} The business id.
 * @throws {Error} When the connection doc or its businessId is missing.
 */
async function readBusinessId(db) {
  const snap = await db.collection("wave").doc("connection").get();
  const data = snap && snap.exists ? snap.data() : null;
  const id = data && typeof data.businessId === "string" ? data.businessId : "";
  if (!id) {
    throw new Error("wave/connection businessId is missing — not connected.");
  }
  return id;
}

/**
 * Returns true when a Wave inputError path (an array of segments or a dotted
 * string) points at the `phone` or `mobile` field.
 * @param {{path:(Array<string>|string)}} err A single input error.
 * @return {boolean}
 */
function isPhoneFieldError(err) {
  if (!err) return false;
  const path = err.path;
  const segments = Array.isArray(path) ?
    path :
    (typeof path === "string" ? path.split(".") : []);
  return segments.some((s) => s === "phone" || s === "mobile");
}

/**
 * True when every input error in the array targets a phone/mobile field,
 * meaning a create-without-phone retry is worth attempting. An empty array
 * is false.
 * @param {Array<Object>} inputErrors Wave input errors.
 * @return {boolean}
 */
function allPhoneFieldErrors(inputErrors) {
  const errs = Array.isArray(inputErrors) ? inputErrors : [];
  return errs.length > 0 && errs.every(isPhoneFieldError);
}

/**
 * Normalizes a Wave mutation payload (the value under `customerCreate` /
 * `customerPatch`) to `{didSucceed, inputErrors, customer}`.
 * @param {Object} payload Raw mutation payload from `data`.
 * @return {{didSucceed:boolean, inputErrors:!Array, customer:Object}}
 */
function readMutationPayload(payload) {
  const p = payload || {};
  return {
    didSucceed: p.didSucceed === true,
    inputErrors: Array.isArray(p.inputErrors) ? p.inputErrors : [],
    customer: p.customer || null,
  };
}

/**
 * Whether a thrown patch error means the customer this doc is LINKED to no
 * longer exists in Wave.
 *
 * Wave reports a missing `customerPatch` target as a **top-level** GraphQL
 * error, not an `inputErrors` entry, so it arrives as `WaveApiError('graphql')`
 * — which the retry taxonomy correctly calls non-retryable and dead-letters.
 * Correct for a bad payload; wrong for this, because the offending value is
 * STORED: every later push re-sends the same missing id, so the job cannot
 * ever drain and "Retry failed" is guaranteed to fail. Observed in prod
 * 2026-08-15 as `codes=[NOT_FOUND] fields=[customerPatch]`.
 *
 * Deliberately narrow — a structured `NOT_FOUND` code, never a text match on
 * Wave's message. This unlinks a client from its Wave customer, so a loose
 * predicate would do that on the strength of a reworded error. The only thing
 * a `customerPatch` can fail to find is the customer, so the code alone is
 * enough inside that call.
 *
 * @param {*} err The error thrown by the patch mutation.
 * @return {boolean}
 */
function isStaleCustomerLink(err) {
  if (!(err instanceof WaveApiError) || err.kind !== "graphql") return false;
  const details = Array.isArray(err.details) ? err.details : [];
  return details.some((d) => d && d.extensions &&
    d.extensions.code === "NOT_FOUND");
}

/**
 * The same conclusion from the OTHER shape Wave can report it in — a
 * `didSucceed: false` payload carrying a `NOT_FOUND` input error.
 *
 * Which shape arrives is Wave's choice, and the consequence of missing one is
 * identical: the doc keeps a link to a customer that is gone, and the job
 * dead-letters on it forever. `ERROR_CODE_MESSAGES` has mapped this code to
 * "The customer no longer exists in Wave." all along — the message was
 * reachable, the recovery was not. Only consulted for a PATCH, where the sole
 * entity that can be missing is the customer being patched.
 *
 * @param {Array<{code:string}>} inputErrors Wave input errors.
 * @return {boolean}
 */
function hasNotFoundInputError(inputErrors) {
  const errs = Array.isArray(inputErrors) ? inputErrors : [];
  return errs.some((e) => e && e.code === "NOT_FOUND");
}

// ---------------------------------------------------------------------------
// upsertCustomer
// ---------------------------------------------------------------------------

/**
 * Pushes a single client document to Wave, hash-gated so we don't do
 * redundant work: a missing doc skips, an already-synced hash no-ops, an
 * existing `waveCustomerId` patches, and an unlinked doc creates (with a
 * phone/mobile fallback). On success we write the sync result back in a
 * short idempotency-checked transaction. A Wave validation rejection flags
 * the doc `error` and throws `WaveValidationError`; transport `WaveApiError`s
 * just propagate unchanged.
 * @param {string} clientId Firestore `clients` document id.
 * @param {Object=} deps Injectable dependencies — `db`, `graphql`,
 *   `businessId`, `now`, `priorAttempts` (the outbox job's failed-attempt
 *   count). When `priorAttempts > 0`, an unlinked create first searches Wave
 *   for a customer a crashed previous attempt may already have created, and
 *   links it instead of duplicating. No default touches real Firestore or
 *   network during a unit test.
 * @return {!Promise<!Object>} A status object (see decision flow). The
 *   `status` vocabulary — `skipped`/`noop`/`patched`/`linked`/`created` — is
 *   READ FOR DISPLAY by `tallyUpsert` in `worker.js`, which turns it into the
 *   "N clients added to Wave / N updated in Wave" counts the admin sees after
 *   a sync. A sixth status added here lands in that helper's uncounted bucket
 *   by default, with every test still passing — classify it there too.
 * @throws {WaveValidationError} On a Wave validation rejection.
 */
async function upsertCustomer(clientId, deps = {}) {
  const db = deps.db || adminFirestore().getFirestore();
  const graphql = deps.graphql || require("./client").graphql;
  const now = deps.now || adminFirestore().FieldValue.serverTimestamp;

  const ref = db.collection("clients").doc(clientId);
  const snap = await ref.get();
  if (!snap || !snap.exists) {
    return {status: "skipped", reason: "missing-doc"};
  }

  const data = snap.data() || {};
  const mappedFields = toWaveCustomerInput(data);
  const hash = mappedFieldsHash(data);
  const waveCustomerId =
    typeof data.waveCustomerId === "string" ? data.waveCustomerId : "";
  const wave = (data.wave && typeof data.wave === "object") ? data.wave : {};

  // Step 3 — already synced with identical mapped fields → no-op.
  if (waveCustomerId && hash === wave.lastSyncedHash) {
    // The doc can still be flagged `pending` here, and nothing else would ever
    // clear it. The trigger marks pending + enqueues on every mapped-field
    // change, but a later write that puts those fields BACK is skipped by
    // shouldEnqueueClientWrite's rule 2 — so the job the first edit left behind
    // arrives to find nothing to push. The admin-facing badge reads this field,
    // so without the heal that client shows "Sync pending" forever while every
    // later sync correctly reports nothing to do.
    //
    // Gated on the state we already read: a no-op is the steady-state outcome
    // for most clients, and healSyncState opens a transaction (a second read)
    // that would return immediately on an already-synced doc. A doc that turned
    // pending since this read has its own queued job and needs no heal.
    if (wave.syncState !== "synced") {
      await healSyncState(db, ref);
    }
    return {status: "noop"};
  }

  const businessId = deps.businessId || await readBusinessId(db);

  // Set once the doc's `waveCustomerId` has been PROVED dead — Wave answered
  // the patch with NOT_FOUND, so that customer is gone from Wave. Carried
  // through to the create path, which then relinks or recreates.
  let staleLink = "";

  if (waveCustomerId) {
    // Step 4 — patch the existing Wave customer (no businessId on patch).
    let payload = null;
    try {
      payload = await runCustomerMutation(
          graphql, PATCH_CUSTOMER, {id: waveCustomerId, ...mappedFields},
      );
    } catch (err) {
      if (!isStaleCustomerLink(err)) throw err;
      // The customer this doc points at no longer exists in Wave (deleted
      // there, most often). Rethrowing dead-letters the job on an error that
      // can NEVER clear: the id is stored, so every later push — and every
      // "Retry failed" press — re-sends the same missing id and fails
      // identically. Fall through and re-establish the link instead.
      staleLink = waveCustomerId;
    }
    if (payload) {
      if (payload.didSucceed) {
        await writeSyncSuccess(db, ref, now, {hash, waveCustomerId: null});
        return {status: "patched", waveCustomerId};
      }
      if (hasNotFoundInputError(payload.inputErrors)) {
        staleLink = waveCustomerId;
      } else {
        await writeSyncError(db, ref, now, payload.inputErrors);
        throw new WaveValidationError(payload.inputErrors);
      }
    }
  }

  // Step 5 — create a new Wave customer. On a retry (priorAttempts > 0) of
  // an unlinked doc, search Wave by name+email first and link instead of
  // duplicating, in case a crashed previous attempt already created it.
  //
  // A stale link takes the same route, deliberately: from here the two are the
  // same situation — the doc claims a Wave customer we cannot patch — and the
  // identity search is what stops a spurious NOT_FOUND from minting a second
  // customer for a client that already has one.
  const priorAttempts =
    typeof deps.priorAttempts === "number" ? deps.priorAttempts : 0;
  if (staleLink || priorAttempts > 0) {
    const existing = await findCustomerByIdentity(
        graphql, businessId, mappedFields,
    );
    if (existing) {
      // Patch the found customer so the doc's CURRENT fields land in Wave
      // (the crashed attempt may have written stale data), then link it.
      const payload = await runCustomerMutation(
          graphql, PATCH_CUSTOMER, {id: existing.id, ...mappedFields},
      );
      if (!payload.didSucceed) {
        await writeSyncError(db, ref, now, payload.inputErrors);
        throw new WaveValidationError(payload.inputErrors);
      }
      await writeSyncSuccess(
          db, ref, now,
          {hash, waveCustomerId: existing.id, replacesLink: staleLink},
      );
      return {status: "linked", waveCustomerId: existing.id};
    }
  }

  const created = await createCustomerWithPhoneFallback(
      graphql, businessId, mappedFields,
  );
  if (!created.didSucceed) {
    await writeSyncError(db, ref, now, created.inputErrors);
    throw new WaveValidationError(created.inputErrors);
  }
  const newId = created.customer && typeof created.customer.id === "string" ?
    created.customer.id : "";
  // When the phone/mobile patch was deferred, record the hash of what actually
  // landed in Wave (without phone) so the next upsert sees a mismatch and
  // retries instead of treating it as synced.
  const syncedHash = created.phoneDeferred ?
    mappedFieldsHash({...data, phone: "", mobile: ""}) : hash;
  await writeSyncSuccess(
      db, ref, now,
      {hash: syncedHash, waveCustomerId: newId, replacesLink: staleLink},
  );
  return {status: "created", waveCustomerId: newId};
}

/**
 * Searches Wave customers for one matching a client doc's normalized
 * name+email identity — only used on the crash-retry path of an unlinked
 * create. We paginate `LIST_CUSTOMERS` since Wave has no server-side
 * name/email filter. Archived customers are skipped, and transport errors
 * just propagate.
 * @param {!Function} graphql Injected graphql function.
 * @param {string} businessId Connected Wave business id.
 * @param {!Object} mappedFields Mapped Wave customer fields for the doc.
 * @param {number=} pageSize Page size for the listing (default 100).
 * @return {!Promise<?{id: string}>} The matching customer, or null.
 */
async function findCustomerByIdentity(graphql, businessId, mappedFields,
    pageSize = 100) {
  const norm = (v) => (typeof v === "string" ? v.trim().toLowerCase() : "");
  const wantName = norm(mappedFields.name);
  const wantEmail = norm(mappedFields.email);
  // A blank name can never identify "our" customer — bail out rather than
  // linking an arbitrary blank-named record.
  if (!wantName) return null;

  let page = 1;
  for (;;) {
    const data = await graphql(
        LIST_CUSTOMERS, {id: businessId, page, pageSize},
    );
    const customers = data && data.business ? data.business.customers : null;
    const pageInfo = (customers && customers.pageInfo) || {};
    const edges = (customers && Array.isArray(customers.edges)) ?
      customers.edges : [];

    for (const edge of edges) {
      const node = edge && edge.node;
      if (!node || node.isArchived === true) continue;
      if (typeof node.id !== "string" || !node.id) continue;
      if (norm(node.name) === wantName && norm(node.email) === wantEmail) {
        return {id: node.id};
      }
    }

    const current = typeof pageInfo.currentPage === "number" ?
      pageInfo.currentPage : page;
    const total = typeof pageInfo.totalPages === "number" ?
      pageInfo.totalPages : current;
    if (current >= total) return null;
    page = current + 1;
  }
}

/**
 * Calls a customer mutation and returns the normalized payload. Transport
 * errors still propagate, but a `didSucceed:false` comes back as a return
 * value rather than a throw, so callers can branch on it.
 * @param {!Function} graphql Injected graphql function.
 * @param {string} mutation The mutation document.
 * @param {!Object} input The mutation input (becomes the `input` variable).
 * @return {!Promise<{didSucceed:boolean, inputErrors:!Array, customer:Object}>}
 */
async function runCustomerMutation(graphql, mutation, input) {
  const data = await graphql(mutation, {input});
  const key = mutation === PATCH_CUSTOMER ? "customerPatch" : "customerCreate";
  return readMutationPayload(data ? data[key] : null);
}

/**
 * Creates a Wave customer with the plan §7 phone/mobile fallback. If create
 * fails on phone/mobile errors only, we retry without them and then patch
 * them onto the new id afterward. Any other failure is just returned as-is.
 * @param {!Function} graphql Injected graphql function.
 * @param {string} businessId Connected Wave business id.
 * @param {!Object} mappedFields Mapped Wave customer fields.
 * @return {!Promise<{didSucceed:boolean, inputErrors:!Array, customer:Object}>}
 */
async function createCustomerWithPhoneFallback(graphql, businessId,
    mappedFields) {
  const first = await runCustomerMutation(
      graphql, CREATE_CUSTOMER, {businessId, ...mappedFields},
  );
  if (first.didSucceed) return first;
  if (!allPhoneFieldErrors(first.inputErrors)) return first;

  // Retry create without phone/mobile.
  const {phone, mobile, ...withoutPhone} = mappedFields;
  const retry = await runCustomerMutation(
      graphql, CREATE_CUSTOMER, {businessId, ...withoutPhone},
  );
  if (!retry.didSucceed) return retry;

  const newId = retry.customer && typeof retry.customer.id === "string" ?
    retry.customer.id : "";
  const phoneFields = {};
  if (phone !== undefined) phoneFields.phone = phone;
  if (mobile !== undefined) phoneFields.mobile = mobile;

  // Nothing to patch back (defensive — we only get here on a phone error).
  let phoneDeferred = false;
  if (newId && Object.keys(phoneFields).length > 0) {
    // Try to patch phone/mobile onto the new customer, best effort.
    // `phoneDeferred` tells the caller to fall back to a phone-less hash
    // if this patch fails.
    const patched = await runCustomerMutation(
        graphql, PATCH_CUSTOMER, {id: newId, ...phoneFields},
    );
    phoneDeferred = !patched.didSucceed;
  } else {
    // Had phone/mobile to set but no usable id to patch onto — also deferred.
    phoneDeferred = Object.keys(phoneFields).length > 0;
  }
  return {...retry, phoneDeferred};
}

/**
 * Writes a successful sync result back to the client doc inside a short
 * transaction that re-checks the create idempotency guard. `waveCustomerId`
 * only gets set when the doc is still unlinked, so we never overwrite a
 * concurrent create. A patch call (`waveCustomerId:null`) leaves the
 * existing link untouched.
 * @param {!Object} db Firestore instance.
 * @param {!Object} ref Client document reference.
 * @param {!Function} now serverTimestamp factory.
 * @param {{hash:string, waveCustomerId:(string|null)}} result Sync result.
 * @return {!Promise<void>}
 */
async function writeSyncSuccess(db, ref, now, result) {
  await db.runTransaction(async (tx) => {
    const fresh = await tx.get(ref);
    // Doc was deleted between the initial read and this write-back — leave
    // the orphaned Wave customer unlinked and just no-op.
    if (!fresh || !fresh.exists) return;
    const cur = (fresh && fresh.exists && fresh.data()) || {};
    const update = {
      "wave.syncState": "synced",
      "wave.lastSyncedHash": result.hash,
      "wave.lastSyncedAt": now(),
      "wave.syncError": null,
    };
    if (result.waveCustomerId) {
      // Only set the link when the doc is still unlinked — that's what
      // keeps this idempotent.
      const existing =
        typeof cur.waveCustomerId === "string" ? cur.waveCustomerId : "";
      if (!existing) {
        update.waveCustomerId = result.waveCustomerId;
      } else if (result.replacesLink && existing === result.replacesLink) {
        // ...with ONE exception: a link we have just PROVED dead (Wave
        // answered the patch with NOT_FOUND). Refusing to overwrite it is what
        // made that client unrecoverable — every later push re-sent the same
        // missing id and dead-lettered on it again. Conditioned on the stale
        // id still being the one on the doc, so a link established concurrently
        // (which is newer, and not proven dead) is never clobbered.
        update.waveCustomerId = result.waveCustomerId;
      }
    }
    tx.update(ref, update);
  });
}

/**
 * Clears a stale `pending`/`error` flag on a doc whose mapped fields already
 * match its own `wave.lastSyncedHash` — i.e. Wave demonstrably holds this data
 * and there is nothing left to push.
 *
 * The check is re-run against a FRESH read inside the transaction, not against
 * the hash the caller computed. An edit landing between `upsertCustomer`'s read
 * and this write must not be marked synced: that would put "Synced with Wave"
 * on a client whose change is still sitting in the outbox, which is the exact
 * lie this heal exists to remove.
 *
 * Writes only `wave.syncState`/`wave.syncError`, never `lastSyncedAt` — nothing
 * reached Wave just now, and that stamp must keep naming the last real push.
 * The write re-fires the `waveUpsertCustomer` trigger, which sees unchanged
 * mapped fields and returns at rule 1, so there is no loop.
 * @param {!Object} db Firestore instance.
 * @param {!Object} ref Client document reference.
 * @return {!Promise<void>}
 */
async function healSyncState(db, ref) {
  await db.runTransaction(async (tx) => {
    const fresh = await tx.get(ref);
    if (!fresh || !fresh.exists) return;
    const cur = fresh.data() || {};
    const wave = (cur.wave && typeof cur.wave === "object") ? cur.wave : {};
    if (wave.syncState === "synced") return;
    if (!wave.lastSyncedHash) return;
    if (mappedFieldsHash(cur) !== wave.lastSyncedHash) return;
    tx.update(ref, {"wave.syncState": "synced", "wave.syncError": null});
  });
}

/**
 * Flags the client doc as a sync error with a sanitized message.
 * @param {!Object} db Firestore instance.
 * @param {!Object} ref Client document reference.
 * @param {!Function} now serverTimestamp factory.
 * @param {!Array} inputErrors Wave input errors (mapped by code only).
 * @return {!Promise<void>}
 */
async function writeSyncError(db, ref, now, inputErrors) {
  await db.runTransaction(async (tx) => {
    const fresh = await tx.get(ref);
    if (!fresh || !fresh.exists) return;
    tx.update(ref, {
      "wave.syncState": "error",
      "wave.syncError": sanitizeInputErrors(inputErrors),
      "wave.lastSyncedAt": now(),
    });
  });
}

// ---------------------------------------------------------------------------
// importCustomers
// ---------------------------------------------------------------------------

/** Firestore WriteBatch hard limit. */
const BATCH_LIMIT = 500;

/**
 * Decides what one Wave customer means locally and stages that write.
 *
 * Extracted from [importCustomers]' page loop because every one of the five
 * counters it touches feeds the watermark logic afterwards, and a single
 * miscounted `skippedPending` silently loses Wave-side data — that decision
 * deserves to be readable on its own rather than buried three levels into a
 * paging loop.
 *
 * Mutates `ctx.summary` and stages onto `ctx.batch`.
 *
 * @param {?Object} node One Wave customer node, or null.
 * @param {{db: !Object, batch: !Object, now: !Function, summary: !Object,
 *   skipClientIds: !Set<string>, existingByWaveId: !Map<string, !Object>}} ctx
 * @return {boolean} whether an operation was staged on the batch.
 */
function importOneCustomer(node, ctx) {
  const {db, batch, now, summary, skipClientIds, existingByWaveId} = ctx;
  if (!node) return false;
  if (node.isArchived === true) {
    summary.skippedArchived += 1;
    return false;
  }
  const fields = fromWaveCustomer(node);
  const hash = mappedFieldsHash(fields);
  const docFields = {
    ...fields,
    wave: {
      syncState: "synced",
      syncError: null,
      lastSyncedHash: hash,
      lastSyncedAt: now(),
    },
  };

  const waveId = fields.waveCustomerId;
  const existing = waveId ? existingByWaveId.get(waveId) : undefined;
  if (existing) {
    // The local edit wins while it is still queued for Wave. Overwriting
    // here would also stamp lastSyncedHash from Wave's values, which
    // turns the pending push into a no-op and destroys the edit
    // permanently — see listOutstandingClientIds in worker.js.
    if (skipClientIds.has(existing.ref.id)) {
      summary.skippedPending += 1;
      return false;
    }
    // Nothing to write: `hash` is taken over the SAME `toWaveCustomerInput`
    // projection that produced the stored `lastSyncedHash`, and the update
    // below sets the doc's mapped fields to exactly `fields` — so a match
    // means this write would be byte-identical. (That equality is already
    // load-bearing: it is what `shouldEnqueueClientWrite`'s Rule 2 uses to
    // stop an import feeding every client straight back into the outbox.)
    //
    // `hasCreatedAt` is NOT optional here. The branch below backfills a
    // missing `createdAt`, and the clients list orders by it — Firestore
    // excludes docs missing an orderBy field, so skipping one would leave
    // a legacy doc permanently invisible in the list.
    if (existing.hasCreatedAt && existing.lastSyncedHash === hash) {
      summary.skippedUnchanged += 1;
      return false;
    }
    // Preserve the original createdAt. Only backfill it when the
    // existing doc lacks one (e.g. a doc from an earlier import that
    // omitted it).
    const update = {...docFields, updatedAt: now()};
    if (!existing.hasCreatedAt) update.createdAt = now();
    batch.set(existing.ref, update, {merge: true});
    summary.updated += 1;
    return true;
  }

  const newRef = db.collection("clients").doc();
  // createdAt/updatedAt are required: the clients list orders by
  // createdAt, and Firestore excludes docs missing that field. `archived`
  // is required for the same reason — the list FILTERS on it, so a doc
  // without it is invisible there while still turning up in search.
  // Deliberately create-only: setting it on the update branch above
  // would un-archive every archived client on every scheduled import.
  batch.set(newRef, {
    ...docFields,
    archived: false,
    createdAt: now(),
    updatedAt: now(),
  });
  summary.imported += 1;
  // Cache so duplicate Wave ids within the same import collapse to one.
  if (waveId) {
    existingByWaveId.set(waveId, {ref: newRef, hasCreatedAt: true});
  }
  return true;
}

/**
 * One-time Wave → App seed. Paginates customers, skips archived ones, and
 * writes active ones to `clients`. Idempotent on `waveCustomerId` — we don't
 * use it as the doc id directly, since Wave Node ids are base64 and can
 * contain `/`, which isn't legal in a Firestore doc id.
 * @param {Object=} deps Injectable dependencies — `db`, `graphql`,
 *   `businessId`, `pageSize` (default 100), `now`, `skipClientIds` (a Set of
 *   client ids with an un-pushed outbox job — see below). No default touches
 *   real Firestore/network during a unit test.
 *
 *   `skipClientIds` is passed in rather than read here on purpose:
 *   `worker.js` owns the queue and already requires this module, so reaching
 *   back for `listOutstandingClientIds` would close a require cycle. Every
 *   caller must supply it — omitting it silently re-opens the clobber
 *   described on that helper.
 *
 *   `since` (an ISO-8601 string, optional) switches the run to a DELTA
 *   import: Wave filters by `modifiedAtAfter` server-side and returns only
 *   customers changed after that instant. Absent → full import. The caller
 *   owns the watermark, because it owns `wave/connection`; this function is
 *   deliberately stateless about it.
 * @return {!Promise<!Object>} Summary `{totalCount, imported, updated,
 *   skippedArchived, skippedPending, skippedUnchanged, pages, delta}`.
 *   `updated` counts only customers whose Wave-mapped fields actually
 *   differed. **`totalCount` is the size of the QUERIED set, so on a delta
 *   run it is the number of changed customers, not the roster size** — don't
 *   render it as "you have N clients".
 */
async function importCustomers(deps = {}) {
  const db = deps.db || adminFirestore().getFirestore();
  const graphql = deps.graphql || require("./client").graphql;
  const now = deps.now || adminFirestore().FieldValue.serverTimestamp;
  const pageSize = typeof deps.pageSize === "number" && deps.pageSize > 0 ?
    deps.pageSize : 100;
  const businessId = deps.businessId || await readBusinessId(db);
  const skipClientIds = deps.skipClientIds || new Set();
  const since = typeof deps.since === "string" && deps.since ? deps.since : "";
  const isDelta = since !== "";

  // Single pass over existing clients → Map<waveCustomerId, docRef>, built
  // LAZILY (see the page loop): a delta run that finds nothing changed would
  // otherwise pay ~650 document reads to resolve zero customers. Note the
  // saving is inside THIS function — the sync around it still does its own
  // reads (connection doc, rate limiter, queue queries).
  let existingByWaveId = null;

  let batch = db.batch();
  let opsInBatch = 0;
  // `updated` counts REAL changes only — everything unchanged lands in
  // `skippedUnchanged`. Before that split it counted every existing customer
  // written, so a sync over an untouched roster told the admin "650 clients
  // updated in the app" on every single press.
  const summary = {
    totalCount: 0, imported: 0, updated: 0, skippedArchived: 0,
    skippedPending: 0, skippedUnchanged: 0, pages: 0, delta: isDelta,
  };

  const flushIfFull = async () => {
    if (opsInBatch >= BATCH_LIMIT) {
      await batch.commit();
      batch = db.batch();
      opsInBatch = 0;
    }
  };

  // Hoisted: the document and its extra variable are decided once, not
  // re-paired on every page.
  const listQuery = isDelta ? LIST_CUSTOMERS_SINCE : LIST_CUSTOMERS;
  const listArgs = isDelta ? {id: businessId, since} : {id: businessId};

  let page = 1;
  for (;;) {
    const data = await graphql(listQuery, {...listArgs, page, pageSize});
    const customers =
      data && data.business ? data.business.customers : null;
    const pageInfo = (customers && customers.pageInfo) || {};
    const edges = (customers && Array.isArray(customers.edges)) ?
      customers.edges : [];
    summary.pages += 1;
    // Built here rather than up front, so an empty delta page reads nothing.
    if (edges.length && !existingByWaveId) {
      existingByWaveId = await buildWaveIdIndex(db);
    }
    if (typeof pageInfo.totalCount === "number") {
      summary.totalCount = pageInfo.totalCount;
    }

    for (const edge of edges) {
      const wrote = importOneCustomer(edge && edge.node, {
        db, batch, now, summary, skipClientIds, existingByWaveId,
      });
      if (!wrote) continue;
      opsInBatch += 1;
      await flushIfFull();
    }

    const current = typeof pageInfo.currentPage === "number" ?
      pageInfo.currentPage : page;
    const total = typeof pageInfo.totalPages === "number" ?
      pageInfo.totalPages : current;
    if (current >= total) break;
    page = current + 1;
  }

  if (opsInBatch > 0) await batch.commit();
  return summary;
}

/**
 * Builds a `Map<waveCustomerId, {ref, hasCreatedAt, lastSyncedHash}>` over the
 * `clients` collection in one pass, skipping docs without a `waveCustomerId`.
 * `hasCreatedAt` lets a re-run backfill a missing `createdAt` without
 * clobbering an existing one; `lastSyncedHash` is what lets the import skip a
 * customer whose Wave-mapped fields already match. It loads the whole
 * collection into memory, which is fine at the ~650-customer import scale
 * we're at now, but should move to a cursor if that grows.
 * @param {!Object} db Firestore instance.
 * @return {!Promise<!Map<string, {ref: !Object, hasCreatedAt: boolean,
 *   lastSyncedHash: string}>>}
 */
async function buildWaveIdIndex(db) {
  const index = new Map();
  // select(): only these fields are read, and a full client doc carries the
  // address family and the contacts array. Billed reads are per-document
  // either way, so this is pure transfer + parse + retained memory. `wave` is
  // taken whole rather than as a `wave.lastSyncedHash` field path — the map
  // is three small scalars, and a nested projection is the kind of thing that
  // silently returns undefined if the path is ever renamed.
  const snap = await db.collection("clients")
      .select("waveCustomerId", "createdAt", "wave")
      .get();
  const docs = (snap && Array.isArray(snap.docs)) ? snap.docs : [];
  for (const doc of docs) {
    const d = doc.data() || {};
    const id = typeof d.waveCustomerId === "string" ? d.waveCustomerId : "";
    if (!id) continue;
    const wave = (d.wave && typeof d.wave === "object") ? d.wave : {};
    index.set(id, {
      ref: doc.ref,
      hasCreatedAt: d.createdAt != null,
      lastSyncedHash: typeof wave.lastSyncedHash === "string" ?
        wave.lastSyncedHash : "",
    });
  }
  return index;
}

module.exports = {
  WaveValidationError,
  upsertCustomer,
  importCustomers,
  // Exported for the sanitizer unit tests in __tests__/wave_customers.test.js,
  // which pin the contract that Wave's raw `message` text never reaches us.
  sanitizeInputErrors,
  // Exported so the unlink decision can be driven directly — it is the one
  // predicate here that REWRITES a client's Wave link.
  isStaleCustomerLink,
  hasNotFoundInputError,
};

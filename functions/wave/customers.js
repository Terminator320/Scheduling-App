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

const LIST_CUSTOMERS = `
query ListCustomers($id: ID!, $page: Int!, $pageSize: Int!) {
  business(id: $id) {
    customers(page: $page, pageSize: $pageSize, sort: [NAME_ASC]) {
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
      }
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
 * @return {!Promise<!Object>} A status object (see decision flow).
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
    return {status: "noop"};
  }

  const businessId = deps.businessId || await readBusinessId(db);

  if (waveCustomerId) {
    // Step 4 — patch the existing Wave customer (no businessId on patch).
    const payload = await runCustomerMutation(
        graphql, PATCH_CUSTOMER, {id: waveCustomerId, ...mappedFields},
    );
    if (!payload.didSucceed) {
      await writeSyncError(db, ref, now, payload.inputErrors);
      throw new WaveValidationError(payload.inputErrors);
    }
    await writeSyncSuccess(db, ref, now, {hash, waveCustomerId: null});
    return {status: "patched", waveCustomerId};
  }

  // Step 5 — create a new Wave customer. On a retry (priorAttempts > 0) of
  // an unlinked doc, search Wave by name+email first and link instead of
  // duplicating, in case a crashed previous attempt already created it.
  const priorAttempts =
    typeof deps.priorAttempts === "number" ? deps.priorAttempts : 0;
  if (priorAttempts > 0) {
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
          db, ref, now, {hash, waveCustomerId: existing.id},
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
      db, ref, now, {hash: syncedHash, waveCustomerId: newId},
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
      if (!existing) update.waveCustomerId = result.waveCustomerId;
    }
    tx.update(ref, update);
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
 * One-time Wave → App seed. Paginates customers, skips archived ones, and
 * writes active ones to `clients`. Idempotent on `waveCustomerId` — we don't
 * use it as the doc id directly, since Wave Node ids are base64 and can
 * contain `/`, which isn't legal in a Firestore doc id.
 * @param {Object=} deps Injectable dependencies — `db`, `graphql`,
 *   `businessId`, `pageSize` (default 100), `now`. No default touches real
 *   Firestore/network during a unit test.
 * @return {!Promise<!Object>} Summary `{totalCount, imported, updated,
 *   skippedArchived, pages}`.
 */
async function importCustomers(deps = {}) {
  const db = deps.db || adminFirestore().getFirestore();
  const graphql = deps.graphql || require("./client").graphql;
  const now = deps.now || adminFirestore().FieldValue.serverTimestamp;
  const pageSize = typeof deps.pageSize === "number" && deps.pageSize > 0 ?
    deps.pageSize : 100;
  const businessId = deps.businessId || await readBusinessId(db);

  // Single pass over existing clients → Map<waveCustomerId, docRef>.
  const existingByWaveId = await buildWaveIdIndex(db);

  let batch = db.batch();
  let opsInBatch = 0;
  const summary =
    {totalCount: 0, imported: 0, updated: 0, skippedArchived: 0, pages: 0};

  const flushIfFull = async () => {
    if (opsInBatch >= BATCH_LIMIT) {
      await batch.commit();
      batch = db.batch();
      opsInBatch = 0;
    }
  };

  let page = 1;
  for (;;) {
    const data = await graphql(
        LIST_CUSTOMERS, {id: businessId, page, pageSize},
    );
    const customers =
      data && data.business ? data.business.customers : null;
    const pageInfo = (customers && customers.pageInfo) || {};
    const edges = (customers && Array.isArray(customers.edges)) ?
      customers.edges : [];
    summary.pages += 1;
    if (typeof pageInfo.totalCount === "number") {
      summary.totalCount = pageInfo.totalCount;
    }

    for (const edge of edges) {
      const node = edge && edge.node;
      if (!node) continue;
      if (node.isArchived === true) {
        summary.skippedArchived += 1;
        continue;
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
        // Preserve the original createdAt. Only backfill it when the
        // existing doc lacks one (e.g. a doc from an earlier import that
        // omitted it).
        const update = {...docFields, updatedAt: now()};
        if (!existing.hasCreatedAt) update.createdAt = now();
        batch.set(existing.ref, update, {merge: true});
        summary.updated += 1;
      } else {
        const newRef = db.collection("clients").doc();
        // createdAt/updatedAt are required: the clients list orders by
        // createdAt, and Firestore excludes docs missing that field.
        batch.set(newRef, {...docFields, createdAt: now(), updatedAt: now()});
        summary.imported += 1;
        // Cache so duplicate Wave ids within the same import collapse to one.
        if (waveId) {
          existingByWaveId.set(waveId, {ref: newRef, hasCreatedAt: true});
        }
      }
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
 * Builds a `Map<waveCustomerId, {ref, hasCreatedAt}>` over the `clients`
 * collection in one pass, skipping docs without a `waveCustomerId`. This
 * lets a re-run backfill a missing `createdAt` without clobbering an
 * existing one. It loads the whole collection into memory, which is fine at
 * the ~650-customer import scale we're at now, but should move to a cursor
 * if that grows.
 * @param {!Object} db Firestore instance.
 * @return {!Promise<!Map<string, {ref: !Object, hasCreatedAt: boolean}>>}
 */
async function buildWaveIdIndex(db) {
  const index = new Map();
  const snap = await db.collection("clients").get();
  const docs = (snap && Array.isArray(snap.docs)) ? snap.docs : [];
  for (const doc of docs) {
    const d = doc.data() || {};
    const id = typeof d.waveCustomerId === "string" ? d.waveCustomerId : "";
    if (id) index.set(id, {ref: doc.ref, hasCreatedAt: d.createdAt != null});
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
};

"use strict";

/**
 * @fileoverview The Wave → App half of customer sync: `importCustomers`
 * paginates Wave's customer list and seeds/refreshes Firestore `clients`
 * docs, idempotent on `waveCustomerId`.
 *
 * Split out of `customers.js` (which keeps the App → Wave push half) because
 * the two share no control flow — neither calls the other. They still share
 * one fact, and it is load-bearing: the `lastSyncedHash` the push half writes
 * on a successful push is the same projection `importOneCustomer` compares
 * against here, which is what stops an import clobbering a queued local edit.
 * See the comments inside `importOneCustomer`.
 *
 * `customers.js` re-exports `importCustomers`, so `require("./customers")`
 * keeps working for every existing call site.
 * @module wave/customers_import
 */

const {mappedFieldsHash, fromWaveCustomer} = require("./mappers");

/**
 * The push half, required LAZILY for the three internals this module shares
 * with it (`readBusinessId` and the two customer-listing GraphQL documents).
 *
 * `customers.js` re-exports `importCustomers` from here at module scope, so a
 * module-scope require back would close a real cycle: whichever file was
 * required second would see a half-built `exports`. Deferring to call time
 * makes the two loadable in either order. Same shape as `adminFirestore`
 * below and `client.js`'s `graphql` in the push half.
 * @return {!Object} The `wave/customers` module exports.
 */
function pushHalf() {
  // eslint-disable-next-line global-require
  return require("./customers");
}

/**
 * Lazily requires `firebase-admin/firestore` so tests that inject `db`/`now`
 * never trigger it.
 * @return {{getFirestore: !Function, FieldValue: !Object}}
 */
function adminFirestore() {
  // eslint-disable-next-line global-require
  return require("firebase-admin/firestore");
}

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
  const {readBusinessId, LIST_CUSTOMERS, LIST_CUSTOMERS_SINCE} = pushHalf();
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
  importCustomers,
  // Exported so the two decisions the page loop delegates can be driven
  // directly from a unit test: `importOneCustomer` owns the five counters the
  // watermark logic reads, and `buildWaveIdIndex` owns the shape those
  // decisions are made against.
  importOneCustomer,
  buildWaveIdIndex,
  BATCH_LIMIT,
};

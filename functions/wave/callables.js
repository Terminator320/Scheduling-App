const {onDocumentWritten} = require("firebase-functions/v2/firestore");
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const {defineSecret} = require("firebase-functions/params");
const logger = require("firebase-functions/logger");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");

const {WAVE_FULL_ACCESS_TOKEN} = require("./auth");
const {graphql, whoami, listBusinesses} = require("./client");
const {importCustomers} = require("./customers");
const {
  enqueueCustomerUpsert,
  drainQueue,
  shouldEnqueueClientWrite,
} = require("./worker");
const {mappedFieldsHash} = require("./mappers");
const {classifyWaveError} = require("./errors");

const {
  assertPayloadShape,
  assertAdmin,
  enforceDurableRateLimit,
} = require("../security");

// waveImportCustomers is a heavy one-shot admin op (it paginates ~650 customers
// across ~7 Wave pages). A modest durable cap keeps a stuck/retried admin from
// hammering Wave: 5 imports per hour is ample for a setup/reconcile action.
const WAVE_IMPORT_RATE_MAX = 5;
const WAVE_IMPORT_RATE_WINDOW_MS = 60 * 60 * 1000;
// waveBootstrap's not-yet-connected path makes live Wave calls (whoami +
// listBusinesses). Cap it per-admin so a buggy/looping client can't burn the
// Wave request budget before a connection exists. The idempotent short-circuit
// (already-connected) runs before this and is not rate-limited.
const WAVE_BOOTSTRAP_RATE_MAX = 10;

// The Wave business to connect, kept in Secret Manager so the name never ships
// in the app and can change without an app release. Set it with
// `firebase functions:secrets:set WAVE_BUSINESS_NAME`. waveBootstrap (which
// declares it in its `secrets`) uses it as the target whenever the client
// supplies no businessId/businessName.
const WAVE_BUSINESS_NAME = defineSecret("WAVE_BUSINESS_NAME");

// ----- Wave Accounting integration ------------------------------------------
//
// These functions wire the app's `clients` collection to Wave Accounting
// customers (plan Task 5). The single `wave/connection` doc holds the selected
// business id; `waveSyncQueue` is a durable outbox drained on a schedule. The
// heavy lifting (GraphQL transport, mapping, queue mechanics) lives in the
// `wave/*` modules — these functions are thin orchestrators that add auth,
// admin, and rate-limit guards and translate Wave errors into HttpsErrors.
//
// App Check posture mirrors deleteAccount: admin callables run
// enforceAppCheck:false with a TODO(pre-ship) until Play Integrity can mint
// verified tokens for store builds.

/**
 * Reads the connected Wave `businessId` from the `wave/connection` doc, or
 * returns "" when the doc/field is absent. Used by the callables/scheduler to
 * gate on "bootstrapped yet?".
 * @return {!Promise<string>} The business id, or "" if not connected.
 */
async function readWaveBusinessId() {
  const snap = await getFirestore().collection("wave").doc("connection").get();
  const data = snap.exists ? snap.data() : null;
  return data && typeof data.businessId === "string" ? data.businessId : "";
}

// Per-instance cache for the scheduled worker's connection gate. The worker
// fires every minute forever, so an installation that never connects Wave
// would otherwise pay a Firestore read per minute per warm instance. A found
// businessId is cached for the instance's lifetime (bootstrap is
// set-once-never-changed); a NOT-connected result is cached for a short TTL
// so a fresh bootstrap is still picked up within a few minutes.
const NOT_CONNECTED_CACHE_MS = 5 * 60 * 1000;
let cachedBusinessId = "";
let notConnectedUntilMs = 0;

/**
 * Cached wrapper around readWaveBusinessId for the every-minute scheduler.
 * @return {!Promise<string>} The business id, or "" if not connected.
 */
async function readWaveBusinessIdCached() {
  if (cachedBusinessId) return cachedBusinessId;
  if (Date.now() < notConnectedUntilMs) return "";
  const businessId = await readWaveBusinessId();
  if (businessId) {
    cachedBusinessId = businessId;
  } else {
    notConnectedUntilMs = Date.now() + NOT_CONNECTED_CACHE_MS;
  }
  return businessId;
}

/**
 * Selects the intended Wave business from the listed businesses. Selection
 * order: by name when `wantName` (the server-configured business name) is
 * given, else the single business when exactly one exists. Never blindly takes
 * the first of several.
 * @param {!Array<{id: string, name: string}>} businesses Listed businesses.
 * @param {string} wantName Configured business name ("" when not set).
 * @return {{id: string, name: string}} The selected business.
 * @throws {HttpsError} not-found when a given name has no match;
 *   failed-precondition when ambiguous (several businesses, no selector).
 */
function selectBusiness(businesses, wantName) {
  const list = Array.isArray(businesses) ? businesses : [];
  if (wantName) {
    // NOTE: name match is case-insensitive and trims surrounding whitespace so
    // "acme co" / "  Acme Co  " both reach the same business. Id match above
    // stays exact (ids are opaque tokens).
    const want = wantName.trim().toLowerCase();
    const match = list.find((b) => b && b.name.trim().toLowerCase() === want);
    if (!match) throw new HttpsError("not-found", "wave/business-not-found");
    return match;
  }
  if (list.length === 1) return list[0];
  throw new HttpsError("failed-precondition", "wave/business-ambiguous");
}

// 1) waveBootstrap — admin-only, idempotent get-or-create of wave/connection.
const waveBootstrap = onCall(
    // TODO(pre-ship): set back to `enforceAppCheck: true` once the app ships
    // through Play Store and Play Integrity can mint verified App Check tokens.
    {
      secrets: [WAVE_FULL_ACCESS_TOKEN, WAVE_BUSINESS_NAME],
      enforceAppCheck: false,
    },
    async (req) => {
      if (!req.auth || !req.auth.uid) {
        throw new HttpsError("unauthenticated", "auth-required");
      }
      assertPayloadShape(req.data, new Set());
      await assertAdmin(req.auth.uid);

      const db = getFirestore();
      const ref = db.collection("wave").doc("connection");

      // Idempotent: an already-connected doc is returned unchanged.
      const existing = await ref.get();
      if (existing.exists && existing.data() &&
          typeof existing.data().businessId === "string" &&
          existing.data().businessId) {
        const d = existing.data();
        logger.info("WAVE-BOOT already connected", {
          uid: req.auth.uid,
          businessId: d.businessId,
        });
        return {businessId: d.businessId, businessName: d.businessName || ""};
      }

      // The target business is chosen server-side from the Secret Manager
      // value — the app never names the business. `|| ""` guards an unset/empty
      // secret against a trim() throw.
      const wantName = (WAVE_BUSINESS_NAME.value() || "").trim();

      // Only the not-yet-connected path (live Wave calls) is rate-limited.
      await enforceDurableRateLimit(
          "wave-bootstrap",
          req.auth.uid,
          WAVE_BOOTSTRAP_RATE_MAX,
          WAVE_IMPORT_RATE_WINDOW_MS,
      );

      // Network calls run OUTSIDE the transaction (transactions retry; a Wave
      // mutation must never run more than once). whoami() fast-fails a bad
      // token before we list businesses.
      let selected;
      try {
        await whoami();
        const businesses = await listBusinesses();
        selected = selectBusiness(businesses, wantName);
      } catch (e) {
        if (e instanceof HttpsError) throw e;
        const {code, message} = classifyWaveError(e);
        logger.warn("WAVE-BOOT failed", {uid: req.auth.uid, code, message});
        throw new HttpsError(code, message);
      }

      // Transaction set-if-absent so concurrent first calls converge on one
      // connection (the first writer wins; later writers return its value).
      const result = await db.runTransaction(async (tx) => {
        const fresh = await tx.get(ref);
        const fd = fresh.exists ? fresh.data() : null;
        if (fd && typeof fd.businessId === "string" && fd.businessId) {
          return {businessId: fd.businessId, businessName: fd.businessName ||
            ""};
        }
        tx.set(ref, {
          businessId: selected.id,
          businessName: selected.name || "",
          bootstrappedAt: FieldValue.serverTimestamp(),
        });
        return {businessId: selected.id, businessName: selected.name || ""};
      });

      logger.info("WAVE-BOOT connected", {
        uid: req.auth.uid,
        businessId: result.businessId,
      });
      return result;
    },
);

const waveGetConnection = onCall(
    // TODO(pre-ship): set back to `enforceAppCheck: true` once the app ships
    // through Play Store and Play Integrity can mint verified App Check tokens.
    {enforceAppCheck: false},
    async (req) => {
      if (!req.auth || !req.auth.uid) {
        throw new HttpsError("unauthenticated", "auth-required");
      }
      assertPayloadShape(req.data, new Set());
      await assertAdmin(req.auth.uid);

      const snap = await getFirestore()
          .collection("wave").doc("connection").get();
      const data = snap.exists ? snap.data() : null;
      const businessId = data && typeof data.businessId === "string" ?
        data.businessId : "";
      const businessName = data && typeof data.businessName === "string" ?
        data.businessName : "";
      return {connected: Boolean(businessId), businessId, businessName};
    },
);

// 2) waveImportCustomers — admin-only one-shot Wave → App seed.
const waveImportCustomers = onCall(
    // TODO(pre-ship): set back to `enforceAppCheck: true` once the app ships
    // through Play Store and Play Integrity can mint verified App Check tokens.
    {
      secrets: [WAVE_FULL_ACCESS_TOKEN],
      enforceAppCheck: false,
      timeoutSeconds: 300,
    },
    async (req) => {
      if (!req.auth || !req.auth.uid) {
        throw new HttpsError("unauthenticated", "auth-required");
      }
      assertPayloadShape(req.data, new Set());
      await assertAdmin(req.auth.uid);
      await enforceDurableRateLimit(
          "wave-import",
          req.auth.uid,
          WAVE_IMPORT_RATE_MAX,
          WAVE_IMPORT_RATE_WINDOW_MS,
      );

      const businessId = await readWaveBusinessId();
      if (!businessId) {
        throw new HttpsError("failed-precondition", "wave/not-bootstrapped");
      }

      logger.info("WAVE-CUST import starting", {
        uid: req.auth.uid,
        businessId,
      });
      let summary;
      try {
        summary = await importCustomers({businessId, graphql});
      } catch (e) {
        const {code, message} = classifyWaveError(e);
        logger.warn("WAVE-CUST import failed", {
          uid: req.auth.uid,
          code,
          message,
        });
        throw new HttpsError(code, message);
      }

      logger.info("WAVE-CUST import done", {
        uid: req.auth.uid,
        totalCount: summary.totalCount,
        imported: summary.imported,
        updated: summary.updated,
        skippedArchived: summary.skippedArchived,
        pages: summary.pages,
      });
      return summary;
    },
);

// 3) waveUpsertCustomer — enqueues a Wave write-back when a client doc's mapped
// fields change. No secret needed (it only writes to the Firestore outbox).
// `retry: true` is safe: the handler is idempotent (deterministic jobId via
// set-merge; the mark-pending update writes absolute values) and hash-guarded
// (shouldEnqueueClientWrite absorbs echoes), so a crash-retry converges.
const waveUpsertCustomer = onDocumentWritten(
    {document: "clients/{clientId}", retry: true},
    async (event) => {
      const beforeSnap = event.data?.before;
      const afterSnap = event.data?.after;
      const after = afterSnap?.exists ? afterSnap.data() : null;

      // Delete: the local doc is dropped and Wave is left intact (plan). No
      // enqueue.
      if (!after) return;

      const before = beforeSnap?.exists ? beforeSnap.data() : null;
      if (!shouldEnqueueClientWrite(before, after)) return;

      // NOTE: the mark-pending write touches only wave.* fields, so
      // shouldEnqueueClientWrite returns false when the trigger re-fires
      // (mappedFieldsHash is unchanged) — no second pending-write or loop.
      const clientId = event.params.clientId;
      const db = getFirestore();

      // Compute once here; shouldEnqueueClientWrite also hashes internally
      // but does not expose its result, so this call is the single explicit
      // hash at the enqueue site.
      const hash = mappedFieldsHash(after);

      // Mark-pending + enqueue land in ONE WriteBatch so a crash between the
      // two can't leave the doc stuck at 'pending' with no queued job (or a
      // queued job with no visible pending state).
      const batch = db.batch();
      batch.update(db.doc("clients/" + clientId), {
        "wave.syncState": "pending",
        "wave.syncError": null,
      });
      // payloadHash is diagnostic only: the worker re-reads the live doc
      // and recomputes before writing — the doc is the source of truth.
      await enqueueCustomerUpsert(clientId, {batch, payloadHash: hash});
      try {
        await batch.commit();
      } catch (e) {
        // The batch fails atomically when the doc was deleted between the
        // trigger firing and the commit (update precondition). Fall back to
        // enqueue-only: the worker resolves a missing doc as a clean skip,
        // and nothing is left half-written. Any other failure surfaces the
        // same way; retry:true re-runs the (idempotent) handler.
        logger.warn("waveUpsertCustomer: batched mark-pending failed; " +
            "enqueueing without it", {clientId, err: e.message});
        await enqueueCustomerUpsert(clientId, {payloadHash: hash});
      }
      logger.debug("waveUpsertCustomer: enqueued", {clientId});
    },
);

// 4) waveSyncWorker — drains the Wave outbox on a schedule. Single instance so
// Wave pacing stays simple; the worker's lease reaper + transactional claim
// handle robustness. 1/min × default batchLimit 30 = 30 Wave calls/min (< 60).
//
// timeoutSeconds is raised to 540 because a worst-case drain is minutes long
// (up to 30 serial jobs, each with client-level Retry-After sleeps of up to
// 60s × 3 retries); the default 60s timeout would kill the run mid-dispatch.
// drainQueue additionally gets a wall-clock deadline at ~70% of the timeout
// so it stops claiming new jobs in time to finish its outcome writes cleanly.
const WORKER_TIMEOUT_SECONDS = 540;
const WORKER_DEADLINE_FRACTION = 0.7;

const waveSyncWorker = onSchedule(
    {
      schedule: "every 1 minutes",
      secrets: [WAVE_FULL_ACCESS_TOKEN],
      maxInstances: 1,
      timeoutSeconds: WORKER_TIMEOUT_SECONDS,
    },
    async () => {
      // Cheap gate: skip the run entirely while Wave is not connected (the
      // cached read avoids a Firestore read per minute on idle installs).
      const businessId = await readWaveBusinessIdCached();
      if (!businessId) {
        logger.debug("waveSyncWorker: not bootstrapped — nothing to do");
        return;
      }
      // `graphql`/`upsertCustomer` intentionally omitted: drainQueue defaults
      // to the real Wave client (WAVE_FULL_ACCESS_TOKEN is in scope via this
      // function's `secrets` binding).
      const deadlineMs = Date.now() +
        WORKER_TIMEOUT_SECONDS * 1000 * WORKER_DEADLINE_FRACTION;
      const summary = await drainQueue({businessId, deadlineMs});
      logger.info("waveSyncWorker: drain done", {
        processed: summary.processed,
        done: summary.done,
        retried: summary.retried,
        dead: summary.dead,
        skipped: summary.skipped,
        reclaimed: summary.reclaimed,
      });
    },
);

module.exports = {
  selectBusiness,
  waveBootstrap,
  waveGetConnection,
  waveImportCustomers,
  waveUpsertCustomer,
  waveSyncWorker,
};

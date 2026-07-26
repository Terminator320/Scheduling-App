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
const {isImportDue, SCHEDULE_VALUES} = require("./import_schedule");

const {
  assertPayloadShape,
  assertAdmin,
  enforceDurableRateLimit,
} = require("../security");

// Accepted automatic-import cadences (mirrors the app's WaveImportSchedule
// enum and the wave/connection field); "off" is the default when absent.
const IMPORT_SCHEDULE_SET = new Set(SCHEDULE_VALUES);

// waveImportCustomers is a heavy one-shot admin op (~650 customers across ~7
// Wave pages), so a modest cap — 5 imports/hour — keeps a stuck/retried admin
// from hammering Wave.
const WAVE_IMPORT_RATE_MAX = 5;
const WAVE_IMPORT_RATE_WINDOW_MS = 60 * 60 * 1000;
// waveBootstrap's not-yet-connected path makes live Wave calls (whoami +
// listBusinesses), capped per-admin so a buggy/looping client can't burn the
// Wave request budget — the idempotent already-connected short-circuit runs
// before this and isn't rate-limited.
const WAVE_BOOTSTRAP_RATE_MAX = 10;

// The Wave business to connect, kept in Secret Manager (set via
// `firebase functions:secrets:set WAVE_BUSINESS_NAME`) so the name never ships
// in the app and can change without a release; waveBootstrap uses it as the
// target whenever the client supplies no businessId/businessName.
const WAVE_BUSINESS_NAME = defineSecret("WAVE_BUSINESS_NAME");

// ----- Wave Accounting integration ------------------------------------------
//
// These functions wire the app's `clients` collection to Wave Accounting
// customers (plan Task 5): the single `wave/connection` doc holds the selected
// business id, `waveSyncQueue` is a durable outbox drained on a schedule, and
// the heavy lifting lives in the `wave/*` modules — these functions are thin
// orchestrators adding auth/admin/rate-limit guards and translating Wave
// errors into HttpsErrors.

/**
 * Reads the connected Wave `businessId` from the `wave/connection` doc (or ""
 * when absent), used by the callables/scheduler to gate on "bootstrapped
 * yet?".
 * @return {!Promise<string>} The business id, or "" if not connected.
 */
async function readWaveBusinessId() {
  const snap = await getFirestore().collection("wave").doc("connection").get();
  const data = snap.exists ? snap.data() : null;
  return data && typeof data.businessId === "string" ? data.businessId : "";
}

// Per-instance cache for the scheduled worker's connection gate, so an
// installation that never connects Wave doesn't pay a Firestore read every
// 5-minute run — a found businessId caches for the instance's lifetime, a
// not-connected result for a short TTL so a fresh bootstrap is still picked up
// within a few minutes.
const NOT_CONNECTED_CACHE_MS = 5 * 60 * 1000;
let cachedBusinessId = "";
let notConnectedUntilMs = 0;

/**
 * Cached wrapper around readWaveBusinessId for the every-5-minutes scheduler.
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
 * Selects the intended Wave business from the listed businesses — by name
 * when `wantName` is given, else the single business when exactly one exists,
 * never blindly taking the first of several.
 * @param {!Array<{id: string, name: string}>} businesses Listed businesses.
 * @param {string} wantName Configured business name ("" when not set).
 * @return {{id: string, name: string}} The selected business.
 * @throws {HttpsError} not-found when a given name has no match;
 *   failed-precondition when ambiguous (several businesses, no selector).
 */
function selectBusiness(businesses, wantName) {
  const list = Array.isArray(businesses) ? businesses : [];
  if (wantName) {
    // NOTE: name match is case-insensitive and whitespace-trimmed (so
    // "acme co" / "  Acme Co  " both match); id match stays exact since ids
    // are opaque tokens.
    const want = wantName.trim().toLowerCase();
    // `b.name` is guarded too: a business with no name would otherwise throw a
    // raw TypeError that classifyWaveError turns into a misleading generic
    // Wave failure instead of the intended wave/business-not-found.
    const match = list.find((b) => b && typeof b.name === "string" &&
        b.name.trim().toLowerCase() === want);
    if (!match) throw new HttpsError("not-found", "wave/business-not-found");
    return match;
  }
  if (list.length === 1) return list[0];
  throw new HttpsError("failed-precondition", "wave/business-ambiguous");
}

// 1) waveBootstrap — admin-only, idempotent get-or-create of wave/connection.
const waveBootstrap = onCall(
    {
      secrets: [WAVE_FULL_ACCESS_TOKEN, WAVE_BUSINESS_NAME],
      enforceAppCheck: true,
    },
    async (req) => {
      if (!req.auth || !req.auth.uid) {
        throw new HttpsError("unauthenticated", "auth-required");
      }
      await assertAdmin(req.auth.uid);
      assertPayloadShape(req.data, new Set());

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
      // value (the app never names it); `|| ""` guards an unset/empty secret
      // against a trim() throw.
      const wantName = (WAVE_BUSINESS_NAME.value() || "").trim();

      // Only the not-yet-connected path (live Wave calls) is rate-limited.
      await enforceDurableRateLimit(
          "wave-bootstrap",
          req.auth.uid,
          WAVE_BOOTSTRAP_RATE_MAX,
          WAVE_IMPORT_RATE_WINDOW_MS,
      );

      // Network calls run outside the transaction (transactions retry, and a
      // Wave mutation must never run twice); whoami() fast-fails a bad token
      // before listing businesses.
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
    {enforceAppCheck: true},
    async (req) => {
      if (!req.auth || !req.auth.uid) {
        throw new HttpsError("unauthenticated", "auth-required");
      }
      await assertAdmin(req.auth.uid);
      assertPayloadShape(req.data, new Set());

      const snap = await getFirestore()
          .collection("wave").doc("connection").get();
      const data = snap.exists ? snap.data() : null;
      const businessId = data && typeof data.businessId === "string" ?
        data.businessId : "";
      const businessName = data && typeof data.businessName === "string" ?
        data.businessName : "";
      const rawSchedule = data && typeof data.importSchedule === "string" ?
        data.importSchedule : "off";
      const importSchedule =
        IMPORT_SCHEDULE_SET.has(rawSchedule) ? rawSchedule : "off";
      return {
        connected: Boolean(businessId),
        businessId,
        businessName,
        importSchedule,
      };
    },
);

// 2b) waveSetImportSchedule — admin-only setter for the automatic-import
// cadence, writing `importSchedule` on the single wave/connection doc; no
// secret or rate limit needed (a cheap Firestore write), just App Check +
// admin.
const waveSetImportSchedule = onCall(
    {enforceAppCheck: true},
    async (req) => {
      if (!req.auth || !req.auth.uid) {
        throw new HttpsError("unauthenticated", "auth-required");
      }
      await assertAdmin(req.auth.uid);
      assertPayloadShape(req.data, new Set(["schedule"]));

      const schedule = req.data && req.data.schedule;
      if (typeof schedule !== "string" || !IMPORT_SCHEDULE_SET.has(schedule)) {
        throw new HttpsError("invalid-argument", "wave/invalid-schedule");
      }

      const ref = getFirestore().collection("wave").doc("connection");
      const snap = await ref.get();
      const data = snap.exists ? snap.data() : null;
      if (!data || typeof data.businessId !== "string" || !data.businessId) {
        throw new HttpsError("failed-precondition", "wave/not-bootstrapped");
      }

      await ref.update({importSchedule: schedule});
      logger.info("WAVE-SCHED set", {uid: req.auth.uid, schedule});
      return {schedule};
    },
);

// 2) waveImportCustomers — admin-only one-shot Wave → App seed.
const waveImportCustomers = onCall(
    {
      secrets: [WAVE_FULL_ACCESS_TOKEN],
      enforceAppCheck: true,
      timeoutSeconds: 300,
    },
    async (req) => {
      if (!req.auth || !req.auth.uid) {
        throw new HttpsError("unauthenticated", "auth-required");
      }
      await assertAdmin(req.auth.uid);
      assertPayloadShape(req.data, new Set());
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

// 3) waveUpsertCustomer — enqueues a Wave write-back when a client doc's
// mapped fields change (no secret needed, it only writes to the Firestore
// outbox); `retry: true` is safe since the handler is idempotent and
// hash-guarded, so a crash-retry converges.
const waveUpsertCustomer = onDocumentWritten(
    {document: "clients/{clientId}", retry: true},
    async (event) => {
      const beforeSnap = event.data?.before;
      const afterSnap = event.data?.after;
      const after = afterSnap?.exists ? afterSnap.data() : null;

      // Delete: the local doc is dropped and Wave is left intact (plan) — no
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
        // The batch fails atomically when the doc was deleted before commit,
        // so fall back to enqueue-only — the worker resolves a missing doc as
        // a clean skip, and any other failure retries via retry:true's
        // idempotent re-run.
        logger.warn("waveUpsertCustomer: batched mark-pending failed; " +
            "enqueueing without it", {clientId, err: e.message});
        await enqueueCustomerUpsert(clientId, {payloadHash: hash});
      }
      logger.debug("waveUpsertCustomer: enqueued", {clientId});
    },
);

// 4) waveSyncWorker — drains the Wave outbox on a schedule, single-instance
// for simple Wave pacing (the lease reaper + transactional claim handle
// robustness); the 5-min cadence at batchLimit 30 keeps calls under 60/min, in
// exchange for syncing within minutes rather than ~1 at ~5x fewer scheduler
// invocations.
//
// timeoutSeconds is raised to 540 since a worst-case drain (up to 30 serial
// jobs, each with Retry-After sleeps of up to 60s × 3 retries) would exceed
// the default 60s; drainQueue also gets a ~70%-of-timeout wall-clock deadline
// so it stops claiming new jobs in time to finish its outcome writes cleanly.
const WORKER_TIMEOUT_SECONDS = 540;
const WORKER_DEADLINE_FRACTION = 0.7;

const waveSyncWorker = onSchedule(
    {
      schedule: "every 5 minutes",
      secrets: [WAVE_FULL_ACCESS_TOKEN],
      maxInstances: 1,
      timeoutSeconds: WORKER_TIMEOUT_SECONDS,
    },
    async () => {
      // Cheap gate: skip the run entirely while Wave is not connected (the
      // cached read avoids a Firestore read every run on idle installs).
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

// 5) waveScheduledImport — daily Wave → App auto-import, running
// importCustomers() only when the configured cadence is due (see
// isImportDue); server-triggered so no App Check/rate limit, and a per-run
// failure just logs (no user to surface it to) and retries the next day.
const waveScheduledImport = onSchedule(
    {
      schedule: "every 24 hours",
      secrets: [WAVE_FULL_ACCESS_TOKEN],
      maxInstances: 1,
      timeoutSeconds: 300,
    },
    async () => {
      const ref = getFirestore().collection("wave").doc("connection");
      const snap = await ref.get();
      const data = snap.exists ? snap.data() : null;
      const businessId = data && typeof data.businessId === "string" ?
        data.businessId : "";
      if (!businessId) {
        logger.debug("waveScheduledImport: not connected — nothing to do");
        return;
      }
      const schedule = data && typeof data.importSchedule === "string" ?
        data.importSchedule : "off";
      const lastAt = data && data.lastAutoImportAt &&
        typeof data.lastAutoImportAt.toMillis === "function" ?
        data.lastAutoImportAt.toMillis() : null;
      if (!isImportDue(schedule, lastAt, Date.now())) {
        logger.debug("waveScheduledImport: not due", {schedule});
        return;
      }

      logger.info("WAVE-SCHED import starting", {businessId, schedule});
      let summary;
      try {
        summary = await importCustomers({businessId, graphql});
      } catch (e) {
        const {code, message} = classifyWaveError(e);
        logger.warn("WAVE-SCHED import failed", {code, message});
        return; // leave lastAutoImportAt unchanged → retried next run
      }

      await ref.update({
        lastAutoImportAt: FieldValue.serverTimestamp(),
      });
      logger.info("WAVE-SCHED import done", {
        imported: summary.imported,
        updated: summary.updated,
        skippedArchived: summary.skippedArchived,
        pages: summary.pages,
      });
    },
);

module.exports = {
  selectBusiness,
  waveBootstrap,
  waveGetConnection,
  waveSetImportSchedule,
  waveImportCustomers,
  waveUpsertCustomer,
  waveScheduledImport,
  waveSyncWorker,
};

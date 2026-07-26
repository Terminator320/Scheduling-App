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

// waveImportCustomers is a heavy one-shot admin op (~650 customers across ~7 Wave
// pages), so a modest cap keeps a stuck/retried admin from hammering Wave.
const WAVE_IMPORT_RATE_MAX = 5;
const WAVE_IMPORT_RATE_WINDOW_MS = 60 * 60 * 1000;
// Caps how many live Wave calls (whoami + listBusinesses) an admin can make.
// The already-connected short-circuit runs first and isn't rate-limited.
const WAVE_BOOTSTRAP_RATE_MAX = 10;

// The Wave business to connect, kept in Secret Manager so the name never
// ships in the app. waveBootstrap uses it whenever the client supplies no
// businessId/businessName.
const WAVE_BUSINESS_NAME = defineSecret("WAVE_BUSINESS_NAME");

// ----- Wave Accounting integration ------------------------------------------
//
// Wires the app's `clients` collection to Wave Accounting customers. The
// `wave/connection` doc holds the selected business id, `waveSyncQueue` is a
// durable outbox drained on a schedule, and these functions are just thin
// wrappers adding auth/admin/rate-limit guards around the `wave/*` modules.

/**
 * Reads the connected Wave `businessId` from the `wave/connection` doc.
 * @return {!Promise<string>} The business id, or "" if not connected.
 */
async function readWaveBusinessId() {
  const snap = await getFirestore().collection("wave").doc("connection").get();
  const data = snap.exists ? snap.data() : null;
  return data && typeof data.businessId === "string" ? data.businessId : "";
}

// Per-instance cache for the scheduled worker's connection gate. A found
// businessId caches for the instance's lifetime; a not-connected result only
// caches for a short TTL, so a fresh bootstrap still gets picked up within a
// few minutes.
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
    // Name match is case-insensitive and whitespace-trimmed, so "acme co"
    // and "  Acme Co  " both match. Id match stays exact since ids are
    // opaque tokens.
    const want = wantName.trim().toLowerCase();
    // We guard `b.name` too — a business with no name would otherwise throw
    // a raw TypeError, which classifyWaveError would turn into a misleading
    // generic Wave failure instead of the intended wave/business-not-found.
    const match = list.find((b) => b && typeof b.name === "string" &&
        b.name.trim().toLowerCase() === want);
    if (!match) throw new HttpsError("not-found", "wave/business-not-found");
    return match;
  }
  if (list.length === 1) return list[0];
  throw new HttpsError("failed-precondition", "wave/business-ambiguous");
}

// waveBootstrap — admin-only, idempotent get-or-create of wave/connection.
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

      // Already-connected doc gets returned unchanged, so this call is safe
      // to make more than once.
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
      // value — the app never names it. The `|| ""` guards against an
      // unset/empty secret throwing on `.trim()`.
      const wantName = (WAVE_BUSINESS_NAME.value() || "").trim();

      // Only the not-yet-connected path (live Wave calls) is rate-limited.
      await enforceDurableRateLimit(
          "wave-bootstrap",
          req.auth.uid,
          WAVE_BOOTSTRAP_RATE_MAX,
          WAVE_IMPORT_RATE_WINDOW_MS,
      );

      // Network calls run outside the transaction — transactions retry, and
      // a Wave mutation must never run twice. whoami() fast-fails a bad
      // token before we bother listing businesses.
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
      // connection — the first writer wins, and later writers just return
      // its value.
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

// waveSetImportSchedule — admin-only setter for the auto-import cadence on
// the wave/connection doc. Just needs App Check + admin, no secret or rate
// limit.
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

// waveImportCustomers — admin-only one-shot Wave → App seed.
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

// waveUpsertCustomer — enqueues a Wave write-back when a client doc's mapped
// fields change. `retry: true` is safe here since the handler is idempotent
// and hash-guarded.
const waveUpsertCustomer = onDocumentWritten(
    {document: "clients/{clientId}", retry: true},
    async (event) => {
      const beforeSnap = event.data?.before;
      const afterSnap = event.data?.after;
      const after = afterSnap?.exists ? afterSnap.data() : null;

      // On delete, the local doc is just dropped and Wave is left intact —
      // nothing to enqueue.
      if (!after) return;

      const before = beforeSnap?.exists ? beforeSnap.data() : null;
      if (!shouldEnqueueClientWrite(before, after)) return;

      // The mark-pending write below only touches wave.* fields, so when
      // the trigger re-fires on it, mappedFieldsHash is unchanged and
      // shouldEnqueueClientWrite returns false — no second pending-write,
      // no loop.
      const clientId = event.params.clientId;
      const db = getFirestore();

      // We compute the hash once here. shouldEnqueueClientWrite also hashes
      // internally but doesn't expose its result, so this is the one
      // explicit hash computed at the enqueue site.
      const hash = mappedFieldsHash(after);

      // Mark-pending + enqueue land in ONE WriteBatch so a crash between the
      // two can't leave the doc stuck at 'pending' with no queued job (or a
      // queued job with no visible pending state).
      const batch = db.batch();
      batch.update(db.doc("clients/" + clientId), {
        "wave.syncState": "pending",
        "wave.syncError": null,
      });
      // payloadHash is diagnostic only — the worker re-reads the live doc
      // and recomputes the hash before writing, since the doc is the real
      // source of truth.
      await enqueueCustomerUpsert(clientId, {batch, payloadHash: hash});
      try {
        await batch.commit();
      } catch (e) {
        // The batch fails atomically when the doc was deleted before
        // commit, so we fall back to enqueue-only. The worker treats a
        // missing doc as a clean skip, and any other failure just retries
        // via retry:true's idempotent re-run.
        logger.warn("waveUpsertCustomer: batched mark-pending failed; " +
            "enqueueing without it", {clientId, err: e.message});
        await enqueueCustomerUpsert(clientId, {payloadHash: hash});
      }
      logger.debug("waveUpsertCustomer: enqueued", {clientId});
    },
);

// waveSyncWorker — drains the Wave outbox on a schedule. It's single-instance
// for simple pacing; the lease reaper and transactional claim are what
// actually handle robustness.
// timeoutSeconds is raised to 540 because a worst-case 30-job drain (with
// Retry-After sleeps) would blow past the default 60s. drainQueue gets a
// deadline at ~70% of the timeout, so it stops claiming new jobs in time to
// finish writing outcomes cleanly.
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
      // Cheap gate that skips the run entirely while Wave isn't connected.
      // The cached read avoids a Firestore read on every run for idle
      // installs.
      const businessId = await readWaveBusinessIdCached();
      if (!businessId) {
        logger.debug("waveSyncWorker: not bootstrapped — nothing to do");
        return;
      }
      // We intentionally don't pass `graphql`/`upsertCustomer` here —
      // drainQueue defaults to the real Wave client, and
      // WAVE_FULL_ACCESS_TOKEN is already in scope via this function's
      // `secrets` binding.
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

// waveScheduledImport — daily Wave → App auto-import, only runs
// importCustomers() when the configured cadence is due. A per-run failure
// just logs and retries the next day.
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

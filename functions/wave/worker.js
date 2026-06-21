"use strict";

/**
 * @fileoverview Wave Accounting outbox worker.
 *
 * Manages the `waveSyncQueue` collection, which acts as a durable outbox for
 * Wave API write-backs. Enqueue a job for a client; the scheduler calls
 * `drainQueue` to claim and execute pending jobs.
 *
 * ## Job document contract (`waveSyncQueue/{jobId}`)
 * ```
 * {
 *   type:           'customerUpsert',
 *   refPath:        'clients/<id>',
 *   payloadHash:    '<hash>|undefined',
 *   attempts:       0,
 *   nextAttemptAt:  <timestamp>,
 *   status:         'queued'|'inflight'|'done'|'dead',
 *   lastError:      string|null,
 *   idempotencyKey: '<string>',
 * }
 * ```
 *
 * ## Claim protocol
 * Each job is claimed transactionally: re-read inside a transaction, skip if
 * not `status=='queued'`, then set `status:'inflight'`. This prevents two
 * worker instances from processing the same job concurrently.
 *
 * ## Retryability taxonomy
 * - `WaveValidationError` — NOT retryable (bad input; dead-letter immediately).
 * - `WaveApiError` kind `rateLimited`|`network` — retryable (transient).
 * - `WaveApiError` kind `auth`|`graphql`|`unknown` — NOT retryable.
 * - Any other (unexpected/infra) error — retryable (bounded by maxAttempts).
 *
 * ## Required Firestore composite index
 * NOTE: `waveSyncQueue` needs a composite index `(status ASC, nextAttemptAt
 * ASC)` for the `drainQueue` query. Add this to `firestore.indexes.json`
 * before deploying and run `firebase deploy --only firestore:indexes`.
 *
 * ## Throughput sizing
 * The drainQueue schedule frequency × batchLimit must stay under Wave's
 * 60-requests-per-minute limit. With the default batchLimit of 30 and a
 * 1-minute schedule cadence, peak throughput is 30/min — safely below 60/min.
 * If you increase batchLimit or run on a shorter cadence, adjust accordingly.
 *
 * @module wave/worker
 */

const {WaveValidationError, upsertCustomer} = require("./customers");
const {WaveApiError} = require("./client");

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

/** Firestore collection that holds outbox jobs. */
const QUEUE_COLLECTION = "waveSyncQueue";

/** Default maximum dispatch attempts per job before dead-lettering. */
const DEFAULT_MAX_ATTEMPTS = 5;

/** Default number of jobs to claim per drainQueue invocation (see note above
 * about throughput sizing). */
const DEFAULT_BATCH_LIMIT = 30;

/** Base delay for exponential backoff in milliseconds (60 seconds). */
const BASE_BACKOFF_MS = 60_000;

/** Maximum backoff delay cap in milliseconds (1 hour). */
const MAX_BACKOFF_MS = 3_600_000;

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

/**
 * Lazily resolves firebase-admin/firestore without touching it at module load
 * (so unit tests that inject deps are never affected).
 * @return {{getFirestore: !Function, FieldValue: !Object, Timestamp: !Object}}
 */
function adminFirestore() {
  // eslint-disable-next-line global-require
  return require("firebase-admin/firestore");
}

/**
 * Default exponential-backoff-with-jitter function.
 * Formula: min(BASE * 2^n, MAX) * (0.75 + random 0..0.25) ms, returned as ms.
 * @param {number} attempts The current attempt count (0-indexed; first retry
 *   is attempts=0 after the initial attempt failed).
 * @return {number} Milliseconds to wait before the next attempt.
 */
function defaultBackoffMs(attempts) {
  const exp = Math.min(BASE_BACKOFF_MS * Math.pow(2, attempts), MAX_BACKOFF_MS);
  return Math.floor(exp * (0.75 + Math.random() * 0.25));
}

/**
 * Returns true when the error is transient and worth retrying.
 *
 * Rules:
 *   - `WaveValidationError` → false (bad input; no retry).
 *   - `WaveApiError` kind `rateLimited`|`network` → true.
 *   - `WaveApiError` kind `auth`|`graphql`|`unknown` → false.
 *   - Everything else (unexpected/infra) → true (bounded by maxAttempts).
 * @param {*} err The caught error.
 * @return {boolean}
 */
function isRetryable(err) {
  if (err instanceof WaveValidationError) return false;
  if (err instanceof WaveApiError) {
    return err.kind === "rateLimited" || err.kind === "network";
  }
  // Unexpected / infra errors: retry (bounded).
  return true;
}

/**
 * Extracts a safe, PII-free error summary for `lastError`. Never logs or
 * stores Wave's raw error message or customer data — only the error class name
 * and (for WaveApiError) the `kind` field.
 * @param {*} err The caught error.
 * @return {string}
 */
function sanitizeError(err) {
  if (err instanceof WaveValidationError) {
    return "WaveValidationError: Wave rejected the customer data.";
  }
  if (err instanceof WaveApiError) {
    return `WaveApiError(${err.kind})`;
  }
  const name = (err && err.name) ? String(err.name) : "Error";
  return `${name}: unexpected error`;
}

/**
 * Extracts the clientId from a `refPath` like `'clients/<id>'`.
 * @param {string} refPath The `refPath` stored in the job doc.
 * @return {string} The client id segment, or empty string on a bad path.
 */
function clientIdFromRefPath(refPath) {
  if (typeof refPath !== "string") return "";
  const parts = refPath.split("/");
  return parts.length >= 2 ? parts[parts.length - 1] : "";
}

// ---------------------------------------------------------------------------
// enqueueCustomerUpsert
// ---------------------------------------------------------------------------

/**
 * Enqueues (or re-enqueues) a `customerUpsert` job for the given client.
 *
 * Uses deterministic dedup: the jobId is always `customerUpsert__<clientId>`,
 * so a burst of client edits collapses into ONE pending job. The doc is
 * written via `set(..., {merge:true})` so a pre-existing job is updated
 * in-place rather than creating a duplicate.
 *
 * Every enqueue resets `attempts:0` and `lastError:null` so a newly-edited
 * client gets a fresh retry budget, regardless of prior failure history.
 *
 * @param {string} clientId Firestore `clients` document id.
 * @param {Object=} deps Injectable dependencies. `db` defaults to
 *   `getFirestore()`; `now` defaults to `FieldValue.serverTimestamp`. Neither
 *   default may be triggered inside a unit test.
 * @return {!Promise<string>} The jobId that was enqueued.
 */
async function enqueueCustomerUpsert(clientId, deps = {}) {
  const db = deps.db || adminFirestore().getFirestore();
  const now = deps.now || adminFirestore().FieldValue.serverTimestamp;

  const jobId = `customerUpsert__${clientId}`;
  const ref = db.collection(QUEUE_COLLECTION).doc(jobId);

  await ref.set(
      {
        type: "customerUpsert",
        refPath: `clients/${clientId}`,
        status: "queued",
        nextAttemptAt: now(),
        idempotencyKey: jobId,
        attempts: 0,
        lastError: null,
      },
      {merge: true},
  );

  return jobId;
}

// ---------------------------------------------------------------------------
// drainQueue
// ---------------------------------------------------------------------------

/**
 * Claims and dispatches pending `waveSyncQueue` jobs.
 *
 * Query: `status == 'queued' AND nextAttemptAt <= now`, ordered by
 * `nextAttemptAt ASC`, limited to `batchLimit`.
 *
 * Each job is claimed transactionally (re-read; skip if not still `queued`;
 * set `inflight`) before dispatch so two concurrent workers can't race on the
 * same job.
 *
 * @param {Object=} deps Injectable dependencies:
 *   - `db` {!Object} Firestore instance (default `getFirestore()`).
 *   - `graphql` {!Function} Wave GraphQL client.
 *   - `businessId` {string} Connected Wave business id.
 *   - `upsertCustomer` {!Function} Override for testing (default: the real
 *     `upsertCustomer` from customers.js).
 *   - `now` {!Function} Returns the current Firestore Timestamp or a plain
 *     Date/number for `nextAttemptAt <= now` comparison.
 *   - `backoffFn` {!Function} `(attempts:number) => number` ms; default:
 *     exponential with jitter, base 60s, cap 1h.
 *   - `maxAttempts` {number} Max retries before dead-lettering (default 5).
 *   - `batchLimit` {number} Max jobs per call (default 30; keep
 *     `schedule_frequency × batchLimit < Wave 60/min` limit).
 *   - `logger` {!Object} Logging facade with `.error(msg, meta)` etc.
 *     Defaults to `firebase-functions/logger`. Never use `console`.
 * @return {!Promise<{processed:number, done:number, retried:number,
 *   dead:number, skipped:number}>} Summary of the drain run.
 */
async function drainQueue(deps = {}) {
  const db = deps.db || adminFirestore().getFirestore();
  // eslint-disable-next-line global-require
  const logger = deps.logger || require("firebase-functions/logger");
  const backoffFn = deps.backoffFn || defaultBackoffMs;
  const maxAttempts =
    typeof deps.maxAttempts === "number" ? deps.maxAttempts :
    DEFAULT_MAX_ATTEMPTS;
  const batchLimit =
    typeof deps.batchLimit === "number" ? deps.batchLimit :
    DEFAULT_BATCH_LIMIT;
  const dispatchUpsert = deps.upsertCustomer || upsertCustomer;
  const nowValue = deps.now ? deps.now() : new Date();

  const summary = {processed: 0, done: 0, retried: 0, dead: 0, skipped: 0};

  // NOTE: `waveSyncQueue` needs a composite index `(status ASC,
  // nextAttemptAt ASC)` — add to firestore.indexes.json before deploying.
  const snap = await db.collection(QUEUE_COLLECTION)
      .where("status", "==", "queued")
      .where("nextAttemptAt", "<=", nowValue)
      .orderBy("nextAttemptAt")
      .limit(batchLimit)
      .get();

  const docs = snap && Array.isArray(snap.docs) ? snap.docs : [];

  for (const doc of docs) {
    const jobId = doc.id;
    const jobData = doc.data() || {};

    // --- Claim the job transactionally ----------------------------------
    let claimed = false;
    try {
      await db.runTransaction(async (tx) => {
        // Reset on each retry so a prior abandoned callback run doesn't bleed.
        claimed = false;
        const fresh = await tx.get(doc.ref);
        if (!fresh || !fresh.exists) return; // deleted between query and claim
        const freshData = fresh.data() || {};
        if (freshData.status !== "queued") return; // already claimed/done
        tx.update(doc.ref, {status: "inflight"});
        claimed = true;
      });
    } catch (txErr) {
      // Transaction failure (contention, etc.) — skip and let the next run
      // retry.
      logger.warn("WAVE-WORKER claim transaction failed", {
        jobId,
        error: sanitizeError(txErr),
      });
      summary.skipped += 1;
      continue;
    }

    if (!claimed) {
      summary.skipped += 1;
      continue;
    }

    summary.processed += 1;

    // --- Dispatch -------------------------------------------------------
    const type = jobData.type;
    let dispatchError = null;

    try {
      if (type === "customerUpsert") {
        const clientId = clientIdFromRefPath(jobData.refPath);
        await dispatchUpsert(clientId, {
          db,
          graphql: deps.graphql,
          businessId: deps.businessId,
        });
      } else {
        // Unknown job type — treat as a permanent failure (non-retryable).
        throw new TypeError(`Unknown job type: ${String(type)}`);
      }
    } catch (err) {
      dispatchError = err;
    }

    // --- Resolve outcome ------------------------------------------------
    if (!dispatchError) {
      // Success.
      await doc.ref.update({
        status: "done",
        lastError: null,
      });
      summary.done += 1;
      continue;
    }

    // Error path — classify and update.
    const retryable = isRetryable(dispatchError);
    const newAttempts = (typeof jobData.attempts === "number" ?
      jobData.attempts : 0) + 1;
    const sanitized = sanitizeError(dispatchError);

    if (retryable && newAttempts < maxAttempts) {
      // Back to queued with backoff.
      const delayMs = backoffFn(newAttempts - 1);
      const nextAttemptAt = new Date(Date.now() + delayMs);

      await doc.ref.update({
        status: "queued",
        attempts: newAttempts,
        nextAttemptAt,
        lastError: sanitized,
      });
      summary.retried += 1;
    } else {
      // Dead-letter: not retryable OR attempts cap reached.
      const clientId = clientIdFromRefPath(jobData.refPath);
      const errKind = (dispatchError instanceof WaveApiError) ?
        dispatchError.kind :
        (dispatchError instanceof WaveValidationError ?
          "validation" : "unexpected");

      logger.error("WAVE-WORKER dead-lettering job", {
        jobId,
        clientId,
        errorClass: dispatchError.constructor ?
          dispatchError.constructor.name : "Error",
        errorKind: errKind,
        attempts: newAttempts,
        retryable,
      });

      await doc.ref.update({
        status: "dead",
        attempts: newAttempts,
        lastError: sanitized,
      });
      summary.dead += 1;
    }
  }

  return summary;
}

module.exports = {enqueueCustomerUpsert, drainQueue};

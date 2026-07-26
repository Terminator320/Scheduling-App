"use strict";

/**
 * @fileoverview Wave Accounting outbox worker.
 *
 * Manages the `waveSyncQueue` collection — a durable outbox for Wave API
 * write-backs — enqueued per client and drained by the scheduler's
 * `drainQueue`.
 *
 * ## Job document contract (`waveSyncQueue/{jobId}`)
 * ```
 * {
 *   type:           'customerUpsert',
 *   refPath:        'clients/<id>',
 *   payloadHash:    '<hash>|undefined',   // written when caller provides it
 *   attempts:       0,
 *   nextAttemptAt:  <timestamp>,
 *   claimedAt:      <timestamp>|undefined, // set on claim; used by reaper
 *   status:         'queued'|'inflight'|'done'|'dead',
 *   lastError:      string|null,
 *   idempotencyKey: '<string>',
 * }
 * ```
 *
 * ## Claim protocol
 * Each job is claimed transactionally (re-read; skip unless still `queued`;
 * set `inflight` + stamp `claimedAt`) so two worker instances can't process
 * the same job concurrently.
 *
 * ## Lease / reclaim protocol
 * The claim and outcome write are separated by a Wave API call, so a dead
 * function instance would strand a job `inflight` forever; the reclaim pass
 * at the start of `drainQueue` finds jobs whose `claimedAt` exceeds
 * `LEASE_MS` and retries/dead-letters them (bumping `attempts`) through the
 * same atomic, re-read-and-rewrite transaction as a normal failure, so a
 * concurrent reclaim or re-enqueue in the same window can't be clobbered.
 *
 * ## Outcome-write guard
 * The outcome write is itself transactional (`commitOutcome`): it commits
 * only while the job is still `inflight` with the same `claimedAt` stamped
 * at claim time, so a client re-enqueue or another worker's re-claim during
 * the in-flight Wave call is skipped instead of clobbered to `done`.
 *
 * ## Retryability taxonomy
 * - `WaveValidationError` — NOT retryable (bad input; dead-letter immediately).
 * - `WaveApiError` kind `rateLimited`|`network` — retryable (transient).
 * - `WaveApiError` kind `graphql` — retryable ONLY when the GraphQL error
 *   looks like a transient server-side failure (Wave returns e.g. internal /
 *   timeout / unavailable errors on HTTP 200); genuine validation / query
 *   errors stay permanent.
 * - `WaveApiError` kind `auth`|`unknown` — NOT retryable.
 * - Any other (unexpected/infra) error — retryable (bounded by maxAttempts).
 *
 * ## Required Firestore composite indexes
 * NOTE: `waveSyncQueue` needs both `(status ASC, nextAttemptAt ASC)` (for `drainQueue`'s
 * queued query) and `(status ASC, claimedAt ASC)` (for the reclaim pass) in
 * `firestore.indexes.json`; run `firebase deploy --only firestore:indexes` after adding them.
 *
 * ## Throughput sizing
 * drainQueue's schedule frequency × batchLimit must stay under Wave's 60/min
 * limit — the default (batchLimit 30, 5-min cadence) peaks at 6/min, so
 * adjust both together if you change either.
 *
 * @module wave/worker
 */

const {WaveValidationError, upsertCustomer} = require("./customers");
const {WaveApiError} = require("./client");
const {mappedFieldsHash} = require("./mappers");

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

/**
 * Default lease duration (10 minutes, comfortably longer than any Cloud
 * Function's max runtime) after which an `inflight` job is assumed lost and
 * reclaimed by the next drainQueue run.
 */
const DEFAULT_LEASE_MS = 600_000;

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
 * Default exponential-backoff-with-jitter: min(BASE * 2^n, MAX) * (0.75 + random 0..0.25) ms.
 * @param {number} attempts The PRE-increment attempt index passed by the
 *   caller (first retry → 0, second → 1, …); it is one less than the
 *   `attempts` value subsequently stored on the job doc.
 * @return {number} Milliseconds to wait before the next attempt.
 */
function defaultBackoffMs(attempts) {
  const exp = Math.min(BASE_BACKOFF_MS * Math.pow(2, attempts), MAX_BACKOFF_MS);
  return Math.floor(exp * (0.75 + Math.random() * 0.25));
}

/**
 * Heuristic: treats a `graphql`-kind WaveApiError as transient (retryable) when its message/extensions.code looks like a server-side failure, since Wave sometimes returns transient errors as GraphQL errors on HTTP 200 (see client.js).
 * @param {!WaveApiError} err A WaveApiError with kind 'graphql'.
 * @return {boolean}
 */
function isTransientGraphqlError(err) {
  const texts = [];
  if (typeof err.message === "string") texts.push(err.message);
  const details = Array.isArray(err.details) ? err.details : [];
  for (const d of details) {
    if (!d) continue;
    if (typeof d.message === "string") texts.push(d.message);
    const code = d.extensions && typeof d.extensions.code === "string" ?
      d.extensions.code : "";
    if (code) texts.push(code);
  }
  const joined = texts.join(" ").toLowerCase();
  const transientRe = new RegExp(
      "internal|timeout|timed out|unavailable|temporar|" +
      "overloaded|service error|try again");
  return transientRe.test(joined);
}

/**
 * Returns true when the error is transient and worth retrying.
 *
 * Rules:
 *   - `WaveValidationError` → false (bad input; no retry).
 *   - `WaveApiError` kind `rateLimited`|`network` → true.
 *   - `WaveApiError` kind `graphql` → true only for transient-looking
 *     server-side errors (see `isTransientGraphqlError`); validation/query
 *     errors stay permanent.
 *   - `WaveApiError` kind `auth`|`unknown` → false.
 *   - Everything else (unexpected/infra) → true (bounded by maxAttempts).
 * @param {*} err The caught error.
 * @return {boolean}
 */
function isRetryable(err) {
  if (err instanceof WaveValidationError) return false;
  if (err instanceof WaveApiError) {
    if (err.kind === "rateLimited" || err.kind === "network") return true;
    if (err.kind === "graphql") return isTransientGraphqlError(err);
    return false;
  }
  // Unexpected / infra errors: retry (bounded).
  return true;
}

/**
 * Extracts a safe, PII-free error summary for `lastError` — only the error class name and (for WaveApiError) its `kind`, never Wave's raw message or customer data.
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
 * Best-effort: flags the client doc behind a dead-lettered job with a sanitized sync error (so admins see `error` instead of forever-`pending`); never throws, since the job doc's `dead` status is the durable source of truth.
 * @param {!Object} db Firestore instance.
 * @param {string} refPath The job's `refPath` (`'clients/<id>'`).
 * @param {string} message Sanitized, PII-free error summary.
 * @param {!Object} logger Logging facade.
 * @return {!Promise<void>}
 */
async function markClientSyncError(db, refPath, message, logger) {
  const clientId = clientIdFromRefPath(refPath);
  if (!clientId) return;
  try {
    await db.collection("clients").doc(clientId).update({
      "wave.syncState": "error",
      "wave.syncError": message,
    });
  } catch (err) {
    logger.warn("WAVE-WORKER could not mark client sync error", {
      clientId,
      error: sanitizeError(err),
    });
  }
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

/**
 * Converts a Firestore timestamp-ish value (Date, Timestamp, or number) to epoch milliseconds, returning NaN for anything non-numeric (e.g. a serverTimestamp sentinel).
 * @param {*} value
 * @return {number} Epoch ms, or NaN.
 */
function timestampToMs(value) {
  if (value instanceof Date) return value.getTime();
  if (value && typeof value.toMillis === "function") return value.toMillis();
  if (value && typeof value.toDate === "function") {
    return value.toDate().getTime();
  }
  const n = Number(value);
  return Number.isFinite(n) ? n : NaN;
}

/**
 * Whether two `claimedAt` stamps identify the same claim — compares by epoch ms when both are real timestamps, else falls back to strict identity (e.g. a test serverTimestamp sentinel).
 * @param {*} a
 * @param {*} b
 * @return {boolean}
 */
function sameClaim(a, b) {
  const am = timestampToMs(a);
  const bm = timestampToMs(b);
  if (Number.isFinite(am) && Number.isFinite(bm)) return am === bm;
  return a === b;
}

/**
 * Atomically writes a claimed job's terminal/retry outcome only while this worker still owns the claim (same `inflight` status and `claimedAt`), so a concurrent re-enqueue during the Wave call is left alone instead of clobbered to `done`.
 * @param {!Object} db Firestore instance.
 * @param {!Object} ref The job document ref.
 * @param {*} claimStamp The `claimedAt` value written when the job was claimed.
 * @param {!Object} update The outcome fields to write when still owned.
 * @return {!Promise<boolean>} True if the outcome was written.
 */
async function commitOutcome(db, ref, claimStamp, update) {
  let applied = false;
  await db.runTransaction(async (tx) => {
    applied = false; // reset per retry of the transaction callback
    const fresh = await tx.get(ref);
    if (!fresh || !fresh.exists) return;
    const freshData = fresh.data() || {};
    if (freshData.status !== "inflight") return;
    if (!sameClaim(freshData.claimedAt, claimStamp)) return;
    tx.update(ref, update);
    applied = true;
  });
  return applied;
}

// ---------------------------------------------------------------------------
// shouldEnqueueClientWrite
// ---------------------------------------------------------------------------

/**
 * Decides whether a `clients/{id}` write should enqueue a Wave customer-upsert job; pure (hash comparison only) so it's unit-testable in isolation — the `onDocumentWritten` trigger in `index.js` calls it with the before/after document data.
 *
 * Skips a pointless no-op job when the mapped fields are unchanged from `before`
 * (catches the worker's own write-back echo) or already match
 * `after.wave.lastSyncedHash` (catches the import's full-doc writes). A create
 * (`before == null`) is enqueued unless that same synced-hash check already covers it.
 *
 * @param {Object|null|undefined} before Pre-write client document data
 *   (null/undefined on a create).
 * @param {Object|null|undefined} after Post-write client document data;
 *   callers must not invoke this for a delete (after absent) — that path
 *   returns early in the trigger.
 * @return {boolean} True when a job should be enqueued.
 */
function shouldEnqueueClientWrite(before, after) {
  const afterData = after || {};
  const afterHash = mappedFieldsHash(afterData);

  // Rule 1: mapped fields unchanged vs. before → wave-only/unmapped change.
  if (before && afterHash === mappedFieldsHash(before)) {
    return false;
  }

  // Rule 2: mapped fields already equal the last synced hash → no-op.
  const wave = (afterData.wave && typeof afterData.wave === "object") ?
    afterData.wave : {};
  if (afterHash === wave.lastSyncedHash) {
    return false;
  }

  return true;
}

// ---------------------------------------------------------------------------
// enqueueCustomerUpsert
// ---------------------------------------------------------------------------

/**
 * Uses a deterministic jobId (`customerUpsert__<clientId>`) written via `set(..., {merge:true})`, so a burst of client edits collapses into one updated-in-place job.
 *
 * Every enqueue resets `attempts:0` and `lastError:null` so a newly-edited
 * client gets a fresh retry budget, regardless of prior failure history.
 *
 * @param {string} clientId Firestore `clients` document id.
 * @param {Object=} deps Injectable dependencies: `db`/`now` default to
 *   `getFirestore()`/`FieldValue.serverTimestamp` (never triggered in unit
 *   tests); optional `payloadHash` is written to the job doc when provided;
 *   optional `batch` (a Firestore WriteBatch) stages the enqueue on the
 *   caller's batch instead of writing immediately, so it can be paired
 *   atomically with other writes (e.g. the waveUpsertCustomer trigger's
 *   mark-pending update).
 * @return {!Promise<string>} The jobId that was enqueued (or staged).
 */
async function enqueueCustomerUpsert(clientId, deps = {}) {
  const db = deps.db || adminFirestore().getFirestore();
  const now = deps.now || adminFirestore().FieldValue.serverTimestamp;

  const jobId = `customerUpsert__${clientId}`;
  const ref = db.collection(QUEUE_COLLECTION).doc(jobId);

  const docData = {
    type: "customerUpsert",
    refPath: `clients/${clientId}`,
    status: "queued",
    nextAttemptAt: now(),
    idempotencyKey: jobId,
    attempts: 0,
    lastError: null,
  };

  if (deps.payloadHash !== undefined) {
    docData.payloadHash = deps.payloadHash;
  }

  if (deps.batch) {
    deps.batch.set(ref, docData, {merge: true});
  } else {
    await ref.set(docData, {merge: true});
  }

  return jobId;
}

// ---------------------------------------------------------------------------
// drainQueue phases
// ---------------------------------------------------------------------------

/**
 * @typedef {{
 *   db: !Object,
 *   logger: !Object,
 *   backoffFn: !Function,
 *   maxAttempts: number,
 *   batchLimit: number,
 *   leaseMs: number,
 *   deadlineMs: number,
 *   pastDeadline: !Function,
 *   nowValue: *,
 *   nowMs: number,
 *   nowFn: (!Function|undefined),
 *   dispatchUpsert: !Function,
 *   graphql: (!Function|undefined),
 *   businessId: (string|undefined),
 *   summary: !Object
 * }} DrainContext
 */

/**
 * Reclaim pass: fixes jobs stuck `inflight` because the function died between claim and outcome write, by re-reading and rewriting each stale job in ONE transaction so a concurrent reclaim/re-enqueue is left untouched instead of clobbered.
 *
 * NOTE: requires a composite index `(status ASC, claimedAt ASC)` on
 * `waveSyncQueue` — add to firestore.indexes.json before deploying.
 *
 * @param {!DrainContext} ctx Shared drain state; `ctx.summary` is mutated.
 * @return {!Promise<void>}
 */
async function reclaimStaleJobs(ctx) {
  const {
    db, logger, backoffFn, maxAttempts, batchLimit, leaseMs, deadlineMs,
    pastDeadline, nowMs, summary,
  } = ctx;

  const leaseThreshold = new Date(nowMs - leaseMs);
  const staleSnap = await db.collection(QUEUE_COLLECTION)
      .where("status", "==", "inflight")
      .where("claimedAt", "<=", leaseThreshold)
      .limit(batchLimit)
      .get();

  const staleDocs = staleSnap && Array.isArray(staleSnap.docs) ?
    staleSnap.docs : [];

  for (const staleDoc of staleDocs) {
    if (pastDeadline()) {
      logger.warn("WAVE-WORKER deadline budget reached during reclaim", {
        deadlineMs,
      });
      break;
    }
    const jobId = staleDoc.id;
    // Atomic reclaim: re-reads and rewrites the job in ONE transaction,
    // writing only while still inflight past its lease, so a concurrent
    // reclaim or re-enqueue is left untouched instead of clobbered; `outcome`
    // carries the result out for logging.
    let outcome = null;

    try {
      await db.runTransaction(async (tx) => {
        outcome = null; // reset per transaction retry
        const fresh = await tx.get(staleDoc.ref);
        if (!fresh || !fresh.exists) return;
        const freshData = fresh.data() || {};
        // Only reclaims if still inflight and past the lease (a fresh
        // re-claim resets claimedAt and is skipped); a non-finite claimedAt
        // is treated as reclaimable, since skipping it would strand the job
        // forever.
        if (freshData.status !== "inflight") return;
        const claimedAtMs = timestampToMs(freshData.claimedAt);
        if (Number.isFinite(claimedAtMs) && claimedAtMs > nowMs - leaseMs) {
          return;
        }

        const newAttempts =
          (typeof freshData.attempts === "number" ?
            freshData.attempts : 0) + 1;
        const sanitized = "reclaimed: lease expired";

        if (newAttempts < maxAttempts) {
          const delayMs = backoffFn(newAttempts - 1);
          tx.update(staleDoc.ref, {
            status: "queued",
            attempts: newAttempts,
            nextAttemptAt: new Date(nowMs + delayMs),
            lastError: sanitized,
          });
          outcome = {dead: false, newAttempts};
        } else {
          tx.update(staleDoc.ref, {
            status: "dead",
            attempts: newAttempts,
            lastError: sanitized,
          });
          outcome = {
            dead: true,
            newAttempts,
            refPath: freshData.refPath,
            clientId: clientIdFromRefPath(freshData.refPath),
          };
        }
      });
    } catch (txErr) {
      logger.warn("WAVE-WORKER reclaim transaction failed", {
        jobId,
        error: sanitizeError(txErr),
      });
      continue;
    }

    // No outcome → the job was no longer a stale inflight (re-enqueued or
    // re-claimed in the window); leave it for the owning path to resolve.
    if (!outcome) continue;

    if (outcome.dead) {
      logger.error("WAVE-WORKER dead-lettering reclaimed job", {
        jobId,
        clientId: outcome.clientId,
        attempts: outcome.newAttempts,
        reason: "reclaimed: lease expired",
      });
      // Surface the terminal failure on the client doc (best-effort) so the
      // admin UI shows 'error' instead of a forever-'pending' sync state.
      await markClientSyncError(
          db, outcome.refPath, "Sync failed after repeated attempts.", logger,
      );
    }
    summary.reclaimed += 1;
  }
}

/**
 * Main drain: claims queued jobs transactionally (re-read; skip unless still `queued`; set `inflight` + stamp `claimedAt`) before dispatch, and writes every outcome through `commitOutcome` so a concurrent re-enqueue is never clobbered.
 *
 * NOTE: `waveSyncQueue` needs a composite index `(status ASC,
 * nextAttemptAt ASC)` — add to firestore.indexes.json before deploying.
 *
 * @param {!DrainContext} ctx Shared drain state; `ctx.summary` is mutated.
 * @return {!Promise<void>}
 */
async function dispatchQueuedJobs(ctx) {
  const {
    db, logger, backoffFn, maxAttempts, batchLimit, deadlineMs, pastDeadline,
    nowValue, nowMs, nowFn, dispatchUpsert, summary,
  } = ctx;

  const snap = await db.collection(QUEUE_COLLECTION)
      .where("status", "==", "queued")
      .where("nextAttemptAt", "<=", nowValue)
      .orderBy("nextAttemptAt")
      .limit(batchLimit)
      .get();

  const docs = snap && Array.isArray(snap.docs) ? snap.docs : [];

  for (const doc of docs) {
    // Wall-clock budget: stop CLAIMING new jobs once the deadline passes so
    // the function returns with clean outcome writes instead of being killed
    // mid-dispatch (unclaimed jobs stay queued for the next run).
    if (pastDeadline()) {
      logger.warn("WAVE-WORKER deadline budget reached — stopping early", {
        deadlineMs,
        remainingJobs: docs.length - summary.processed - summary.skipped,
      });
      break;
    }

    const jobId = doc.id;
    const jobData = doc.data() || {};

    // --- Claim the job transactionally ----------------------------------
    // The claim stamp is the ACTUAL claim time (not the drain-start clock):
    // with a stale stamp, a long drain could make a job look lease-expired
    // to a concurrent reclaim pass while it is still being dispatched.
    const claimStamp = nowFn ? nowFn() : new Date();
    let claimed = false;
    try {
      await db.runTransaction(async (tx) => {
        // Reset on each retry so a prior abandoned callback run doesn't bleed.
        claimed = false;
        const fresh = await tx.get(doc.ref);
        if (!fresh || !fresh.exists) return; // deleted between query and claim
        const freshData = fresh.data() || {};
        if (freshData.status !== "queued") return; // already claimed/done
        tx.update(doc.ref, {status: "inflight", claimedAt: claimStamp});
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
          graphql: ctx.graphql,
          businessId: ctx.businessId,
          // Lets the upsert run its crash-retry duplicate check (search Wave
          // before creating) when a previous attempt may have half-finished.
          priorAttempts:
            typeof jobData.attempts === "number" ? jobData.attempts : 0,
        });
      } else {
        // Unknown job type — treat as a permanent failure (non-retryable).
        throw new TypeError(`Unknown job type: ${String(type)}`);
      }
    } catch (err) {
      dispatchError = err;
    }

    // --- Resolve outcome (guarded against a concurrent re-enqueue) -------
    if (!dispatchError) {
      // Success.
      const applied = await commitOutcome(db, doc.ref, claimStamp, {
        status: "done",
        lastError: null,
      });
      if (applied) {
        summary.done += 1;
      } else {
        logger.info("WAVE-WORKER outcome superseded (done skipped)", {jobId});
      }
      continue;
    }

    // Error path — classify and update.
    const retryable = isRetryable(dispatchError);
    const newAttempts = (typeof jobData.attempts === "number" ?
      jobData.attempts : 0) + 1;
    const sanitized = sanitizeError(dispatchError);

    if (retryable && newAttempts < maxAttempts) {
      // Back to queued with backoff, using the injected clock so retry time
      // stays testable and consistent with the query's `nowValue`.
      const delayMs = backoffFn(newAttempts - 1);
      const nextAttemptAt = new Date(nowMs + delayMs);

      const applied = await commitOutcome(db, doc.ref, claimStamp, {
        status: "queued",
        attempts: newAttempts,
        nextAttemptAt,
        lastError: sanitized,
      });
      if (applied) {
        summary.retried += 1;
      } else {
        logger.info("WAVE-WORKER outcome superseded (retry skipped)", {jobId});
      }
    } else {
      // Dead-letter: not retryable OR attempts cap reached.
      const clientId = clientIdFromRefPath(jobData.refPath);
      const errKind = (dispatchError instanceof WaveApiError) ?
        dispatchError.kind :
        (dispatchError instanceof WaveValidationError ?
          "validation" : "unexpected");

      const applied = await commitOutcome(db, doc.ref, claimStamp, {
        status: "dead",
        attempts: newAttempts,
        lastError: sanitized,
      });
      if (applied) {
        logger.error("WAVE-WORKER dead-lettering job", {
          jobId,
          clientId,
          errorClass: dispatchError.constructor ?
            dispatchError.constructor.name : "Error",
          errorKind: errKind,
          attempts: newAttempts,
          retryable,
        });
        // Surfaces the terminal failure on the client doc (best-effort) so
        // the admin UI shows 'error' instead of forever-'pending'; skipped
        // for WaveValidationError, which already wrote a richer message via
        // writeSyncError in customers.js.
        if (!(dispatchError instanceof WaveValidationError)) {
          await markClientSyncError(db, jobData.refPath, sanitized, logger);
        }
        summary.dead += 1;
      } else {
        logger.info("WAVE-WORKER outcome superseded (dead skipped)", {jobId});
      }
    }
  }
}

// ---------------------------------------------------------------------------
// drainQueue
// ---------------------------------------------------------------------------

/**
 * Claims and dispatches pending `waveSyncQueue` jobs: a reclaim pass first
 * retries/dead-letters jobs left `inflight` past `leaseMs` (a crashed
 * instance), then claims due `queued` jobs (`nextAttemptAt <= now`, ordered,
 * limited to `batchLimit`) transactionally so concurrent workers can't race
 * the same job.
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
 *   - `leaseMs` {number} Inflight lease duration in ms (default 600000 / 10
 *     min); jobs still inflight this long are reclaimed, so it must exceed
 *     the function's maximum runtime to avoid reclaiming live jobs.
 *   - `deadlineMs` {number} Wall-clock epoch-ms budget — no new job is
 *     claimed past it (in-flight work still finishes and commits); defaults
 *     to Infinity, and the scheduler passes ~70% of its timeout so the run
 *     ends with clean outcome writes instead of being killed mid-dispatch.
 *   - `wallClock` {!Function} Returns the current epoch ms (default
 *     `Date.now`); injectable for deadline tests.
 *   - `logger` {!Object} Logging facade with `.error(msg, meta)` etc.,
 *     defaulting to `firebase-functions/logger` (never `console`).
 * @return {!Promise<{processed:number, done:number, retried:number,
 *   dead:number, skipped:number, reclaimed:number}>} Summary of the drain run.
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
  const leaseMs =
    typeof deps.leaseMs === "number" ? deps.leaseMs : DEFAULT_LEASE_MS;
  const deadlineMs =
    typeof deps.deadlineMs === "number" ? deps.deadlineMs : Infinity;
  const wallClock = deps.wallClock || Date.now;
  const dispatchUpsert = deps.upsertCustomer || upsertCustomer;
  const nowValue = deps.now ? deps.now() : new Date();
  const nowMs = +nowValue;

  // True once the wall-clock budget is exhausted (logged once).
  const pastDeadline = () => wallClock() > deadlineMs;

  const summary = {
    processed: 0, done: 0, retried: 0, dead: 0, skipped: 0, reclaimed: 0,
  };

  const ctx = {
    db, logger, backoffFn, maxAttempts, batchLimit, leaseMs, deadlineMs,
    pastDeadline, nowValue, nowMs, nowFn: deps.now, dispatchUpsert,
    graphql: deps.graphql, businessId: deps.businessId, summary,
  };

  await reclaimStaleJobs(ctx);
  await dispatchQueuedJobs(ctx);

  return summary;
}

module.exports = {
  enqueueCustomerUpsert,
  drainQueue,
  shouldEnqueueClientWrite,
};

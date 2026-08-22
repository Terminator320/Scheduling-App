"use strict";

/**
 * @fileoverview Pure retry taxonomy for the Wave outbox worker.
 *
 * These decide whether a real client edit reaches Wave or is dead-lettered
 * forever, and a `dead` job never retries — it is only visible as an error
 * badge on the client and in `pushedFailed` if an admin happens to press Sync.
 * They lived inside `worker.js`, where they were reachable only through that
 * module's Firestore-mock harness; this is the same pure-sibling split
 * `notification_policy.js` ↔ `notification_utils.js` and
 * `maintenance_policy.js` ↔ `maintenance.js` already use, and like those it
 * takes NO `deps` — no db, no logger, no clock.
 *
 * `worker.js` re-exports `RATE_LIMITED_MAX_ATTEMPTS`, so nothing outside this
 * pair had to change. Add a new retry rule here and re-export it there, rather
 * than growing the orchestration file back.
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
 * @module wave/retry_policy
 */

const {WaveValidationError} = require("./customers");
const {WaveApiError} = require("./client");

/** Default maximum dispatch attempts per job before dead-lettering. */
const DEFAULT_MAX_ATTEMPTS = 5;

/**
 * Attempt budget for a job whose last failure was Wave RATE-LIMITING us.
 *
 * A rate-limit is not the job's fault and says nothing about whether its
 * payload can ever succeed — it means we asked too fast. Spending the ordinary
 * 5-attempt budget on it dead-letters a perfectly valid client edit, and a
 * `dead` job never retries: it is only visible as an error badge on the client
 * and in `pushedFailed` if an admin happens to press Sync. Bursts are a real
 * shape here (a bulk backfill enqueues a few hundred jobs, each pushed by its
 * own `waveUpsertCustomer` invocation), so this budget has to outlast one.
 *
 * Still bounded rather than infinite: `defaultBackoffMs` caps at
 * MAX_BACKOFF_MS (1 h), so 20 attempts is on the order of half a day of
 * retrying before we admit something is structurally wrong.
 */
const RATE_LIMITED_MAX_ATTEMPTS = 20;

/** Base delay for exponential backoff in milliseconds (60 seconds). */
const BASE_BACKOFF_MS = 60_000;

/** Maximum backoff delay cap in milliseconds (1 hour). */
const MAX_BACKOFF_MS = 3_600_000;

/**
 * Default exponential-backoff-with-jitter:
 * min(BASE * 2^n, MAX) * (0.75 + random 0..0.25) ms.
 * @param {number} attempts The PRE-increment attempt index passed by the
 *   caller (first retry → 0, second → 1, …). It's one less than the
 *   `attempts` value that later gets stored on the job doc.
 * @return {number} Milliseconds to wait before the next attempt.
 */
function defaultBackoffMs(attempts) {
  const exp = Math.min(BASE_BACKOFF_MS * Math.pow(2, attempts), MAX_BACKOFF_MS);
  return Math.floor(exp * (0.75 + Math.random() * 0.25));
}

/**
 * Treats a `graphql`-kind WaveApiError as transient (retryable) when its
 * message/extensions.code looks like a server-side failure — Wave sometimes
 * reports what are really transient errors as GraphQL errors on an HTTP 200
 * (see client.js), so this is a best-effort heuristic to catch those.
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
 * The attempt budget to judge THIS failure against.
 *
 * Keyed on the error rather than stored on the job, so it needs no schema
 * change and no migration: a job that was rate-limited four times and then
 * hits a genuine error is judged on the ordinary budget for that error, which
 * is the honest reading — four failures are four failures once one of them is
 * the job's own fault.
 *
 * @param {*} err The caught dispatch error.
 * @param {number} maxAttempts The configured ordinary budget.
 * @return {number} The budget this failure is measured against.
 */
function attemptBudgetFor(err, maxAttempts) {
  const rateLimited = err instanceof WaveApiError && err.kind === "rateLimited";
  // Never BELOW the configured budget: a caller that raised maxAttempts for a
  // one-off drain must not have it silently lowered by this.
  return rateLimited ?
    Math.max(maxAttempts, RATE_LIMITED_MAX_ATTEMPTS) :
    maxAttempts;
}

/**
 * Extracts a safe, PII-free error summary for `lastError` — only the error
 * class name and (for WaveApiError) its `kind`, never Wave's raw message or
 * customer data.
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

/** Caps on the diagnostic below, so one pathological error can't flood a log
 * line: how many distinct items of each kind, and the overall length. */
const DESCRIBE_MAX_ITEMS = 5;
const DESCRIBE_MAX_LENGTH = 300;

/**
 * De-duplicated, capped, joined list of non-empty strings.
 * @param {!Array<string>} values
 * @return {string} Comma-joined, or empty when there is nothing to say.
 */
function joinCapped(values) {
  const seen = [];
  for (const v of values) {
    if (!v || seen.includes(v)) continue;
    seen.push(v);
    if (seen.length >= DESCRIBE_MAX_ITEMS) break;
  }
  return seen.join(",");
}

/**
 * A PII-free descriptor of WHY Wave refused, for the dead-letter LOG ONLY.
 *
 * [sanitizeError] deliberately reduces every transport failure to
 * `WaveApiError(graphql)`, and that string is what lands in the job's
 * `lastError` and the client's `wave.syncError`. It is the right thing to
 * store — those are read by the app — but it left NOWHERE in the system
 * recording the actual reason: not the log, not the job, not the client badge.
 * A permanently-dead client edit was, by construction, undiagnosable, and the
 * only recovery action ("Retry failed") re-sent the identical payload and
 * dead-lettered it identically.
 *
 * What it takes is bounded to schema-level identifiers, never customer data:
 *   - `extensions.code` — Wave's own error vocabulary
 *     (e.g. `GRAPHQL_VALIDATION_FAILED`).
 *   - the error `path`, and any `at "input.address.countryCode"` fragment,
 *     which names the FIELD at fault. The quoted run captured is only the one
 *     following `at`; the offending VALUE, which the same message quotes
 *     right before it, is never taken.
 *   - `Expected type <T>` — a GraphQL type name.
 *
 * Everything else, including Wave's raw message text, stays out.
 *
 * @param {*} err The caught error.
 * @return {string} A short descriptor, or '' when there is nothing safe to
 *   add beyond what [sanitizeError] already says.
 */
function describeWaveError(err) {
  if (!(err instanceof WaveApiError)) return "";
  const details = Array.isArray(err.details) ? err.details : [];
  const codes = [];
  const fields = [];
  const types = [];
  const messages = [];
  if (typeof err.message === "string") messages.push(err.message);

  for (const d of details) {
    if (!d) continue;
    const code = d.extensions && typeof d.extensions.code === "string" ?
      d.extensions.code : "";
    if (code) codes.push(code);
    if (Array.isArray(d.path)) fields.push(d.path.join("."));
    if (typeof d.message === "string") messages.push(d.message);
  }

  for (const m of messages) {
    for (const hit of m.matchAll(/\bat "([A-Za-z0-9_.[\]]+)"/g)) {
      fields.push(hit[1]);
    }
    for (const hit of m.matchAll(/\bExpected type ([A-Za-z0-9_]+)/g)) {
      types.push(hit[1]);
    }
  }

  const parts = [];
  const codeList = joinCapped(codes);
  if (codeList) parts.push(`codes=[${codeList}]`);
  const fieldList = joinCapped(fields);
  if (fieldList) parts.push(`fields=[${fieldList}]`);
  const typeList = joinCapped(types);
  if (typeList) parts.push(`expected=[${typeList}]`);
  return parts.join(" ").slice(0, DESCRIBE_MAX_LENGTH);
}

/** The `lastError` a lease-expiry reclaim stamps. Sanitized by construction. */
const RECLAIM_REASON = "reclaimed: lease expired";

/**
 * What to do with a job whose lease has expired — retry it or dead-letter it.
 *
 * Pure, and here rather than inside the transaction closure it is called from,
 * because all three of its outcomes DESTROY something: a skip leaves a job for
 * another path to own, a retry rewrites its schedule, and a dead-letter ends a
 * real client edit's journey to Wave permanently. A decision reachable only
 * through a Firestore-transaction mock is a decision nobody re-reads.
 *
 * [job] is already NORMALIZED by the caller — `claimedAtMs` resolved to a
 * number — which is what keeps this module free of Firestore types.
 *
 * @param {{status: string, claimedAtMs: number, attempts: *}} job
 * @param {{nowMs: number, leaseMs: number, maxAttempts: number,
 *   backoffFn: function(number): number}} options
 * @return {?{patch: !Object, dead: boolean, attempts: number}} Null to leave
 *   the job alone.
 */
function reclaimDecision(job, options) {
  const {nowMs, leaseMs, maxAttempts, backoffFn} = options;
  if (!job || job.status !== "inflight") return null;

  // A fresh re-claim resets `claimedAt`, so a job claimed inside the lease is
  // somebody else's and gets skipped. A NON-FINITE `claimedAt` (an unresolved
  // serverTimestamp sentinel) is treated as reclaimable on purpose: skipping
  // it would strand the job forever, which is the worse of the two failures.
  if (Number.isFinite(job.claimedAtMs) && job.claimedAtMs > nowMs - leaseMs) {
    return null;
  }

  const attempts =
    (typeof job.attempts === "number" ? job.attempts : 0) + 1;

  if (attempts < maxAttempts) {
    return {
      patch: {
        status: "queued",
        attempts,
        nextAttemptAt: new Date(nowMs + backoffFn(attempts - 1)),
        lastError: RECLAIM_REASON,
      },
      dead: false,
      attempts,
    };
  }

  return {
    patch: {status: "dead", attempts, lastError: RECLAIM_REASON},
    dead: true,
    attempts,
  };
}

module.exports = {
  DEFAULT_MAX_ATTEMPTS,
  RATE_LIMITED_MAX_ATTEMPTS,
  BASE_BACKOFF_MS,
  MAX_BACKOFF_MS,
  defaultBackoffMs,
  isTransientGraphqlError,
  isRetryable,
  attemptBudgetFor,
  sanitizeError,
  describeWaveError,
  RECLAIM_REASON,
  reclaimDecision,
};

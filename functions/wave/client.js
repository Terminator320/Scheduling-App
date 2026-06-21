"use strict";

/**
 * @fileoverview GraphQL transport client for the Wave Accounting public API.
 *
 * All network I/O is funnelled through `graphql()`. Every argument value
 * travels in `variables` — values are never string-interpolated into the
 * query document (Wave rejects inline String-typed args and this keeps the
 * calls injection-safe).
 *
 * Retry policy (exponential backoff + jitter):
 *   - 429 Too Many Requests: respect `Retry-After` header when present.
 *   - 5xx / fetch rejection (network): retry with backoff.
 *   - 401 / 403: throw immediately — no retry (token missing or revoked).
 *   - Any other non-2xx: throw immediately.
 *
 * All retry parameters and I/O dependencies are injectable via the `options`
 * bag so unit tests can run instantly without real network or secrets.
 *
 * @module wave/client
 */

const WAVE_GQL_URL = "https://gql.waveapps.com/graphql/public";

// Default retry settings. Override via options.maxRetries / options.sleepFn.
const DEFAULT_MAX_RETRIES = 3;
const BASE_DELAY_MS = 500;
const MAX_DELAY_MS = 10_000;

// ---------------------------------------------------------------------------
// WaveApiError
// ---------------------------------------------------------------------------

/**
 * Structured error thrown by all Wave client functions.
 *
 * `kind` values:
 *   - `'auth'`        — 401/403; token missing or revoked.
 *   - `'rateLimited'` — 429 persisting after all retries.
 *   - `'network'`     — 5xx or fetch rejection persisting after all retries.
 *   - `'graphql'`     — HTTP 200 but the body carries a top-level `errors`
 *                       array (GraphQL transport / resolver errors).
 *   - `'unknown'`     — Unexpected HTTP status with no matching category.
 */
class WaveApiError extends Error {
  /**
   * @param {string} kind Error category (see jsdoc above).
   * @param {string} message Human-readable description.
   * @param {*=} details Optional raw details (error array, status code, etc.).
   */
  constructor(kind, message, details) {
    super(message);
    this.name = "WaveApiError";
    /** @type {string} */
    this.kind = kind;
    /** @type {*} */
    this.details = details;
  }
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

/**
 * Returns a delay in milliseconds for retry attempt `n` (0-indexed).
 * Formula: min(BASE * 2^n, MAX) * (0.5 + random 0..0.5) for jitter.
 * @param {number} n Attempt index (0 = first retry).
 * @return {number} Delay in milliseconds.
 */
function backoffMs(n) {
  const exp = Math.min(BASE_DELAY_MS * Math.pow(2, n), MAX_DELAY_MS);
  return Math.floor(exp * (0.5 + Math.random() * 0.5));
}

/**
 * Parses the `Retry-After` header value into a millisecond delay.
 * Handles both the integer-seconds form and the HTTP-date form.
 * Returns `null` when the header is absent or unparseable.
 * @param {Headers} headers Response headers.
 * @return {number|null}
 */
function retryAfterMs(headers) {
  const raw = headers.get("retry-after");
  if (!raw) return null;
  const secs = Number(raw.trim());
  if (!isNaN(secs) && secs >= 0) return secs * 1000;
  const date = Date.parse(raw);
  if (!isNaN(date)) return Math.max(0, date - Date.now());
  return null;
}

/**
 * Returns a Promise that resolves after `ms` milliseconds using `sleepFn`.
 * @param {function(number): Promise<void>} sleepFn Injected delay function.
 * @param {number} ms Milliseconds to wait.
 * @return {!Promise<void>}
 */
function sleep(sleepFn, ms) {
  return sleepFn(ms);
}

// ---------------------------------------------------------------------------
// Core transport
// ---------------------------------------------------------------------------

/**
 * Posts a GraphQL request to the Wave public API and returns `body.data`.
 *
 * @param {string} query GraphQL query or mutation document string.
 * @param {!Object=} variables GraphQL variables (all argument values go here
 *   — never string-interpolate values into `query`).
 * @param {Object=} options Dependency-injection bag. Accepts: token (string),
 *   fetchImpl (function), sleepFn (function), maxRetries (number). Defaults
 *   use getWaveToken(), global.fetch, a setTimeout-based delay, and 3 retries.
 * @return {!Promise<*>} The `data` field of a successful GraphQL response.
 * @throws {WaveApiError}
 */
async function graphql(query, variables = {}, options = {}) {
  const {getWaveToken} = require("./auth");
  const token = options.token !== undefined ? options.token : getWaveToken();
  const fetchImpl = options.fetchImpl || global.fetch;
  const maxRetries = options.maxRetries !== undefined ?
    options.maxRetries : DEFAULT_MAX_RETRIES;
  const sleepFn = options.sleepFn || ((ms) =>
    new Promise((resolve) => setTimeout(resolve, ms)));

  const requestBody = JSON.stringify({query, variables});
  const requestHeaders = {
    "Authorization": `Bearer ${token}`,
    "Content-Type": "application/json",
  };

  let attempt = 0;
  // `attempt` counts total tries; we allow up to maxRetries retries after the
  // first attempt, so the loop runs at most maxRetries + 1 times.
  for (;;) {
    let response;
    let fetchError = null;

    try {
      response = await fetchImpl(WAVE_GQL_URL, {
        method: "POST",
        headers: requestHeaders,
        body: requestBody,
      });
    } catch (err) {
      fetchError = err;
    }

    // Network / fetch rejection → retry or throw.
    if (fetchError !== null) {
      if (attempt < maxRetries) {
        await sleep(sleepFn, backoffMs(attempt));
        attempt++;
        continue;
      }
      throw new WaveApiError(
          "network",
          `Wave fetch failed after ${attempt + 1} attempt(s): ` +
          fetchError.message,
          fetchError,
      );
    }

    const status = response.status;

    // Auth errors: no retry.
    if (status === 401 || status === 403) {
      throw new WaveApiError(
          "auth",
          `Wave API returned ${status} — token missing or revoked.`,
          status,
      );
    }

    // Rate limit: retry with Retry-After or backoff.
    if (status === 429) {
      if (attempt < maxRetries) {
        const delay = retryAfterMs(response.headers) || backoffMs(attempt);
        await sleep(sleepFn, delay);
        attempt++;
        continue;
      }
      throw new WaveApiError(
          "rateLimited",
          `Wave API rate-limited after ${attempt + 1} attempt(s).`,
          status,
      );
    }

    // Server errors: retry or throw.
    if (status >= 500 && status <= 599) {
      if (attempt < maxRetries) {
        await sleep(sleepFn, backoffMs(attempt));
        attempt++;
        continue;
      }
      throw new WaveApiError(
          "network",
          `Wave API returned ${status} after ${attempt + 1} attempt(s).`,
          status,
      );
    }

    // Unexpected non-2xx.
    if (status < 200 || status > 299) {
      throw new WaveApiError(
          "unknown",
          `Wave API returned unexpected status ${status}.`,
          status,
      );
    }

    // HTTP 2xx — parse JSON and check for GraphQL-layer errors.
    let body;
    try {
      body = await response.json();
    } catch (err) {
      throw new WaveApiError(
          "network",
          `Wave API returned non-JSON 2xx response: ${err.message}`,
          err,
      );
    }

    if (Array.isArray(body.errors) && body.errors.length > 0) {
      const messages = body.errors
          .map((e) => (typeof e.message === "string" ? e.message : String(e)))
          .join("; ");
      throw new WaveApiError(
          "graphql",
          `Wave GraphQL errors: ${messages}`,
          body.errors,
      );
    }

    return body.data;
  }
}

// ---------------------------------------------------------------------------
// Helpers built on graphql()
// ---------------------------------------------------------------------------

/**
 * Fetches the authenticated Wave user's id and default email.
 * Used to fast-fail an invalid or missing token.
 * @param {Object=} options Injectable options (see `graphql`).
 * @return {!Promise<Object>} The user object with id and defaultEmail.
 */
async function whoami(options = {}) {
  const data = await graphql(
      "query { user { id defaultEmail } }",
      {},
      options,
  );
  return data.user;
}

/**
 * Lists the first page (up to 50) of Wave businesses for the token owner.
 * Returns an array of `{id, name}` objects.
 * @param {Object=} options Injectable options (see `graphql`).
 * @return {!Promise<!Array<Object>>} Business nodes with id and name.
 */
async function listBusinesses(options = {}) {
  const data = await graphql(
      "{ businesses(page: 1, pageSize: 50)" +
      " { edges { node { id name } } } }",
      {},
      options,
  );
  const edges = (data.businesses && Array.isArray(data.businesses.edges)) ?
    data.businesses.edges : [];
  return edges
      .filter((e) => e && e.node)
      .map((e) => ({id: e.node.id, name: e.node.name}));
}

module.exports = {WaveApiError, graphql, whoami, listBusinesses};

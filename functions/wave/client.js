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
// Hard ceiling on the Retry-After header value so a rogue/misconfigured
// server cannot stall the function against its Cloud Run timeout.
const MAX_RETRY_AFTER_MS = 60_000;

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

/**
 * Consumes (and discards) a response body. Undici/Node fetch keeps the
 * underlying socket pinned until the body is read or cancelled, so every
 * non-2xx retry/throw path must drain the body or connections leak across
 * the retry loop. Errors are swallowed — this is purely a resource release.
 * @param {*} response A fetch Response (or a test double without `.text`).
 * @return {!Promise<void>}
 */
async function discardBody(response) {
  try {
    if (response && typeof response.text === "function") {
      await response.text();
    }
  } catch {
    // Best-effort drain only; the caller is already on an error path.
  }
}

// ---------------------------------------------------------------------------
// Core transport
// ---------------------------------------------------------------------------

/**
 * Runs the POST-with-retry loop and returns the first 2xx response.
 *
 * Retry policy: 429 (honoring a clamped `Retry-After`), 5xx and fetch
 * rejections are retried up to `maxRetries` times; 401/403 and any other
 * non-2xx status throw immediately. Every non-2xx path drains the body first
 * so sockets are not pinned across the loop.
 *
 * @param {string} requestBody Serialized GraphQL request body.
 * @param {!Object} requestHeaders Request headers including Authorization.
 * @param {!Function} fetchImpl Fetch implementation.
 * @param {!Function} sleepFn Injected delay function.
 * @param {number} maxRetries Maximum retries after the first attempt.
 * @return {!Promise<*>} The 2xx fetch Response.
 * @throws {WaveApiError}
 */
async function postWithRetry(
    requestBody, requestHeaders, fetchImpl, sleepFn, maxRetries) {
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
      await discardBody(response);
      throw new WaveApiError(
          "auth",
          `Wave API returned ${status} — token missing or revoked.`,
          status,
      );
    }

    // Rate limit: retry with Retry-After or backoff.
    if (status === 429) {
      await discardBody(response);
      if (attempt < maxRetries) {
        const headerDelay = retryAfterMs(response.headers);
        // Fix #4: treat 0 as a valid header value (honor it), only fall back
        // to backoff when the header is genuinely absent (null).
        // Fix #2: clamp to MAX_RETRY_AFTER_MS so a huge header can't stall us.
        const delay = headerDelay == null ?
          backoffMs(attempt) :
          Math.min(headerDelay, MAX_RETRY_AFTER_MS);
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
      await discardBody(response);
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
      await discardBody(response);
      throw new WaveApiError(
          "unknown",
          `Wave API returned unexpected status ${status}.`,
          status,
      );
    }

    return response;
  }
}

/**
 * Parses a 2xx Wave response body and returns its `data` field.
 *
 * Throws `network` for a non-JSON body, `unknown` for a null/array/non-object
 * body, and `graphql` when the body carries a non-empty top-level `errors`
 * array (Wave reports resolver failures on an HTTP 200).
 *
 * @param {*} response A 2xx fetch Response.
 * @return {!Promise<*>} The `data` field of the GraphQL response.
 * @throws {WaveApiError}
 */
async function parseGraphqlResponse(response) {
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

  // Fix #3: guard against null or non-object bodies (e.g. null, array)
  // before property access to avoid a raw TypeError.
  if (body === null || Array.isArray(body) || typeof body !== "object") {
    throw new WaveApiError(
        "unknown",
        "Wave API returned a 2xx response with an unexpected body shape.",
        body,
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

  const response = await postWithRetry(
      requestBody, requestHeaders, fetchImpl, sleepFn, maxRetries);
  return parseGraphqlResponse(response);
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
  // Fix #1: a 200 with no data.user (off-spec response) must throw a typed
  // WaveApiError rather than a raw TypeError from `undefined.user`.
  if (data == null || data.user == null) {
    throw new WaveApiError(
        "unknown",
        "Wave API /whoami returned a 200 but no user object in data.",
        {data},
    );
  }
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
      // Coerce a null/non-string name to "" so downstream name matching
      // (selectBusiness) never throws on `name.trim()` for an off-spec node.
      .map((e) => ({
        id: e.node.id,
        name: typeof e.node.name === "string" ? e.node.name : "",
      }));
}

module.exports = {WaveApiError, graphql, whoami, listBusinesses};

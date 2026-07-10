"use strict";

/**
 * @fileoverview Maps Wave error objects to Cloud Functions HttpsError
 * `{code, message}` pairs.
 *
 * Kept pure (no firebase-functions import, no I/O) so it can be unit-tested in
 * isolation; `index.js` wraps the result in an `HttpsError`. It lives in its
 * own module — rather than in `client.js` or `customers.js` — so it can require
 * BOTH `WaveApiError` and `WaveValidationError` without creating an import
 * cycle between those two modules.
 *
 * The returned `code`/`message` pairs are a stable contract: the Flutter error
 * mapper mirrors these exact strings. Messages are app-owned, PII-free codes
 * (e.g. `wave/token-invalid`) — never Wave's raw error text.
 *
 * @module wave/errors
 */

const {WaveApiError} = require("./client");
const {WaveValidationError} = require("./customers");

/**
 * Classifies a caught Wave error into the HttpsError `{code, message}` the
 * callable should throw. The mapping (do not change without updating the
 * Flutter mapper):
 *   - `WaveApiError` auth        → failed-precondition / wave/token-invalid
 *   - `WaveApiError` rateLimited → resource-exhausted  / wave/rate-limited
 *   - `WaveApiError` network     → unavailable         / wave/network
 *   - `WaveApiError` graphql     → invalid-argument    / wave/validation
 *   - `WaveValidationError`      → invalid-argument    / wave/validation
 *   - anything else (incl. unknown) → internal         / wave/unknown
 * @param {*} err The caught error.
 * @return {{code: string, message: string}} HttpsError code and message.
 */
function classifyWaveError(err) {
  if (err instanceof WaveValidationError) {
    return {code: "invalid-argument", message: "wave/validation"};
  }
  if (err instanceof WaveApiError) {
    switch (err.kind) {
      case "auth":
        return {code: "failed-precondition", message: "wave/token-invalid"};
      case "rateLimited":
        return {code: "resource-exhausted", message: "wave/rate-limited"};
      case "network":
        return {code: "unavailable", message: "wave/network"};
      case "graphql":
        return {code: "invalid-argument", message: "wave/validation"};
      default:
        return {code: "internal", message: "wave/unknown"};
    }
  }
  return {code: "internal", message: "wave/unknown"};
}

module.exports = {classifyWaveError};

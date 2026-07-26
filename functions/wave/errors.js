"use strict";

/**
 * @fileoverview Maps Wave error objects to Cloud Functions HttpsError
 * `{code, message}` pairs — kept pure and in its own module (so it's
 * unit-testable and can require both `WaveApiError` and `WaveValidationError`
 * without an import cycle between `client.js`/`customers.js`); the pairs are
 * a stable, PII-free contract mirrored by the Flutter error mapper, never
 * Wave's raw error text.
 * @module wave/errors
 */

const {WaveApiError} = require("./client");
const {WaveValidationError} = require("./customers");

/**
 * Classifies a caught Wave error into the HttpsError `{code, message}` the
 * callable should throw (do not change the mapping without updating the
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

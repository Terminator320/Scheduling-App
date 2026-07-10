"use strict";

/**
 * @fileoverview Wave Accounting secret parameter and token accessor.
 *
 * Exports the `WAVE_FULL_ACCESS_TOKEN` secret param object (so `index.js` can
 * bind it to each Wave-calling function via
 * `secrets: [WAVE_FULL_ACCESS_TOKEN]`)
 * and a `getWaveToken()` helper that reads the secret value at runtime.
 *
 * IMPORTANT: `getWaveToken()` must only be called inside a Cloud Function
 * invocation — never at module-load time. Secret param values are only
 * available after the runtime has injected them.
 *
 * @module wave/auth
 */

const {defineSecret} = require("firebase-functions/params");

/** Wave full-access API token. Stored in Google Secret Manager. */
const WAVE_FULL_ACCESS_TOKEN = defineSecret("WAVE_FULL_ACCESS_TOKEN");

/**
 * Returns the trimmed Wave full-access token value.
 * Must only be called inside a Cloud Function invocation (not at module load).
 * @return {string} The token string.
 */
function getWaveToken() {
  return WAVE_FULL_ACCESS_TOKEN.value().trim();
}

module.exports = {WAVE_FULL_ACCESS_TOKEN, getWaveToken};

"use strict";

/**
 * @fileoverview Exports the `WAVE_FULL_ACCESS_TOKEN` secret param (bound to
 * each Wave-calling function via `secrets: [WAVE_FULL_ACCESS_TOKEN]`) and a
 * `getWaveToken()` accessor; `getWaveToken()` must only be called inside a
 * Cloud Function invocation, since secret values aren't injected until then.
 * @module wave/auth
 */

const {defineSecret} = require("firebase-functions/params");

/** Wave full-access API token. Stored in Google Secret Manager. */
const WAVE_FULL_ACCESS_TOKEN = defineSecret("WAVE_FULL_ACCESS_TOKEN");

/**
 * Returns the trimmed Wave full-access token value; must only be called inside a Cloud Function invocation, not at module load.
 * @return {string} The token string.
 */
function getWaveToken() {
  return WAVE_FULL_ACCESS_TOKEN.value().trim();
}

module.exports = {WAVE_FULL_ACCESS_TOKEN, getWaveToken};

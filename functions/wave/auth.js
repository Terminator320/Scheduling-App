"use strict";

/**
 * @fileoverview Exports the `WAVE_FULL_ACCESS_TOKEN` secret param (bound to
 * each Wave-calling function via `secrets: [WAVE_FULL_ACCESS_TOKEN]`) and a
 * `getWaveToken()` accessor. Only call `getWaveToken()` from inside a Cloud
 * Function invocation — secret values aren't injected before that.
 * @module wave/auth
 */

const {defineSecret} = require("firebase-functions/params");

/** Wave full-access API token. Stored in Google Secret Manager. */
const WAVE_FULL_ACCESS_TOKEN = defineSecret("WAVE_FULL_ACCESS_TOKEN");

/**
 * Returns the trimmed Wave full-access token value. Only call this inside a
 * Cloud Function invocation, not at module load.
 * @return {string} The token string.
 */
function getWaveToken() {
  return WAVE_FULL_ACCESS_TOKEN.value().trim();
}

module.exports = {WAVE_FULL_ACCESS_TOKEN, getWaveToken};

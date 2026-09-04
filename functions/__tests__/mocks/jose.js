"use strict";

/**
 * Minimal CommonJS stand-in for Jest loading Firebase Admin's JWKS helper.
 *
 * @return {Promise<object>} A public-key-shaped object.
 */
async function importJWK() {
  return {
    type: "public",
    [Symbol.toStringTag]: "KeyObject",
    export: () => "",
  };
}

/**
 * Returns a harmless PEM placeholder for tests that never verify real tokens.
 *
 * @return {Promise<string>} Empty test key material.
 */
async function exportSPKI() {
  return "";
}

module.exports = {
  exportSPKI,
  importJWK,
};

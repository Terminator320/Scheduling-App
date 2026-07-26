"use strict";

/**
 * @fileoverview Pure image magic-byte validation, split out from the Storage
 * trigger (`maintenance.js`) so it is unit-testable without loading
 * firebase-functions (`onObjectFinalized` eagerly resolves a Storage bucket
 * at load).
 * @module image_magic
 */

/**
 * True when the first bytes are a JPEG or PNG magic signature; the
 * server-side backstop since client contentType/extension aren't trusted.
 * @param {?Buffer} buffer First bytes of the uploaded object.
 * @return {boolean}
 */
function hasValidImageMagic(buffer) {
  const b = buffer || Buffer.alloc(0);
  const isJpeg = b[0] === 0xFF && b[1] === 0xD8 && b[2] === 0xFF;
  const isPng =
    b[0] === 0x89 && b[1] === 0x50 && b[2] === 0x4E && b[3] === 0x47;
  return isJpeg || isPng;
}

module.exports = {hasValidImageMagic};

"use strict";

/**
 * @fileoverview Pure image magic-byte validation, split out from the Storage
 * trigger (`maintenance.js`) so it is unit-testable without loading
 * firebase-functions — `onObjectFinalized` eagerly resolves a Storage bucket
 * at trigger-definition time, which a plain unit test has no config for.
 * @module image_magic
 */

/**
 * True when the first bytes are a JPEG (FF D8 FF) or PNG (89 50 4E 47) magic
 * signature. Client contentType/extension are not trusted — this is the
 * server-side backstop against a direct REST/SDK caller.
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

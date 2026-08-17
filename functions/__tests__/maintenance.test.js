"use strict";

/**
 * Tests for the pure magic-byte validator behind validateUploadedImage. This
 * is the server-side backstop we need because a direct REST/SDK caller can
 * lie about contentType, and the Storage rule has no way to catch that.
 *
 * HAND-MIRRORED by `hasValidImageMagic` in `lib/core/images/image_magic.dart`,
 * and the cases below are shared verbatim with
 * `test/core/images/image_magic_test.dart`. This pair had already drifted —
 * the Dart side accepted PNG on three bytes while this one required four — and
 * because THIS side deletes the object, the divergence showed up as a photo
 * that uploaded successfully and then silently vanished. Change both together.
 */

const {hasValidImageMagic} = require("../image_magic");

describe("hasValidImageMagic", () => {
  test("accepts a JPEG signature (FF D8 FF)", () => {
    expect(hasValidImageMagic(Buffer.from([0xFF, 0xD8, 0xFF, 0x00])))
        .toBe(true);
  });

  test("accepts a PNG signature (89 50 4E 47)", () => {
    expect(hasValidImageMagic(Buffer.from([0x89, 0x50, 0x4E, 0x47])))
        .toBe(true);
  });

  test("rejects the three PNG bytes with the wrong fourth", () => {
    // The regression the Dart mirror was reconciled against: that side used to
    // accept this, so the file uploaded and was then deleted here.
    expect(hasValidImageMagic(Buffer.from([0x89, 0x50, 0x4E, 0x00])))
        .toBe(false);
  });

  test("rejects a three-byte PNG prefix", () => {
    expect(hasValidImageMagic(Buffer.from([0x89, 0x50, 0x4E]))).toBe(false);
  });

  test("accepts a three-byte JPEG prefix", () => {
    // Asymmetric with PNG on purpose — the JPEG branch never indexes the
    // fourth byte, so both sides accept this. The Dart mirror restates the
    // asymmetry explicitly rather than using one length guard.
    expect(hasValidImageMagic(Buffer.from([0xFF, 0xD8, 0xFF]))).toBe(true);
  });

  test("rejects a PDF signature", () => {
    expect(hasValidImageMagic(Buffer.from([0x25, 0x50, 0x44, 0x46])))
        .toBe(false);
  });

  test("rejects a GIF signature", () => {
    expect(hasValidImageMagic(Buffer.from([0x47, 0x49, 0x46, 0x38])))
        .toBe(false);
  });

  test("rejects arbitrary non-image bytes", () => {
    expect(hasValidImageMagic(Buffer.from([0x00, 0x01, 0x02, 0x03])))
        .toBe(false);
  });

  test("rejects a truncated JPEG (fewer than 3 magic bytes)", () => {
    expect(hasValidImageMagic(Buffer.from([0xFF, 0xD8]))).toBe(false);
  });

  test("rejects an empty or missing buffer", () => {
    expect(hasValidImageMagic(Buffer.alloc(0))).toBe(false);
    expect(hasValidImageMagic(null)).toBe(false);
  });
});

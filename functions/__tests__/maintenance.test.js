"use strict";

/**
 * Unit tests for the pure magic-byte validator behind validateUploadedImage —
 * the server-side backstop that the Storage rule's trusted contentType cannot
 * provide (a direct REST/SDK caller can lie about contentType).
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

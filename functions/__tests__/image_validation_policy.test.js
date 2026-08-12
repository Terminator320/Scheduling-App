"use strict";

/**
 * Tests for the OTHER destructive path in `maintenance.js`.
 *
 * `validateUploadedImage` deletes a user's just-uploaded photo, and it does so
 * on two branches — bytes that failed validation, and bytes that could not be
 * READ at all. The second is the dangerous one: nothing about a transient
 * Storage read failure says the file was bad, yet the file is destroyed. It
 * is deliberate (fail closed — the Storage rule trusts client contentType, so
 * an unread file is an uninspected one), and until this suite it was the only
 * branch in the module with no coverage at all.
 */

const {
  isAppointmentImagePath,
  runImageValidation,
} = require("../maintenance_policy");

const JPEG = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46]);
const PNG = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
const PDF = Buffer.from([0x25, 0x50, 0x44, 0x46, 0x2d, 0x31, 0x2e, 0x34]);

const IMAGE_PATH = "appointments/a1/images/photo.jpg";

/** @return {!Object} A logger that records instead of printing. */
function fakeLogger() {
  return {
    warns: [],
    errors: [],
    warn(msg, meta) {
      this.warns.push({msg, meta});
    },
    error(msg, meta) {
      this.errors.push({msg, meta});
    },
  };
}

/**
 * @param {!Object} opts
 * @return {!Object} deps plus the recorded calls.
 */
function harness(opts) {
  const options = opts || {};
  const state = {
    reads: 0,
    deletes: 0,
    logger: fakeLogger(),
  };
  const deps = {
    // Not `||` — an empty path is a case under test, not an absent one.
    filePath: options.filePath === undefined ? IMAGE_PATH : options.filePath,
    readHeader: async () => {
      state.reads += 1;
      if (options.readError) throw options.readError;
      return options.buffer === undefined ? JPEG : options.buffer;
    },
    deleteFile: async () => {
      state.deletes += 1;
      if (options.deleteError) throw options.deleteError;
    },
    logger: state.logger,
  };
  return {deps, state};
}

describe("runImageValidation", () => {
  describe("a path outside the appointment image prefix", () => {
    it("is left alone without reading or deleting anything", async () => {
      const {deps, state} = harness({filePath: "clients/c1/logo.png"});

      await expect(runImageValidation(deps)).resolves.toBe("skipped");
      expect(state.reads).toBe(0);
      expect(state.deletes).toBe(0);
    });

    it("skips an empty object name rather than touching Storage", async () => {
      // The trigger resolves its file handle lazily for exactly this case:
      // `.file("")` throws.
      const {deps, state} = harness({filePath: ""});

      await expect(runImageValidation(deps)).resolves.toBe("skipped");
      expect(state.reads).toBe(0);
    });
  });

  describe("valid bytes", () => {
    it("keeps a JPEG", async () => {
      const {deps, state} = harness({buffer: JPEG});

      await expect(runImageValidation(deps)).resolves.toBe("kept");
      expect(state.deletes).toBe(0);
    });

    it("keeps a PNG", async () => {
      const {deps, state} = harness({buffer: PNG});

      await expect(runImageValidation(deps)).resolves.toBe("kept");
      expect(state.deletes).toBe(0);
    });

    it("logs nothing when it keeps a file", async () => {
      const {deps, state} = harness({buffer: PNG});

      await runImageValidation(deps);

      expect(state.logger.warns).toHaveLength(0);
      expect(state.logger.errors).toHaveLength(0);
    });
  });

  describe("invalid bytes", () => {
    it("deletes a file whose magic bytes are not an image", async () => {
      const {deps, state} = harness({buffer: PDF});

      await expect(runImageValidation(deps)).resolves.toBe("deleted-invalid");
      expect(state.deletes).toBe(1);
    });

    it("deletes an empty file", async () => {
      const {deps, state} = harness({buffer: Buffer.alloc(0)});

      await expect(runImageValidation(deps)).resolves.toBe("deleted-invalid");
      expect(state.deletes).toBe(1);
    });

    it("swallows a failed delete rather than throwing", async () => {
      const {deps, state} = harness({
        buffer: PDF,
        deleteError: new Error("storage down"),
      });

      await expect(runImageValidation(deps)).resolves.toBe("deleted-invalid");
      expect(state.logger.errors).toHaveLength(1);
    });
  });

  describe("a read failure", () => {
    it("DELETES the file — failing closed, not open", async () => {
      // The branch this suite exists for. An unreadable file is an uninspected
      // one, and the Storage rule trusts client contentType, so keeping it
      // would leave unvalidated bytes in the bucket forever.
      const {deps, state} = harness({readError: new Error("read timeout")});

      await expect(runImageValidation(deps)).resolves.toBe(
          "deleted-unreadable",
      );
      expect(state.deletes).toBe(1);
    });

    it("never asks whether unread bytes are valid", async () => {
      // A regression that fell through to the magic-byte check with an
      // undefined buffer would take the invalid-bytes branch instead, which
      // deletes for a reason the logs would then misreport.
      const {deps, state} = harness({readError: new Error("read timeout")});

      await runImageValidation(deps);

      expect(state.logger.warns).toHaveLength(1);
      expect(state.logger.warns[0].msg).toContain("read failed");
    });

    it("logs the path and the cause, and nothing else", async () => {
      const {deps, state} = harness({readError: new Error("read timeout")});

      await runImageValidation(deps);

      expect(state.logger.warns[0].meta).toEqual({
        filePath: IMAGE_PATH,
        err: "read timeout",
      });
    });

    it("still resolves when the delete ALSO fails", async () => {
      // Nothing to retry from a Storage trigger, so a throw here would just be
      // an unhandled rejection; the object survives to the next finalize.
      const {deps, state} = harness({
        readError: new Error("read timeout"),
        deleteError: new Error("delete denied"),
      });

      await expect(runImageValidation(deps)).resolves.toBe(
          "deleted-unreadable",
      );
      expect(state.logger.warns).toHaveLength(1);
      expect(state.logger.errors).toHaveLength(1);
      expect(state.logger.errors[0].msg).toContain("delete after read-fail");
    });

    it("does not read twice", async () => {
      const {deps, state} = harness({readError: new Error("read timeout")});

      await runImageValidation(deps);

      expect(state.reads).toBe(1);
    });
  });

  describe("isAppointmentImagePath", () => {
    it.each([
      ["appointments/a1/images/p.jpg", true],
      ["appointments/a1/images/nested/p.jpg", true],
      ["appointments/a1/notes.txt", false],
      ["appointments//images/p.jpg", false],
      ["clients/c1/images/p.jpg", false],
      ["", false],
    ])("%s → %s", (path, expected) => {
      expect(isAppointmentImagePath(path)).toBe(expected);
    });
  });
});

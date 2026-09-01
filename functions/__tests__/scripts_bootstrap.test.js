"use strict";

/**
 * Tests for `bootstrapScript` — the preamble every prod-touching script in
 * `scripts/` now shares.
 *
 * `_flags.js` owned rejecting an unknown argument and `_project.js` owned the
 * banner, but nothing owned the WIRING between them: resolve `dryRun` once and
 * hand the same value to both. Thirteen scripts spelled that out by hand, and
 * commit `3059ac0a` ("pass the required dryRun flag to the audit's target
 * banner") is that drift landing. Repo history also has a backfill whose
 * `--dry-run` wrote everything and then threw.
 *
 * The two orderings below are the ones that matter, and neither is visible in
 * review: flags must be rejected BEFORE a credential is resolved, and the
 * banner must be printed BEFORE the caller can read anything.
 */

// `mock`-prefixed so jest allows the factories below to close over them.
const mockApp = {options: {projectId: "test-project"}};
const mockDb = {marker: "firestore"};

const mockInitializeApp = jest.fn(() => mockApp);
const mockApplicationDefault = jest.fn(() => ({kind: "adc"}));
const mockGetFirestore = jest.fn(() => mockDb);

jest.mock("firebase-admin/app", () => ({
  initializeApp: (...args) => mockInitializeApp(...args),
  applicationDefault: (...args) => mockApplicationDefault(...args),
}));
jest.mock("firebase-admin/firestore", () => ({
  getFirestore: (...args) => mockGetFirestore(...args),
}));

const {bootstrapScript} = require("../scripts/_project");

let logSpy;
beforeEach(() => {
  jest.clearAllMocks();
  logSpy = jest.spyOn(console, "log").mockImplementation(() => {});
});
afterEach(() => {
  logSpy.mockRestore();
});

/** @return {string} Everything the banner printed. */
function printed() {
  return logSpy.mock.calls.flat().join("\n");
}

describe("bootstrapScript", () => {
  test("returns the app, its Firestore handle and the resolved dryRun", () => {
    const out = bootstrapScript(["--dry-run"], {assertFlags: () => {}});

    expect(out.app).toBe(mockApp);
    expect(out.db).toBe(mockDb);
    expect(out.dryRun).toBe(true);
    expect(mockInitializeApp).toHaveBeenCalledWith({credential: {kind: "adc"}});
  });

  test("the banner shows the SAME dryRun the caller gets back", () => {
    // The drift this helper exists to make impossible: a run that writes
    // behind a banner claiming "[dry-run]", or the reverse.
    const out = bootstrapScript(["--dry-run"], {assertFlags: () => {}});

    expect(out.dryRun).toBe(true);
    expect(printed()).toContain("[dry-run]");
    expect(printed()).toContain("test-project");
  });

  test("no --dry-run means a LIVE banner and a false flag", () => {
    const out = bootstrapScript([], {assertFlags: () => {}});

    expect(out.dryRun).toBe(false);
    expect(printed()).not.toContain("[dry-run]");
    expect(printed()).toContain("(LIVE)");
  });

  test("matches --dry-run EXACTLY, so a typo cannot read as true", () => {
    // The flag wrapper is what rejects these; if one ever slipped past it,
    // this is the line that keeps it from silently meaning "live".
    for (const argv of [["--dryrun"], ["--dry_run"], ["--dry-run=true"]]) {
      expect(bootstrapScript(argv, {assertFlags: () => {}}).dryRun).toBe(false);
    }
  });

  test("rejects flags BEFORE resolving any credential", () => {
    // Ordering, not just presence: a script that reaches for prod credentials
    // and only then rejects the argument has already touched the wrong thing.
    const boom = new Error("unknown argument \"--nope\"");
    expect(() => bootstrapScript(["--nope"], {
      assertFlags: () => {
        throw boom;
      },
    })).toThrow(boom);

    expect(mockApplicationDefault).not.toHaveBeenCalled();
    expect(mockInitializeApp).not.toHaveBeenCalled();
    expect(mockGetFirestore).not.toHaveBeenCalled();
    expect(logSpy).not.toHaveBeenCalled();
  });

  test("hands the script's own argv to the script's own wrapper", () => {
    const assertFlags = jest.fn();
    bootstrapScript(["--since=2026-01-01"], {assertFlags});

    expect(assertFlags).toHaveBeenCalledWith(["--since=2026-01-01"]);
  });

  test("prints the banner BEFORE returning, so nothing reads first", () => {
    // `printTargetBanner` is only useful ahead of the first read; a caller
    // cannot read anything until this returns, so printing inside is the
    // guarantee.
    expect(logSpy).not.toHaveBeenCalled();
    bootstrapScript([], {assertFlags: () => {}});
    expect(logSpy).toHaveBeenCalled();
  });
});

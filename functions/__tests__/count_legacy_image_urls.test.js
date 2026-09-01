"use strict";

/**
 * Tests for `countLegacyUrls` / `countArrayUrls` — the two predicates in
 * `scripts/count-legacy-image-urls.js`.
 *
 * This script's verdict (prod count = 0) is what authorized permanently
 * retiring `images.url` from the rules, the loader, the store and the
 * backfill. That was an irreversible schema decision made on an UNTESTED
 * count, and both ways it could have been wrong are silent: a
 * misclassification at the `storagePath !== ""` branch, or an early exit from
 * the paging loop, each read as "no legacy data" rather than as an error.
 *
 * Every sibling script exports its predicate for exactly this reason
 * (`needsArchivedField`, `patchFor`, `runClear`); this one exported only
 * `assertKnownFlags`.
 */

const {countLegacyUrls, countArrayUrls} =
  require("../scripts/count-legacy-image-urls");

/** Mirrors `PAGE_SIZE` in the script — needed to build a FULL page. */
const PAGE_SIZE = 500;

/**
 * One image-subcollection document double.
 * @param {string} id
 * @param {!Object} data Stored fields.
 * @param {string=} appointmentId The parent appointment, or null for an
 *   orphaned subcollection the script reports as "(unknown)".
 * @return {!Object}
 */
function imageDoc(id, data, appointmentId = "appt1") {
  return {
    id,
    data: () => data,
    ref: {parent: {parent: appointmentId ? {id: appointmentId} : null}},
  };
}

/**
 * One appointment document double.
 * @param {string} id
 * @param {!Object} data Stored fields.
 * @return {!Object}
 */
function apptDoc(id, data) {
  return {id, data: () => data};
}

/**
 * A Firestore double serving `pages` from whichever accessor the caller uses.
 * `countLegacyUrls` reads a collectionGroup, `countArrayUrls` a collection.
 * @param {!Array<!Array<!Object>>} pages Documents per page, in order.
 * @param {!Array<string>=} cursors Filled with each `startAfter` doc id.
 * @return {!Object}
 */
function makeDb(pages, cursors = []) {
  let index = 0;
  const query = {
    orderBy: () => query,
    limit: () => query,
    startAfter: (doc) => {
      cursors.push(doc.id);
      return query;
    },
    get: async () => {
      const docs = pages[index] || [];
      index += 1;
      return {empty: docs.length === 0, size: docs.length, docs};
    },
  };
  return {collectionGroup: () => query, collection: () => query};
}

/** Silences the script's console reporting. */
let logSpy;
beforeEach(() => {
  logSpy = jest.spyOn(console, "log").mockImplementation(() => {});
});
afterEach(() => {
  logSpy.mockRestore();
});

describe("countLegacyUrls three-way classification", () => {
  test("a doc WITH a storagePath is skipped, whether or not it has a url",
      async () => {
        // The branch that decided the schema call: a pre-contract upload wrote
        // BOTH fields, and those are not legacy — counting them would have
        // blocked the retirement that was correct to make.
        const out = await countLegacyUrls(makeDb([[
          imageDoc("i1", {storagePath: "a/1", url: "https://x/1"}),
          imageDoc("i2", {storagePath: "a/2"}),
        ]]), false);

        expect(out).toEqual({scanned: 2, legacy: 0, orphans: 0});
      });

  test("a url-only doc is LEGACY", async () => {
    const out = await countLegacyUrls(makeDb([[
      imageDoc("i1", {url: "https://x/1"}),
    ]]), false);

    expect(out).toEqual({scanned: 1, legacy: 1, orphans: 0});
  });

  test("a doc with NEITHER field is an orphan, not a legacy url", async () => {
    const out = await countLegacyUrls(makeDb([[
      imageDoc("i1", {}),
    ]]), false);

    expect(out).toEqual({scanned: 1, legacy: 0, orphans: 1});
  });

  test("whitespace-only fields count as absent, not present", async () => {
    // `String(...).trim()` on both sides — a blank storagePath must not make
    // a legacy row look migrated, and a blank url must not make an orphan
    // look like a legacy link.
    const out = await countLegacyUrls(makeDb([[
      imageDoc("i1", {storagePath: "   ", url: "https://x/1"}),
      imageDoc("i2", {storagePath: "", url: "   "}),
    ]]), false);

    expect(out).toEqual({scanned: 2, legacy: 1, orphans: 1});
  });

  test("an orphan is ALWAYS reported, verbose or not", async () => {
    // It is the finding that stops the clear script, so it must not hide
    // behind a flag the operator did not pass.
    await countLegacyUrls(makeDb([[imageDoc("i1", {})]]), false);

    expect(logSpy.mock.calls.flat().join("\n"))
        .toContain("appointments/appt1/images/i1");
  });

  test("a legacy url is listed only when verbose", async () => {
    await countLegacyUrls(makeDb([[imageDoc("i1", {url: "u"})]]), false);
    expect(logSpy).not.toHaveBeenCalled();

    await countLegacyUrls(makeDb([[imageDoc("i1", {url: "u"})]]), true);
    expect(logSpy.mock.calls.flat().join("\n")).toContain("legacy url:");
  });

  test("names an unparented image rather than throwing", async () => {
    const out = await countLegacyUrls(
        makeDb([[imageDoc("i1", {}, null)]]), false);

    expect(out.orphans).toBe(1);
    expect(logSpy.mock.calls.flat().join("\n")).toContain("(unknown)");
  });
});

describe("countLegacyUrls paging", () => {
  test("a FULL page continues the walk and pages on its last doc", async () => {
    const cursors = [];
    const full = [];
    for (let i = 0; i < PAGE_SIZE; i += 1) {
      full.push(imageDoc(`i${i}`, {url: "https://x"}));
    }
    const out = await countLegacyUrls(
        makeDb([full, [imageDoc("z1", {url: "https://x"})]], cursors), false);

    expect(out.scanned).toBe(PAGE_SIZE + 1);
    expect(out.legacy).toBe(PAGE_SIZE + 1);
    expect(cursors).toEqual([`i${PAGE_SIZE - 1}`]);
  });

  test("an empty collection group reports zeroes", async () => {
    expect(await countLegacyUrls(makeDb([[]]), false))
        .toEqual({scanned: 0, legacy: 0, orphans: 0});
  });
});

describe("countArrayUrls", () => {
  test("counts url-bearing ENTRIES, not appointments", async () => {
    const out = await countArrayUrls(makeDb([[
      apptDoc("a1", {pictures: [{url: "u1"}, {url: "u2"}, {storagePath: "p"}]}),
    ]]), false);

    expect(out).toEqual({appointments: 1, withArray: 1, urls: 2});
  });

  test("an appointment with no array is scanned but not counted", async () => {
    const out = await countArrayUrls(makeDb([[
      apptDoc("a1", {}),
      apptDoc("a2", {pictures: []}),
      apptDoc("a3", {pictures: "not-an-array"}),
    ]]), false);

    expect(out).toEqual({appointments: 3, withArray: 0, urls: 0});
  });

  test("an array entry with a blank or missing url carries no link",
      async () => {
        // `withArray` still counts it — the array is what the clear script
        // removes, whether or not its entries carry links.
        const out = await countArrayUrls(makeDb([[
          apptDoc("a1", {pictures: [{url: "  "}, {}, null]}),
        ]]), false);

        expect(out).toEqual({appointments: 1, withArray: 1, urls: 0});
      });

  test("a FULL page continues the walk and pages on its last doc", async () => {
    const cursors = [];
    const full = [];
    for (let i = 0; i < PAGE_SIZE; i += 1) {
      full.push(apptDoc(`a${i}`, {pictures: [{url: "u"}]}));
    }
    const out = await countArrayUrls(
        makeDb([full, [apptDoc("z1", {pictures: [{url: "u"}]})]], cursors),
        false);

    expect(out.appointments).toBe(PAGE_SIZE + 1);
    expect(out.urls).toBe(PAGE_SIZE + 1);
    expect(cursors).toEqual([`a${PAGE_SIZE - 1}`]);
  });
});

"use strict";

/**
 * Tests for `runClear` — the sweep body of
 * `scripts/clear-appointment-picture-arrays.js`.
 *
 * `planClear`/`needsRecount`/`storedImageIds` (the DECISIONS) were already
 * covered. What was not covered at all was the sweep around them: the paging
 * loop, BOTH `--dry-run` gates, and the `doc.ref.update` that actually deletes
 * `pictures[]`.
 *
 * That is the gap worth closing before this is pointed at prod. It is the only
 * unattended, irreversible deletion in `scripts/`, it is step 4 of the photo
 * runbook and still pending, and this repo has already shipped exactly this
 * bug once — a backfill whose `--dry-run` wrote everything and then threw. A
 * dry run that writes is invisible in review and catastrophic in practice.
 */

const {runClear} = require("../scripts/clear-appointment-picture-arrays");
const {appointmentImageDocId} = require("../appointment_image_ids");

/**
 * The subcollection ids the backfill would have written for `entries` - the
 * ids `planClear` compares against, derived rather than spelled, so this
 * cannot drift from the real rule.
 * @param {!Array<!Object>} entries
 * @return {!Array<string>}
 */
function coveredIds(entries) {
  return entries.map(appointmentImageDocId);
}

/**
 * One appointment document double.
 * @param {string} id
 * @param {!Object} data Stored fields.
 * @param {!Array<string>} imageIds Ids present in the images subcollection.
 * @return {!Object}
 */
function makeDoc(id, data, imageIds = []) {
  const updates = [];
  return {
    id,
    updates,
    data: () => data,
    ref: {
      update: async (patch) => {
        updates.push(patch);
      },
      collection: () => ({
        select: () => ({
          get: async () => ({
            docs: imageIds.map((imageId) => ({id: imageId})),
          }),
        }),
      }),
    },
  };
}

/**
 * A db that serves `docs` as a single page.
 * @param {!Array<!Object>} docs
 * @return {!Object}
 */
function makeDb(docs) {
  const query = {
    orderBy: () => query,
    limit: () => query,
    startAfter: () => query,
    get: async () => ({
      empty: docs.length === 0,
      size: docs.length,
      docs,
    }),
  };
  return {collection: () => query};
}

/** Silences the script's console reporting. */
const quiet = {log: () => {}, warn: () => {}};

describe("runClear dry-run gates", () => {
  test("a DRY RUN never writes, on a document it would clear", async () => {
    const entries = [{storagePath: "p/1"}];
    const doc = makeDoc(
        "a1",
        {pictures: entries, pictureCount: 1},
        coveredIds(entries),
    );

    const summary = await runClear({
      db: makeDb([doc]),
      dryRun: true,
      ...quiet,
    });

    expect(doc.updates).toEqual([]);
    // It still REPORTS what it would have done — a dry run that reports
    // nothing is indistinguishable from a dry run that found nothing.
    expect(summary.cleared).toBe(1);
    expect(summary.entriesCleared).toBe(1);
  });

  test("a DRY RUN never writes on the RECOUNT path either", async () => {
    // The second gate, on the no-array branch. It is a separate `if (dryRun)`
    // and was equally unexercised.
    const doc = makeDoc("a2", {pictureCount: 0}, ["img1", "img2"]);

    const summary = await runClear({
      db: makeDb([doc]),
      dryRun: true,
      ...quiet,
    });

    expect(doc.updates).toEqual([]);
    expect(summary.recounted).toBe(1);
  });
});

describe("runClear writes", () => {
  test("a live run deletes the array AND re-stamps the count", async () => {
    const entries = [{storagePath: "p/1"}, {storagePath: "p/2"}];
    const doc = makeDoc("a1", {pictures: entries}, coveredIds(entries));

    await runClear({db: makeDb([doc]), dryRun: false, ...quiet});

    expect(doc.updates).toHaveLength(1);
    const patch = doc.updates[0];
    expect(patch).toHaveProperty("pictures");
    // Stamped from the SUBCOLLECTION, not from the array's length — the
    // subcollection is the store.
    expect(patch.pictureCount).toBe(2);
  });

  test("the count comes from the subcollection even when it disagrees with " +
      "the array", async () => {
    // Only reachable because the subcollection covers the array; the point is
    // which side the number is taken from.
    const entries = [{storagePath: "p/1"}];
    const doc = makeDoc("a1", {pictures: entries}, [
      ...coveredIds(entries),
      "img_extra_a",
      "img_extra_b",
    ]);

    await runClear({db: makeDb([doc]), dryRun: false, ...quiet});

    expect(doc.updates[0].pictureCount).toBe(3);
  });

  test("a live recount writes only pictureCount, never a pictures delete",
      async () => {
        const doc = makeDoc("a2", {pictureCount: 5}, ["img1"]);

        await runClear({db: makeDb([doc]), dryRun: false, ...quiet});

        expect(doc.updates).toEqual([{pictureCount: 1}]);
      });

  test("an appointment with no array and an ALREADY-CORRECT count is left " +
      "alone", async () => {
    const doc = makeDoc("a3", {pictureCount: 1}, ["img1"]);

    const summary = await runClear({
      db: makeDb([doc]),
      dryRun: false,
      ...quiet,
    });

    expect(doc.updates).toEqual([]);
    expect(summary.recounted).toBe(0);
  });
});

describe("runClear refusals", () => {
  test("an array the subcollection does NOT cover is refused, not cleared",
      async () => {
        // The safety gate: clearing here would destroy the only record those
        // photos existed.
        const doc = makeDoc(
            "a4",
            {pictures: [{storagePath: "p/1"}, {storagePath: "p/2"}]},
            ["img1"],
        );

        const summary = await runClear({
          db: makeDb([doc]),
          dryRun: false,
          ...quiet,
        });

        expect(doc.updates).toEqual([]);
        expect(summary.cleared).toBe(0);
        expect(summary.refused).toHaveLength(1);
        expect(summary.refused[0].id).toBe("a4");
      });

  test("a refusal does not stop the sweep reaching later appointments",
      async () => {
        const refused = makeDoc("a4", {pictures: [{storagePath: "p/x"}]}, []);
        const ok = [{storagePath: "p/1"}];
        const clearable = makeDoc("a5", {pictures: ok}, coveredIds(ok));

        const summary = await runClear({
          db: makeDb([refused, clearable]),
          dryRun: false,
          ...quiet,
        });

        expect(summary.refused).toHaveLength(1);
        expect(clearable.updates).toHaveLength(1);
        expect(summary.appointments).toBe(2);
      });
});

describe("runClear reporting", () => {
  test("an empty collection is a no-op that still reports", async () => {
    const summary = await runClear({db: makeDb([]), dryRun: false, ...quiet});
    expect(summary.appointments).toBe(0);
    expect(summary.cleared).toBe(0);
  });

  test("a dry run says plainly that nothing was written", async () => {
    const lines = [];
    await runClear({
      db: makeDb([
        makeDoc("a1", {pictures: [{storagePath: "p/1"}]},
            coveredIds([{storagePath: "p/1"}])),
      ]),
      dryRun: true,
      log: (line) => lines.push(line),
      warn: () => {},
    });

    expect(lines.join("\n")).toContain("no writes were made");
  });

  test("a live run does NOT claim to be a dry run", async () => {
    const lines = [];
    await runClear({
      db: makeDb([
        makeDoc("a1", {pictures: [{storagePath: "p/1"}]},
            coveredIds([{storagePath: "p/1"}])),
      ]),
      dryRun: false,
      log: (line) => lines.push(line),
      warn: () => {},
    });

    expect(lines.join("\n")).not.toContain("dry run");
    expect(lines.join("\n")).toContain("cleared");
  });
});

"use strict";

/**
 * The shared batched-write loop behind every bulk backfill in
 * `functions/scripts/`. This is the code that performs unattended,
 * irreversible writes against prod; it was hand-spelled in four scripts and
 * tested in none. `backfill-clients-archived.js`'s one decision rides along
 * here, since it had no test either.
 */

const {commitInBatches, MAX_BATCH_SIZE} = require("../scripts/_batch");
const {
  needsArchivedField,
  assertKnownFlags,
} = require("../scripts/backfill-clients-archived");

/**
 * Firestore stand-in recording every batch, its updates and its commits.
 * @return {!Object} `{db, batches, commits}`.
 */
function fakeDb() {
  const batches = [];
  const commits = [];
  const db = {
    batch() {
      const b = {
        updates: [],
        update(ref, patch) {
          b.updates.push([ref, patch]);
        },
        async commit() {
          commits.push(b.updates.map(([ref]) => ref));
        },
      };
      batches.push(b);
      return b;
    },
  };
  return {db, batches, commits};
}

describe("commitInBatches", () => {
  test("commits once the batch fills, and again on flush", async () => {
    const {db, commits} = fakeDb();
    const writer = commitInBatches(db, {batchSize: 2});

    for (const id of ["a", "b", "c"]) await writer.stage(id, {x: 1});
    expect(commits).toEqual([["a", "b"]]);

    await writer.flush();
    expect(commits).toEqual([["a", "b"], ["c"]]);
  });

  test("a run that lands exactly on the boundary flushes nothing extra",
      async () => {
        const {db, commits} = fakeDb();
        const writer = commitInBatches(db, {batchSize: 2});

        await writer.stage("a", {});
        await writer.stage("b", {});
        await writer.flush();

        expect(commits).toEqual([["a", "b"]]);
      });

  test("flushing an empty writer commits nothing", async () => {
    const {db, batches, commits} = fakeDb();
    await commitInBatches(db, {}).flush();
    expect(batches).toEqual([]);
    expect(commits).toEqual([]);
  });

  test("DRY RUN writes nothing at all", async () => {
    // The safety property this module exists for: `--dry-run` is enforced
    // here, so a script cannot forget the guard at its call site. A backfill
    // in this directory has previously written everything under --dry-run
    // and then thrown.
    const {db, batches, commits} = fakeDb();
    const writer = commitInBatches(db, {dryRun: true, batchSize: 2});

    for (const id of ["a", "b", "c"]) await writer.stage(id, {x: 1});
    await writer.flush();

    expect(batches).toEqual([]);
    expect(commits).toEqual([]);
  });

  test("a failed commit is not resent by the flush behind it", async () => {
    // The batch is cleared before the await, so a throw cannot leave a
    // half-committed batch that `flush()` would replay against prod.
    const failing = {
      batch: () => ({
        update() {},
        commit: async () => {
          throw new Error("unavailable");
        },
      }),
    };
    const writer = commitInBatches(failing, {batchSize: 1});

    await expect(writer.stage("a", {})).rejects.toThrow("unavailable");
    await expect(writer.flush()).resolves.toBeUndefined();
  });

  test("defaults to Firestore's cap and refuses anything past it", () => {
    expect(MAX_BATCH_SIZE).toBe(500);
    expect(() => commitInBatches(fakeDb().db, {batchSize: 501})).toThrow(
        RangeError);
    expect(() => commitInBatches(fakeDb().db, {batchSize: 0})).toThrow(
        RangeError);
    expect(() => commitInBatches(fakeDb().db, {batchSize: 1.5})).toThrow(
        RangeError);
  });
});

describe("backfill-clients-archived", () => {
  test("a doc with no archived field is patched", () => {
    expect(needsArchivedField({name: "Acme"})).toBe(true);
    expect(needsArchivedField({})).toBe(true);
    expect(needsArchivedField(null)).toBe(true);
  });

  test("an ARCHIVED client is left alone", () => {
    // Truthiness would reset this to false and un-archive them.
    expect(needsArchivedField({archived: true})).toBe(false);
  });

  test("a doc already carrying false is skipped, making re-runs free", () => {
    expect(needsArchivedField({archived: false})).toBe(false);
  });

  test("a non-boolean value is treated as missing", () => {
    // The list query filters `== false`, so a string never matches it.
    expect(needsArchivedField({archived: "false"})).toBe(true);
    expect(needsArchivedField({archived: 0})).toBe(true);
  });

  test("a near-miss flag is a hard error, not a silent live run", () => {
    expect(() => assertKnownFlags(["--dry-run"])).not.toThrow();
    expect(() => assertKnownFlags(["--dryrun"])).toThrow();
    expect(() => assertKnownFlags(["--dry_run"])).toThrow();
  });
});

/**
 * @fileoverview Tests the orchestration bodies behind the photo
 * subcollection. All of them take an injected `db`, so none needs the emulator.
 *
 * The cascade is the one that matters most: Firestore does not delete a
 * subcollection with its parent, so if `purgeAppointmentImages` regresses,
 * every appointment delete leaves photo documents orphaned under a parent that
 * no longer exists — invisible in the console, unreachable by every query the
 * app makes, and with nothing anywhere reporting it.
 *
 * The debounce is the one most easily broken into a data bug: it must collapse
 * one photo batch into ONE parent write without ever suppressing the offline
 * queue's replay, which is the only self-heal `pictureCount` has.
 */
const {
  purgeAppointmentImages,
  recountPictures,
  debouncedRecountPictures,
  IMAGES_SUBCOLLECTION,
  RECOUNT_CLAIM_COLLECTION,
  RECOUNT_CLAIM_STALE_MS,
  RECOUNT_CLAIM_TTL_MS,
} = require("../appointment_images");

/**
 * Resolves after every pending promise job has drained.
 * @return {!Promise<void>}
 */
function flush() {
  return new Promise((resolve) => setImmediate(resolve));
}

/**
 * Minimal Firestore fake: an in-memory claim ledger plus recorders for the
 * recursiveDelete targets, the parent updates and the ORDER of every
 * operation (the release-before-aggregate rule is an ordering property, so it
 * can only be pinned by observing order).
 * @param {!Object=} config `{count, updateError, deleteError, claimCreateError,
 *   claimDeleteError}`.
 * @return {!Object}
 */
function makeDb(config = {}) {
  const state = {
    count: config.count || 0,
    claims: new Map(),
    recursiveDeletes: [],
    updates: [],
    claimCreates: [],
    claimSets: [],
    claimDeletes: [],
    ops: [],
  };
  const claimDoc = (id) => ({
    create: async (data) => {
      if (config.claimCreateError) throw config.claimCreateError;
      if (state.claims.has(id)) {
        throw Object.assign(new Error("already exists"), {code: 6});
      }
      state.claims.set(id, data);
      state.claimCreates.push({id, data});
      state.ops.push("claim");
    },
    get: async () => {
      const data = state.claims.get(id);
      return {
        exists: data !== undefined,
        get: (field) => (data ? data[field] : undefined),
      };
    },
    set: async (data) => {
      state.claims.set(id, data);
      state.claimSets.push({id, data});
      state.ops.push("takeover");
    },
    delete: async () => {
      if (config.claimDeleteError) throw config.claimDeleteError;
      state.claims.delete(id);
      state.claimDeletes.push(id);
      state.ops.push("release");
    },
  });
  const appointmentDoc = (name, id) => {
    const parentPath = `${name}/${id}`;
    return {
      _path: parentPath,
      update: async (patch) => {
        if (config.updateError) throw config.updateError;
        state.updates.push({path: parentPath, patch});
        state.ops.push("update");
      },
      collection: (sub) => ({
        _path: `${parentPath}/${sub}`,
        count: () => ({
          get: async () => {
            state.ops.push("count");
            return {data: () => ({count: state.count})};
          },
        }),
      }),
    };
  };
  const db = {
    recursiveDelete: async (ref) => {
      if (config.deleteError) throw config.deleteError;
      state.recursiveDeletes.push(ref._path);
    },
    collection(name) {
      if (name === RECOUNT_CLAIM_COLLECTION) return {doc: claimDoc};
      return {doc: (id) => appointmentDoc(name, id)};
    },
  };
  return {db, state};
}

/**
 * A logger that swallows, so a fail-open path doesn't print.
 * @return {!Object}
 */
function quietLogger() {
  return {warn: () => {}, info: () => {}};
}

describe("the subcollection name is a hand-mirror", () => {
  test("matches the Dart repository and firestore.rules", () => {
    // `_imagesSubcollection` in firebase_appointments_repository.dart and the
    // `match /images/{imageId}` block in firestore.rules both spell this. A
    // rename in one place alone points the trigger at a collection nothing
    // writes, and the cascade silently stops cascading.
    expect(IMAGES_SUBCOLLECTION).toBe("images");
  });
});

describe("purgeAppointmentImages", () => {
  test("recursively deletes the images subcollection", async () => {
    const {db, state} = makeDb();
    await purgeAppointmentImages("appt1", {db});
    expect(state.recursiveDeletes).toEqual(["appointments/appt1/images"]);
  });

  test("targets the subcollection, never the parent document", async () => {
    // A ref one level too high deletes the appointment's siblings' data or the
    // appointment itself. Worth pinning explicitly — the bug would be silent
    // and catastrophic rather than silent and merely untidy.
    const {db, state} = makeDb();
    await purgeAppointmentImages("appt1", {db});
    expect(state.recursiveDeletes[0]).not.toBe("appointments/appt1");
    expect(state.recursiveDeletes[0].endsWith(`/${IMAGES_SUBCOLLECTION}`))
        .toBe(true);
  });

  test("RETHROWS, so the trigger's retry can run", async () => {
    // Deliberately unlike the best-effort cleanup elsewhere in this codebase.
    // A swallowed failure here leaves permanently invisible orphans; letting it
    // throw is what makes `retry: true` mean anything.
    const {db} = makeDb({deleteError: new Error("boom")});
    await expect(purgeAppointmentImages("appt1", {db})).rejects.toThrow("boom");
  });
});

describe("recountPictures", () => {
  test("writes the count() aggregate absolutely", async () => {
    // Absolute, never an increment: the trigger runs with retry: true, and a
    // retried FieldValue.increment double-counts. Same rule as
    // recountClientJobs.
    const {db, state} = makeDb({count: 3});
    await expect(recountPictures("appt1", {db})).resolves.toBe(3);
    expect(state.updates).toEqual([
      {path: "appointments/appt1", patch: {pictureCount: 3}},
    ]);
  });

  test("writes zero when the last photo is removed", async () => {
    // The card's indicator reads this, so the count has to fall as well as
    // rise — a photo indicator that never clears is the visible bug.
    const {db, state} = makeDb({count: 0});
    await expect(recountPictures("appt1", {db})).resolves.toBe(0);
    expect(state.updates[0].patch).toEqual({pictureCount: 0});
  });

  test("tolerates the parent being already deleted", async () => {
    // The cascade deletes photos when an appointment goes, and each of those
    // deletes fires this trigger. Racing a NOT_FOUND is the normal path, not an
    // error — and `update()` (not set+merge) is what stops it resurrecting the
    // appointment as a count-only stub.
    const notFound = Object.assign(new Error("missing"), {code: 5});
    const {db, state} = makeDb({count: 0, updateError: notFound});
    await expect(recountPictures("appt1", {db})).resolves.toBe(-1);
    expect(state.updates).toEqual([]);
  });

  test("rethrows any other write failure", async () => {
    const denied = Object.assign(new Error("denied"), {code: 7});
    const {db} = makeDb({count: 1, updateError: denied});
    await expect(recountPictures("appt1", {db})).rejects.toThrow("denied");
  });
});

describe("debouncedRecountPictures collapses one batch", () => {
  test("ten image creates in one batch produce exactly ONE parent update",
      async () => {
        // appendAppointmentPictures commits N image docs in one WriteBatch, so
        // N triggers land on the same parent within milliseconds. Each parent
        // write also re-fires notifyAppointmentChanges, so the un-debounced
        // cost of ten photos was 10 recounts + 11 notification invocations for
        // one user action.
        const {db, state} = makeDb({count: 10});
        let openGate = () => {};
        const gate = new Promise((resolve) => {
          openGate = resolve;
        });
        const runs = Array.from({length: 10}, () =>
          debouncedRecountPictures("appt1", {
            db, logger: quietLogger(), sleep: () => gate,
          }));
        // Let every sibling's claim attempt settle before the winner releases,
        // which is what a real batch's simultaneous triggers do.
        await flush();
        openGate();
        const results = await Promise.all(runs);

        expect(state.updates).toEqual([
          {path: "appointments/appt1", patch: {pictureCount: 10}},
        ]);
        expect(state.claimCreates).toHaveLength(1);
        expect(results.filter((r) => r.skipped)).toHaveLength(9);
      });

  test("the one write it makes is the absolute aggregate, not a delta",
      async () => {
        const {db, state} = makeDb({count: 7});
        const result = await debouncedRecountPictures(
            "appt1", {db, logger: quietLogger(), sleep: async () => {}});
        expect(result).toEqual({skipped: false, count: 7});
        expect(state.updates[0].patch).toEqual({pictureCount: 7});
      });

  test("releases the claim BEFORE running the aggregate", async () => {
    // The whole safety argument for the debounce. A suppressed sibling's photo
    // was committed before its trigger fired, and its trigger fired before this
    // release — so an aggregate that runs after the release necessarily sees
    // it. Count first and release after, and a photo written in that gap would
    // be both suppressed and uncounted.
    const {db, state} = makeDb({count: 2});
    await debouncedRecountPictures(
        "appt1", {db, logger: quietLogger(), sleep: async () => {}});
    expect(state.ops).toEqual(["claim", "release", "count", "update"]);
  });

  test("a suppressed sibling writes nothing at all", async () => {
    const {db, state} = makeDb({count: 4});
    const now = new Date(1000000);
    state.claims.set("appt1", {claimedAt: now});
    const result = await debouncedRecountPictures("appt1", {
      db, logger: quietLogger(), now, sleep: async () => {},
    });
    expect(result).toEqual({skipped: true, count: null});
    expect(state.updates).toEqual([]);
    expect(state.ops).toEqual([]);
  });
});

describe("the replay self-heal survives the debounce", () => {
  test("a later independent write still recounts", async () => {
    // The offline queue replays `set(..., {merge: true})` on the DERIVED doc
    // id, and the backfill re-runs — those two are the ONLY self-heal
    // pictureCount has. A debounce whose claim outlived its batch would eat
    // them and leave a wrong count wrong forever.
    const {db, state} = makeDb({count: 2});
    const deps = {db, logger: quietLogger(), sleep: async () => {}};
    await debouncedRecountPictures("appt1", deps);
    state.count = 3; // a replay landing a photo the first pass never saw
    const second = await debouncedRecountPictures("appt1", deps);

    expect(second).toEqual({skipped: false, count: 3});
    expect(state.updates.map((u) => u.patch)).toEqual([
      {pictureCount: 2}, {pictureCount: 3},
    ]);
  });

  test("the claim does not survive its own pass", async () => {
    const {db, state} = makeDb({count: 1});
    await debouncedRecountPictures(
        "appt1", {db, logger: quietLogger(), sleep: async () => {}});
    expect(state.claims.has("appt1")).toBe(false);
  });

  test("an abandoned claim is taken over rather than obeyed", async () => {
    // An invocation killed between claiming and releasing leaves a claim
    // behind. Waiting for the TTL policy to sweep it would suspend the
    // self-heal for as long as that takes, so staleness is enforced in code.
    const claimedAt = new Date(1000000);
    const now = new Date(claimedAt.getTime() + RECOUNT_CLAIM_STALE_MS + 1);
    const {db, state} = makeDb({count: 5});
    state.claims.set("appt1", {claimedAt});

    const result = await debouncedRecountPictures("appt1", {
      db, logger: quietLogger(), now, sleep: async () => {},
    });
    expect(result).toEqual({skipped: false, count: 5});
    expect(state.claimSets).toHaveLength(1);
    expect(state.updates[0].patch).toEqual({pictureCount: 5});
  });

  test("a claim with no usable timestamp is taken over", async () => {
    // A doc that vanished mid-read, or one written by an older shape, is the
    // opposite of a live claim. Reading it as live would fail closed in the
    // one direction that loses data.
    const {db, state} = makeDb({count: 6});
    state.claims.set("appt1", {});
    await debouncedRecountPictures(
        "appt1", {db, logger: quietLogger(), sleep: async () => {}});
    expect(state.updates[0].patch).toEqual({pictureCount: 6});
  });

  test("a claim ledger failure FAILS OPEN and still recounts", async () => {
    // An extra parent write is exactly the old behaviour; a skipped recount is
    // a wrong count with nothing left to notice it.
    const {db, state} = makeDb({
      count: 8, claimCreateError: Object.assign(new Error("nope"), {code: 13}),
    });
    const result = await debouncedRecountPictures(
        "appt1", {db, logger: quietLogger(), sleep: async () => {}});
    expect(result).toEqual({skipped: false, count: 8});
    expect(state.updates[0].patch).toEqual({pictureCount: 8});
  });

  test("a failed release does not stop the recount", async () => {
    const {db, state} = makeDb({
      count: 2, claimDeleteError: new Error("release failed"),
    });
    const result = await debouncedRecountPictures(
        "appt1", {db, logger: quietLogger(), sleep: async () => {}});
    expect(result).toEqual({skipped: false, count: 2});
    expect(state.updates[0].patch).toEqual({pictureCount: 2});
  });

  test("stamps an absolute expiresAt for the TTL policy", async () => {
    // Firestore TTL policies use expiration offset 0, so the stored value must
    // be the instant of deletion, not a duration.
    const now = new Date(1000000);
    const {db, state} = makeDb({count: 1});
    await debouncedRecountPictures("appt1", {
      db, logger: quietLogger(), now, sleep: async () => {},
    });
    const {claimedAt, expiresAt} = state.claimCreates[0].data;
    expect(claimedAt).toEqual(now);
    expect(expiresAt.getTime())
        .toBe(now.getTime() + RECOUNT_CLAIM_TTL_MS);
  });
});

describe("debouncedRecountPictures and a missing parent", () => {
  test("swallows a NOT_FOUND parent rather than throwing", async () => {
    // The cascade has just removed the photos; racing it is the normal path.
    const notFound = Object.assign(new Error("missing"), {code: 5});
    const {db, state} = makeDb({count: 0, updateError: notFound});
    const result = await debouncedRecountPictures(
        "appt1", {db, logger: quietLogger(), sleep: async () => {}});
    expect(result).toEqual({skipped: false, count: -1});
    expect(state.updates).toEqual([]);
  });

  test("still rethrows a real write failure, having released first",
      async () => {
        // Rethrowing is what makes `retry: true` mean anything, and the
        // already-released claim is what lets the retry re-claim instead of
        // suppressing itself.
        const denied = Object.assign(new Error("denied"), {code: 7});
        const {db, state} = makeDb({count: 1, updateError: denied});
        await expect(debouncedRecountPictures(
            "appt1", {db, logger: quietLogger(), sleep: async () => {}}))
            .rejects.toThrow("denied");
        expect(state.claimDeletes).toEqual(["appt1"]);
        expect(state.claims.has("appt1")).toBe(false);
      });
});

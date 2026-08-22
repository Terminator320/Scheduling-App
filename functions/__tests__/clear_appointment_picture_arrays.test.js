/**
 * The CONTRACT step's cleanup script deletes data nothing can rebuild: the
 * legacy `pictures` array is the last record of a photo that was never copied
 * into `appointments/{id}/images`. So the property worth pinning is not what
 * it clears — it is what it REFUSES to clear.
 */
const {
  planClear,
  needsRecount,
  storedImageIds,
} = require("../scripts/clear-appointment-picture-arrays");
const {appointmentImageDocId} = require("../appointment_image_ids");

/**
 * A stored array entry with a storage path.
 * @param {string} name The stored file name.
 * @return {!Object} One `pictures[]` entry.
 */
const photo = (name) => ({
  storagePath: `appointments/a1/images/${name}`,
  url: `https://firebasestorage.googleapis.com/v0/b/x/o/${name}?alt=media`,
  fileName: name,
});

/**
 * The subcollection ids the given photos would have been copied to.
 * @param {!Array<!Object>} pictures
 * @return {!Set<string>}
 */
const idsOf = (pictures) =>
  new Set(pictures.map((p) => appointmentImageDocId(p)));

describe("planClear", () => {
  test("clears when every entry is already in the subcollection", () => {
    const pictures = [photo("1_a.jpg"), photo("2_b.jpg")];

    expect(planClear(pictures, idsOf(pictures))).toEqual({
      clear: true,
      missing: [],
      identityless: 0,
    });
  });

  test("REFUSES the whole appointment when one photo was not copied", () => {
    // Not "clear the ones that were copied": the array is a single field, so
    // there is no partial delete — and the uncopied photo's only record is the
    // entry that would go with it.
    const copied = photo("1_a.jpg");
    const uncopied = photo("2_b.jpg");

    const plan = planClear([copied, uncopied], idsOf([copied]));

    expect(plan.clear).toBe(false);
    expect(plan.missing).toEqual([appointmentImageDocId(uncopied)]);
  });

  test("REFUSES an entry with no identity at all", () => {
    // No storagePath and no url: unrenderable, so no backfill could ever have
    // copied it and no re-run will change that. Clearing would destroy the
    // only evidence it existed, which is a person's call.
    const plan = planClear([{fileName: "orphan.jpg"}], new Set());

    expect(plan.clear).toBe(false);
    expect(plan.identityless).toBe(1);
    expect(plan.missing).toEqual([]);
  });

  test("an identity-less entry blocks a clear beside covered ones", () => {
    const covered = photo("1_a.jpg");

    const plan = planClear([covered, {}], idsOf([covered]));

    expect(plan.clear).toBe(false);
    expect(plan.identityless).toBe(1);
  });

  test("a LEGACY url-only entry counts as covered when its doc exists", () => {
    // Documents written before `storagePath` existed key on their url, and the
    // backfill carries that url across — so they are coverable, unlike the
    // identity-less case above.
    const legacy = {
      url: "https://firebasestorage.googleapis.com/v0/b/x/o/old.jpg?alt=media",
    };

    expect(planClear([legacy], idsOf([legacy])).clear).toBe(true);
  });

  test("an empty array is trivially clearable", () => {
    expect(planClear([], new Set())).toEqual({
      clear: true,
      missing: [],
      identityless: 0,
    });
  });

  test("extra subcollection documents do not block the clear", () => {
    // Photos added after the last backfill pass live only in the
    // subcollection. They are the normal state, not a mismatch.
    const inBoth = photo("1_a.jpg");
    const stored = idsOf([inBoth, photo("9_newer.jpg")]);

    expect(planClear([inBoth], stored).clear).toBe(true);
  });
});

describe("storedImageIds", () => {
  test("reads ids only, from the images subcollection", async () => {
    const calls = [];
    const doc = {
      ref: {
        collection: (name) => {
          calls.push(name);
          return {
            select: () => ({
              get: async () => ({docs: [{id: "x"}, {id: "y"}]}),
            }),
          };
        },
      },
    };

    expect(await storedImageIds(doc)).toEqual(new Set(["x", "y"]));
    // `select()` with no fields: the bodies are irrelevant and this runs once
    // per appointment that still carries an array.
    expect(calls).toEqual(["images"]);
  });
});

/**
 * The script's SECOND job, and the one the prose elsewhere leans on: after it
 * runs, `pictureCount` is supposed to be right on every appointment, not only
 * on the ones that still carried an array. It used to `continue` past a
 * document with no array, so an appointment whose array had already been
 * emptied while its counter write failed kept a wrong count with nothing left
 * to notice it.
 */
describe("needsRecount", () => {
  test("an absent counter agrees with an empty subcollection", () => {
    // `undefined` is how the client parses a missing field, so this is the
    // common shape and must not generate a write.
    expect(needsRecount({}, 0)).toBe(false);
  });

  test("an absent counter DISAGREES with photos that exist", () => {
    // The shape that hid a job's photo indicator forever.
    expect(needsRecount({}, 3)).toBe(true);
  });

  test("a matching counter needs nothing, so a re-run writes nothing", () => {
    expect(needsRecount({pictureCount: 2}, 2)).toBe(false);
  });

  test("a stale counter is re-stamped in either direction", () => {
    expect(needsRecount({pictureCount: 5}, 2)).toBe(true);
    expect(needsRecount({pictureCount: 1}, 4)).toBe(true);
  });

  test("a non-integer counter is not trusted as a number", () => {
    // A console edit or a legacy write can leave anything here. Reading "2"
    // as 2 would skip a document whose stored value is not a number at all.
    expect(needsRecount({pictureCount: "2"}, 2)).toBe(true);
    expect(needsRecount({pictureCount: null}, 0)).toBe(false);
    expect(needsRecount({pictureCount: 1.5}, 0)).toBe(true);
  });
});

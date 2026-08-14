/**
 * @fileoverview Tests the two orchestration bodies behind the photo
 * subcollection. Both take an injected `db`, so neither needs the emulator.
 *
 * The cascade is the one that matters most: Firestore does not delete a
 * subcollection with its parent, so if `purgeAppointmentImages` regresses,
 * every appointment delete leaves photo documents orphaned under a parent that
 * no longer exists — invisible in the console, unreachable by every query the
 * app makes, and with nothing anywhere reporting it.
 */
const {
  purgeAppointmentImages,
  recountPictures,
  IMAGES_SUBCOLLECTION,
} = require("../appointment_images");

/**
 * Minimal Firestore fake recording recursiveDelete targets and parent updates.
 * @param {!Object=} config `{count, updateError}`.
 * @return {!Object}
 */
function makeDb(config = {}) {
  const recursiveDeletes = [];
  const updates = [];
  const db = {
    recursiveDelete: async (ref) => {
      if (config.deleteError) throw config.deleteError;
      recursiveDeletes.push(ref._path);
      return undefined;
    },
    collection(name) {
      return {
        doc(id) {
          const parentPath = `${name}/${id}`;
          return {
            _path: parentPath,
            update: async (patch) => {
              if (config.updateError) throw config.updateError;
              updates.push({path: parentPath, patch});
            },
            collection(sub) {
              return {
                _path: `${parentPath}/${sub}`,
                count: () => ({
                  get: async () => ({
                    data: () => ({count: config.count || 0}),
                  }),
                }),
              };
            },
          };
        },
      };
    },
  };
  return {db, recursiveDeletes, updates};
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
    const {db, recursiveDeletes} = makeDb();
    await purgeAppointmentImages("appt1", {db});
    expect(recursiveDeletes).toEqual(["appointments/appt1/images"]);
  });

  test("targets the subcollection, never the parent document", async () => {
    // A ref one level too high deletes the appointment's siblings' data or the
    // appointment itself. Worth pinning explicitly — the bug would be silent
    // and catastrophic rather than silent and merely untidy.
    const {db, recursiveDeletes} = makeDb();
    await purgeAppointmentImages("appt1", {db});
    expect(recursiveDeletes[0]).not.toBe("appointments/appt1");
    expect(recursiveDeletes[0].endsWith(`/${IMAGES_SUBCOLLECTION}`)).toBe(true);
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
    const {db, updates} = makeDb({count: 3});
    await expect(recountPictures("appt1", {db})).resolves.toBe(3);
    expect(updates).toEqual([
      {path: "appointments/appt1", patch: {pictureCount: 3}},
    ]);
  });

  test("writes zero when the last photo is removed", async () => {
    // The card's indicator reads this, so the count has to fall as well as
    // rise — a photo indicator that never clears is the visible bug.
    const {db, updates} = makeDb({count: 0});
    await expect(recountPictures("appt1", {db})).resolves.toBe(0);
    expect(updates[0].patch).toEqual({pictureCount: 0});
  });

  test("tolerates the parent being already deleted", async () => {
    // The cascade deletes photos when an appointment goes, and each of those
    // deletes fires this trigger. Racing a NOT_FOUND is the normal path, not an
    // error — and `update()` (not set+merge) is what stops it resurrecting the
    // appointment as a count-only stub.
    const notFound = Object.assign(new Error("missing"), {code: 5});
    const {db, updates} = makeDb({count: 0, updateError: notFound});
    await expect(recountPictures("appt1", {db})).resolves.toBe(-1);
    expect(updates).toEqual([]);
  });

  test("rethrows any other write failure", async () => {
    const denied = Object.assign(new Error("denied"), {code: 7});
    const {db} = makeDb({count: 1, updateError: denied});
    await expect(recountPictures("appt1", {db})).rejects.toThrow("denied");
  });
});

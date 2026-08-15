const {Timestamp} = require("firebase-admin/firestore");
const {
  imageDoc,
  backfillOne,
} = require("../scripts/backfill-appointment-images");

/**
 * A batch that records what was written and how many times it committed.
 * @return {!Object} The fake batch.
 */
function fakeBatch() {
  return {
    sets: [],
    updates: [],
    commits: 0,
    set(ref, body, opts) {
      this.sets.push({ref, body, opts});
    },
    update(ref, body) {
      this.updates.push({ref, body});
    },
    async commit() {
      this.commits += 1;
    },
  };
}

/**
 * A minimal appointment snapshot over `pictures`.
 * @param {!Array<!Object>} pictures Stored array entries.
 * @return {!Object} The fake snapshot.
 */
function fakeDoc(pictures) {
  const imageDocs = [];
  const ref = {
    id: "appt-1",
    collection: () => ({
      doc: (id) => {
        const r = {id};
        imageDocs.push(r);
        return r;
      },
    }),
  };
  return {ref, imageDocs, data: () => ({pictures})};
}

describe("imageDoc", () => {
  test("omits `url` when a storagePath is present", () => {
    // A persisted download URL is a permanent, rules-free token. Photos render
    // from storagePath so every read re-evaluates storage.rules, so a copied
    // url would have no reader and would undo that gate.
    const doc = imageDoc({
      storagePath: "appointments/a1/images/x.jpg",
      url: "https://firebasestorage/…?alt=media&token=abc",
    });
    expect(doc.storagePath).toBe("appointments/a1/images/x.jpg");
    expect(doc.url).toBeUndefined();
  });

  test("KEEPS a legacy entry's url when it has no storagePath", () => {
    // Dropping it destroys the only thing that can render that photo.
    const doc = imageDoc({url: "https://firebasestorage/…?alt=media&token=a"});
    expect(doc.url).toBe("https://firebasestorage/…?alt=media&token=a");
    expect(doc.storagePath).toBe("");
  });

  test("round-trips uploadedAt from every shape the array holds", () => {
    const stamp = Timestamp.fromDate(new Date("2026-08-01T12:00:00Z"));
    expect(imageDoc({storagePath: "p", uploadedAt: stamp}).uploadedAt)
        .toBe(stamp);
    // The offline queue's carried-forward entries serialize ISO-8601.
    expect(imageDoc({storagePath: "p", uploadedAt: "2026-08-01T12:00:00Z"})
        .uploadedAt.toDate().toISOString())
        .toBe("2026-08-01T12:00:00.000Z");
    expect(imageDoc({storagePath: "p"}).uploadedAt).toBeNull();
    expect(imageDoc({storagePath: "p", uploadedAt: "nonsense"}).uploadedAt)
        .toBeNull();
  });
});

describe("backfillOne", () => {
  test("ATOMIC: photos and the count go in ONE batch, committed once", () => {
    // The stated guarantee. The client treats an EMPTY subcollection as "not
    // backfilled yet, use the array", so a half-copied appointment would
    // render a partial photo list with no error anywhere.
    const batch = fakeBatch();
    const db = {batch: () => batch};
    const doc = fakeDoc([
      {storagePath: "appointments/a1/images/1.jpg"},
      {storagePath: "appointments/a1/images/2.jpg"},
    ]);

    return backfillOne(db, doc).then((result) => {
      expect(result).toEqual({copied: 2, skipped: 0});
      expect(batch.sets).toHaveLength(2);
      expect(batch.updates).toEqual([
        {ref: doc.ref, body: {pictureCount: 2}},
      ]);
      expect(batch.commits).toBe(1);
    });
  });

  test("writes with merge, so a second run overwrites rather than duplicates",
      () => {
        const batch = fakeBatch();
        const doc = fakeDoc([{storagePath: "appointments/a1/images/1.jpg"}]);

        return backfillOne({batch: () => batch}, doc).then(() => {
          expect(batch.sets[0].opts).toEqual({merge: true});
        });
      });

  test("an identity-less entry is SKIPPED and left out of pictureCount", () => {
    // No storagePath and no url: nothing to render and no legal document id.
    // The card's indicator must not promise a photo nobody can see.
    const batch = fakeBatch();
    const doc = fakeDoc([
      {storagePath: "appointments/a1/images/1.jpg"},
      {fileName: "orphan.jpg"},
    ]);

    return backfillOne({batch: () => batch}, doc).then((result) => {
      expect(result).toEqual({copied: 1, skipped: 1});
      expect(batch.updates[0].body).toEqual({pictureCount: 1});
    });
  });

  test("an all-unrenderable array still stamps a count of zero", () => {
    // So it reads as no photos rather than promising one.
    const batch = fakeBatch();
    const doc = fakeDoc([{fileName: "orphan.jpg"}]);

    return backfillOne({batch: () => batch}, doc).then((result) => {
      expect(result).toEqual({copied: 0, skipped: 1});
      expect(batch.sets).toHaveLength(0);
      expect(batch.updates[0].body).toEqual({pictureCount: 0});
      expect(batch.commits).toBe(1);
    });
  });

  test("NEVER touches the `pictures` array — copy, not move", () => {
    // The shipped build reads photos from that array; clearing it here blanks
    // every photo on every phone until it updates.
    const batch = fakeBatch();
    const doc = fakeDoc([{storagePath: "appointments/a1/images/1.jpg"}]);

    return backfillOne({batch: () => batch}, doc).then(() => {
      for (const update of batch.updates) {
        expect(Object.keys(update.body)).toEqual(["pictureCount"]);
      }
    });
  });
});

"use strict";

/**
 * Rotation of the permanent, rules-free Storage download tokens a deactivated
 * employee's device received inside every assigned appointment's
 * `pictures[]`. Nothing client-side can invalidate a link somebody already
 * holds, so this is the only mechanism there is — and it must never be able
 * to blank a photo, throw into a `retry: true` trigger, or leave the stored
 * `url` pointing at a token it just killed.
 */

const {
  ROTATE_APPOINTMENT_MAX,
  storagePathOf,
  downloadUrl,
  rotateObjectToken,
  rotatePictures,
  rotateAssignedImageTokens,
} = require("../appointment_image_tokens");

const BUCKET = "schedulingapp-88727.appspot.com";
const PATH = "appointments/a1/images/1723_photo.jpg";
const LEGACY_URL = "https://firebasestorage.googleapis.com/v0/b/" +
    `${BUCKET}/o/appointments%2Fa1%2Fimages%2Fold.jpg?alt=media&token=dead`;

/**
 * Storage bucket stand-in recording every metadata write.
 * @param {{failOn: (string|undefined)}=} opts
 * @return {!Object} `{bucket, writes}`.
 */
function fakeBucket(opts) {
  const writes = [];
  const failOn = (opts || {}).failOn;
  return {
    writes,
    bucket: {
      name: BUCKET,
      file(path) {
        return {
          async getMetadata() {
            if (path === failOn) throw new Error("object-not-found");
            return [{contentType: "image/jpeg", metadata: {
              firebaseStorageDownloadTokens: "old-token",
              custom: "kept",
            }}];
          },
          async setMetadata(meta) {
            if (path === failOn) throw new Error("object-not-found");
            writes.push({path, meta});
          },
        };
      },
    },
  };
}

/**
 * Firestore stand-in over a fixed list of appointment docs.
 * @param {!Array<!Object>} records `{id, pictures}` shapes.
 * @param {{queryThrows: (boolean|undefined),
 *          updateThrows: (string|undefined)}=} opts
 * @return {!Object} `{db, updates, orders, limits}`.
 */
function fakeDb(records, opts) {
  const updates = [];
  const orders = [];
  const limits = [];
  const {queryThrows = false, updateThrows, backstopThrows = false} =
    opts || {};
  const docs = records.map((r) => ({
    id: r.id,
    data: () => ({
      pictures: r.pictures,
      // Defaults to a real instant so an ordinary case exercises the ordered
      // pass. Pass `endTime: null` to model a legacy or console-written doc.
      endTime: r.endTime === undefined ? 1723000000000 : r.endTime,
    }),
    ref: {
      async update(patch) {
        if (r.id === updateThrows) throw new Error("unavailable");
        updates.push({id: r.id, patch});
      },
    },
  }));
  // A FRESH query per `collection()` call, so the two passes cannot share
  // `ordered` state — and an ordered query EXCLUDES docs missing the ordered
  // field, which is the Firestore behaviour the backstop exists to cover and
  // the one thing this fake has to get right.
  const makeQuery = () => {
    let ordered = false;
    const query = {
      where: () => query,
      orderBy: (field, dir) => {
        ordered = true;
        orders.push([field, dir]);
        return query;
      },
      limit: (n) => {
        limits.push(n);
        return query;
      },
      get: async () => {
        if (ordered && queryThrows) throw new Error("FAILED_PRECONDITION");
        if (!ordered && backstopThrows) throw new Error("unavailable");
        return {
          docs: ordered ?
            docs.filter((d) => d.data().endTime != null) :
            docs,
        };
      },
    };
    return query;
  };
  return {db: {collection: () => makeQuery()}, updates, orders, limits};
}

/** @return {!Object} A logger recording every level. */
function fakeLogger() {
  const lines = [];
  const push = (level) => (msg, meta) => lines.push([level, msg, meta]);
  return {lines, warn: push("warn"), error: push("error"), info: push("info")};
}

describe("storagePathOf", () => {
  test("prefers the stored storagePath", () => {
    expect(storagePathOf({storagePath: PATH, url: LEGACY_URL})).toBe(PATH);
  });

  test("falls back to decoding a LEGACY url", () => {
    // A doc written before storagePath existed has only its url, and that url
    // is the only handle there is — so the oldest photos must be rotatable
    // too, or this closes the exposure everywhere except where it is worst.
    expect(storagePathOf({url: LEGACY_URL}))
        .toBe("appointments/a1/images/old.jpg");
  });

  test("an entry with no usable handle yields nothing", () => {
    expect(storagePathOf({})).toBe("");
    expect(storagePathOf({url: "https://example.com/not-storage"})).toBe("");
    expect(storagePathOf(null)).toBe("");
    expect(storagePathOf({storagePath: 42})).toBe("");
  });
});

describe("downloadUrl", () => {
  test("reproduces the shape the client persisted", () => {
    // Byte-for-byte, or a build that renders from the stored url stops
    // recognising it. Note the path is percent-encoded, slashes included.
    expect(downloadUrl(BUCKET, PATH, "t1")).toBe(
        `https://firebasestorage.googleapis.com/v0/b/${BUCKET}/o/` +
        "appointments%2Fa1%2Fimages%2F1723_photo.jpg?alt=media&token=t1");
  });
});

describe("rotateObjectToken", () => {
  test("writes a NEW token and keeps every other metadata key", () => {
    const {bucket, writes} = fakeBucket();
    return rotateObjectToken(bucket, PATH).then((url) => {
      const written = writes[0].meta.metadata;
      expect(written.firebaseStorageDownloadTokens).not.toBe("old-token");
      expect(written.firebaseStorageDownloadTokens).toEqual(
          expect.stringMatching(/^[0-9a-f-]{36}$/));
      // contentType/cacheControl are set at upload; dropping the sibling keys
      // would change how the object is served.
      expect(written.custom).toBe("kept");
      expect(url).toContain(
          `token=${written.firebaseStorageDownloadTokens}`);
    });
  });
});

describe("rotatePictures", () => {
  test("returns a new array carrying the fresh urls", async () => {
    const {bucket} = fakeBucket();
    const next = await rotatePictures({bucket}, [
      {storagePath: PATH, url: "old", fileName: "p.jpg"},
    ]);
    expect(next[0].url).not.toBe("old");
    expect(next[0].url).toContain("alt=media&token=");
    // Everything else on the entry survives.
    expect(next[0].fileName).toBe("p.jpg");
    expect(next[0].storagePath).toBe(PATH);
  });

  test("a photo whose object cannot be rotated keeps its entry verbatim",
      async () => {
        // A failure here must never blank a photo that is still perfectly
        // readable by everyone who is still entitled to it.
        const {bucket} = fakeBucket({failOn: PATH});
        const logger = fakeLogger();
        const entry = {storagePath: PATH, url: "still-works"};
        const next = await rotatePictures({bucket, logger}, [
          entry, {storagePath: "appointments/a1/images/ok.jpg", url: "b"},
        ]);
        expect(next[0]).toEqual(entry);
        expect(next[1].url).not.toBe("b");
        expect(logger.lines[0][1])
            .toBe("imageTokens: object rotation failed");
      });

  test("nothing rotatable means no write at all", async () => {
    const {bucket} = fakeBucket();
    expect(await rotatePictures({bucket}, [{fileName: "orphan.jpg"}]))
        .toBeNull();
  });
});

describe("rotateAssignedImageTokens", () => {
  test("rewrites the stored url so old builds keep rendering", async () => {
    // Rotating alone would blank these photos on any phone still rendering
    // from `pictures[].url` — the very builds that write exists for. The
    // deactivated employee cannot read the doc any more, so they never see
    // the replacement.
    const {bucket} = fakeBucket();
    const {db, updates} = fakeDb([
      {id: "a1", pictures: [{storagePath: PATH, url: "old"}]},
    ]);

    const res = await rotateAssignedImageTokens({db, bucket}, "e1");

    expect(res).toEqual({appointments: 1, photos: 1});
    expect(updates).toHaveLength(1);
    expect(updates[0].patch.pictures[0].url).toContain("alt=media&token=");
    expect(updates[0].patch.pictures[0].url).not.toBe("old");
  });

  test("passes the LAZILY resolved bucket down to the rotation", async () => {
    // The regression this pins: `rotatePictures` reads `deps.bucket`, and the
    // resolved bucket used to land in a local instead. Every test injects one,
    // and `bridge.js` passes only `{db, logger}` — so the branch production
    // ALWAYS takes was the one branch nothing covered, and on it every
    // rotation threw into this module's swallow. The control reported
    // "nothing rotated" while rotating nothing.
    const {bucket, writes} = fakeBucket();
    const {db, updates} = fakeDb([
      {id: "a1", pictures: [{storagePath: PATH, url: "old"}]},
    ]);

    // No `bucket` in deps — exactly the shape `syncUsersByUid` calls with.
    const res = await rotateAssignedImageTokens(
        {db, bucket: null, resolveBucket: () => bucket}, "e1");

    expect(res).toEqual({appointments: 1, photos: 1});
    expect(writes).toHaveLength(1);
    expect(updates[0].patch.pictures[0].url).not.toBe("old");
  });

  test("an appointment with NO endTime is still rotated", async () => {
    // The ordered pass cannot see it — Firestore omits documents missing the
    // field it orders by — so without the backstop that job's photos kept
    // their permanent, rules-free download tokens forever, and nothing
    // logged it. The Dart model never writes such a record; legacy and
    // console-written docs are how it reaches the server.
    const {bucket} = fakeBucket();
    const {db, updates} = fakeDb([
      {id: "dated", pictures: [{storagePath: PATH, url: "old"}]},
      {id: "undated", endTime: null,
        pictures: [{storagePath: PATH, url: "old"}]},
    ]);

    const res = await rotateAssignedImageTokens({db, bucket}, "e1");

    expect(res).toEqual({appointments: 2, photos: 2});
    expect(updates.map((u) => u.id).sort()).toEqual(["dated", "undated"]);
  });

  test("the backstop rotates each undated job ONCE", async () => {
    // The unordered scan returns the dated docs too. They are deduped by id,
    // so a dated job is never rotated twice — a second pass would mint a
    // fresh token and rewrite `url` again for nothing.
    const {bucket, writes} = fakeBucket();
    const {db, updates} = fakeDb([
      {id: "a1", pictures: [{storagePath: PATH}]},
      {id: "a2", pictures: [{storagePath: PATH}]},
    ]);

    await rotateAssignedImageTokens({db, bucket}, "e1");

    expect(updates).toHaveLength(2);
    expect(writes).toHaveLength(2);
  });

  test("a failed backstop keeps the ordered pass's results", async () => {
    const {bucket} = fakeBucket();
    const logger = fakeLogger();
    const {db, updates} = fakeDb(
        [{id: "a1", pictures: [{storagePath: PATH}]}],
        {backstopThrows: true});

    const res = await rotateAssignedImageTokens({db, bucket, logger}, "e1");

    expect(res).toEqual({appointments: 1, photos: 1});
    expect(updates).toHaveLength(1);
    expect(logger.lines.some(([lvl, msg]) =>
      lvl === "warn" && msg.includes("backstop scan failed"))).toBe(true);
  });

  test("orders newest first and bounds the scan", async () => {
    const {bucket} = fakeBucket();
    const {db, orders, limits} = fakeDb([]);

    await rotateAssignedImageTokens({db, bucket}, "e1");

    // Newest first is what makes the cap defensible — those are the photos a
    // just-departed employee most plausibly still holds a link to. Exactly
    // ONE ordered query: the backstop must stay unordered, or it inherits the
    // very exclusion it exists to cover.
    expect(orders).toEqual([["endTime", "desc"]]);
    // BOTH passes bounded — an unbounded backstop would read every
    // appointment this person was ever assigned to.
    expect(limits).toEqual([ROTATE_APPOINTMENT_MAX, ROTATE_APPOINTMENT_MAX]);
  });

  test("warns when the cap is hit", async () => {
    const {bucket} = fakeBucket();
    const records = Array.from({length: ROTATE_APPOINTMENT_MAX}, (_, i) => ({
      id: `a${i}`, pictures: [],
    }));
    const {db} = fakeDb(records);
    const logger = fakeLogger();

    await rotateAssignedImageTokens({db, bucket, logger}, "e1");

    expect(logger.lines[0][1]).toBe(
        "imageTokens: appointment cap hit; older photos keep their " +
        "download tokens");
  });

  test("an appointment with no photos is not written", async () => {
    const {bucket, writes} = fakeBucket();
    const {db, updates} = fakeDb([
      {id: "a1", pictures: []},
      {id: "a2", pictures: undefined},
    ]);

    const res = await rotateAssignedImageTokens({db, bucket}, "e1");

    expect(updates).toEqual([]);
    expect(writes).toEqual([]);
    expect(res).toEqual({appointments: 0, photos: 0});
  });

  test("NEVER throws — a failed query returns zero counts", async () => {
    // syncUsersByUid runs under retry:true, so a rethrow would re-run the
    // whole handler and re-rotate everything already done, for something a
    // retry cannot fix.
    const {bucket} = fakeBucket();
    const {db} = fakeDb([], {queryThrows: true});
    const logger = fakeLogger();

    await expect(rotateAssignedImageTokens({db, bucket, logger}, "e1"))
        .resolves.toEqual({appointments: 0, photos: 0});
    expect(logger.lines[0][0]).toBe("error");
  });

  test("one failing appointment does not stop the rest", async () => {
    const {bucket} = fakeBucket();
    const {db, updates} = fakeDb([
      {id: "bad", pictures: [{storagePath: PATH}]},
      {id: "good", pictures: [{storagePath: PATH}]},
    ], {updateThrows: "bad"});
    const logger = fakeLogger();

    const res = await rotateAssignedImageTokens({db, bucket, logger}, "e1");

    expect(updates.map((u) => u.id)).toEqual(["good"]);
    expect(res.appointments).toBe(1);
    expect(logger.lines.some(([, msg]) =>
      msg === "imageTokens: appointment rotation failed")).toBe(true);
  });

  test("no resolvable bucket logs an error rather than throwing", async () => {
    // Reached only in prod, and only when Storage is unavailable — but this
    // sits inside a retry:true trigger, so it must degrade rather than loop.
    const {db} = fakeDb([]);
    const logger = fakeLogger();

    await expect(rotateAssignedImageTokens({db, logger}, "e1"))
        .resolves.toEqual({appointments: 0, photos: 0});
    expect(logger.lines[0]).toEqual([
      "error",
      "imageTokens: no Storage bucket; tokens NOT rotated",
      expect.objectContaining({employeeDocId: "e1"}),
    ]);
  });
});

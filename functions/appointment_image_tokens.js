/**
 * Rotates the Storage download token on every photo a deactivated employee
 * could have captured, and rewrites the stored `url` to the fresh one.
 *
 * ## Why this exists
 *
 * `ImageStorageService.uploadImage` calls `getDownloadURL()` and persists the
 * result into the appointment's `pictures[]` array. That URL carries the
 * object's `firebaseStorageDownloadTokens` value, which is **stable per
 * object and never expires**, and fetching it serves the bytes over plain
 * HTTPS with **no auth and no `storage.rules` evaluation**. Every assigned
 * employee receives that array on their device, so a modified client — or
 * simply reading the app's local Firestore persistence — yields links that
 * keep working forever, including after `deactivateEmployee` has revoked the
 * credential, disabled the Auth account and flipped the `status == 'active'`
 * gate.
 *
 * Rendering no longer mints one (`AppointmentImageLoader` fetches bytes
 * through the SDK, so rules are evaluated on every fetch), and the `url`
 * write is scheduled to go at the photo-subcollection CONTRACT step — but
 * until then the app is still *minting and persisting a fresh permanent link
 * per upload*, so the exposure is ongoing rather than historical. Rotating
 * the token is the only thing that can invalidate a link somebody already
 * holds; nothing client-side can.
 *
 * ## Why it also rewrites the stored URL
 *
 * Rotating alone would blank those photos on any phone still running a build
 * that renders from `pictures[].url` — the very builds the `url` write exists
 * for. Minting the replacement and writing it back in the same pass keeps
 * them working: a deactivated employee cannot read the appointment document
 * any more (the rules gate on `status == 'active'`), so they never see the
 * new URL, while everyone still entitled picks it up on their next read.
 *
 * ## What this does NOT claim
 *
 * It is **defense-in-depth, not the access control** — `firestore.rules` and
 * `storage.rules` remain the real gate. It is bounded
 * ([ROTATE_APPOINTMENT_MAX]), best-effort per object, and does not revoke a
 * link to a photo on an appointment outside that bound. It also cannot stop
 * an entitled person screenshotting or re-sharing a photo they can
 * legitimately see. Retire this module at the CONTRACT step, once no build
 * renders from a stored `url` and nothing mints one.
 */

const {randomUUID} = require("crypto");

/**
 * How many of the employee's appointments one deactivation rotates, newest
 * first. A ceiling rather than an exhaustive pass, with the warn-at-cap
 * posture the sweep ceilings use: the newest jobs are the ones whose photos
 * were most plausibly captured, and understating what was revoked must be
 * visible in the log.
 */
const ROTATE_APPOINTMENT_MAX = 500;

/** Appointments rotated at once, so one deactivation isn't a serial crawl. */
const ROTATE_CONCURRENCY = 8;

/**
 * Photos rotated at once WITHIN one appointment.
 *
 * The two bounds multiply — this loop runs inside the appointment one — so
 * the real ceiling on concurrent GCS chains is the product, not either
 * number. Same discipline as `PRUNE_CHUNK` in `live_activity_registry.js`.
 */
const ROTATE_PHOTO_CONCURRENCY = 8;

/**
 * The Storage object path a stored picture entry refers to, or `""` when
 * there is none to resolve.
 *
 * Hand-mirrors `ImageStorageService._pathFromUrl`: a doc written before
 * `storagePath` was stored has only its `url`, and that URL is then the only
 * handle there is — so a legacy entry must be rotatable too, or the exposure
 * this module closes stays open on exactly the oldest photos.
 *
 * @param {?Object} picture One `pictures[]` entry.
 * @return {string}
 */
function storagePathOf(picture) {
  const entry = picture || {};
  if (typeof entry.storagePath === "string" && entry.storagePath) {
    return entry.storagePath;
  }
  const url = typeof entry.url === "string" ? entry.url : "";
  if (!url) return "";
  const parts = url.split("/o/");
  if (parts.length < 2) return "";
  try {
    return decodeURIComponent(parts[1].split("?")[0]);
  } catch (err) {
    return "";
  }
}

/**
 * The Firebase Storage download URL for `path` under `token`.
 *
 * Hand-built rather than re-read through `getDownloadURL()`: the Admin SDK's
 * signed-URL helpers mint a different (expiring) shape, and this has to
 * reproduce byte-for-byte what the client persisted, or an old build's
 * renderer stops recognising it.
 *
 * @param {string} bucketName Storage bucket, e.g. `my-app.appspot.com`.
 * @param {string} path Object path.
 * @param {string} token The object's download token.
 * @return {string}
 */
function downloadUrl(bucketName, path, token) {
  return "https://firebasestorage.googleapis.com/v0/b/" +
      `${bucketName}/o/${encodeURIComponent(path)}` +
      `?alt=media&token=${token}`;
}

/**
 * Sets a fresh `firebaseStorageDownloadTokens` on one object and returns its
 * new URL, or `""` when the object could not be rotated.
 *
 * Every other metadata key is carried through — `contentType` and
 * `cacheControl` are set at upload and dropping them would change how the
 * object is served.
 *
 * @param {!Object} bucket Admin Storage bucket.
 * @param {string} path Object path.
 * @return {!Promise<string>} The replacement URL, or "".
 */
async function rotateObjectToken(bucket, path) {
  const file = bucket.file(path);
  const [meta] = await file.getMetadata();
  const token = randomUUID();
  await file.setMetadata({
    metadata: {...((meta && meta.metadata) || {}),
      firebaseStorageDownloadTokens: token},
  });
  return downloadUrl(bucket.name, path, token);
}

/**
 * Rotates every photo of one appointment and returns the replacement
 * `pictures[]` array, or `null` when nothing changed.
 *
 * A picture whose object cannot be rotated keeps its stored entry verbatim:
 * a failure here must not blank a photo that is still perfectly readable.
 *
 * @param {!Object} deps `{bucket, logger}`.
 * @param {!Array<!Object>} pictures The stored array.
 * @return {!Promise<?Array<!Object>>}
 */
async function rotatePictures(deps, pictures) {
  const {bucket, logger} = deps;
  let changed = false;
  const next = pictures.slice();

  // Chunked, because this sits INSIDE the ROTATE_CONCURRENCY appointment
  // loop: the rules cap `pictures` at 100, so an unbounded fan-out here is up
  // to 8 x 100 concurrent GCS metadata chains — two HTTP requests each — from
  // one invocation. Every failure in this module is swallowed, so the way
  // that surfaces is not an error but the control quietly not running.
  for (let i = 0; i < next.length; i += ROTATE_PHOTO_CONCURRENCY) {
    const slice = next.slice(i, i + ROTATE_PHOTO_CONCURRENCY);
    await Promise.all(slice.map(async (picture, offset) => {
      const path = storagePathOf(picture);
      if (!path) return;
      try {
        const url = await rotateObjectToken(bucket, path);
        if (!url) return;
        changed = true;
        next[i + offset] = {...picture, url};
      } catch (err) {
        if (logger) {
          logger.warn("imageTokens: object rotation failed", {
            path,
            error: err && err.message,
          });
        }
      }
    }));
  }
  return changed ? next : null;
}

/**
 * Resolves the default Storage bucket lazily.
 *
 * Deliberately NOT at module load: `maintenance.js` resolves one at load and
 * therefore throws on `require()` outside the emulator, which is exactly why
 * the only unattended deletion in this repo went untested for months.
 * `rotateAssignedImageTokens` takes an injected `bucket`, so jest never
 * reaches this — and when it IS reached and fails, the caller logs and
 * returns rather than throwing.
 *
 * @return {!Object}
 */
function defaultBucket() {
  // eslint-disable-next-line global-require
  return require("firebase-admin/storage").getStorage().bucket();
}

/**
 * Rotates the download token on every photo of every appointment
 * `employeeDocId` was assigned to, newest first.
 *
 * Never throws: this is defense-in-depth behind the rules' status gate, and
 * `syncUsersByUid` runs under `retry: true`, so a rethrow would re-run the
 * whole handler — re-rotating everything it had already done — for something
 * a retry cannot fix. Failures are logged with counts instead.
 *
 * @param {!Object} deps `{db, logger, bucket}` — `bucket` is injected by
 *   tests and resolved lazily otherwise.
 * @param {string} employeeDocId The users doc id being deactivated.
 * @return {!Promise<{appointments: number, photos: number}>}
 */
async function rotateAssignedImageTokens(deps, employeeDocId) {
  const {db, logger} = deps;
  const result = {appointments: 0, photos: 0};

  let bucket = deps.bucket;
  if (!bucket) {
    try {
      // `resolveBucket` exists so the LAZY branch is reachable from jest.
      // Without it the only branch production ever takes was also the only
      // one no test could enter, which is how the bucket failed to reach
      // [rotatePictures] unnoticed.
      bucket = (deps.resolveBucket || defaultBucket)();
    } catch (err) {
      if (logger) {
        logger.error("imageTokens: no Storage bucket; tokens NOT rotated", {
          employeeDocId,
          error: err && err.message,
        });
      }
      return result;
    }
  }
  // Carries the RESOLVED bucket, which is the whole point: [rotatePictures]
  // reads `deps.bucket`, so passing the caller's `deps` straight through left
  // it `undefined` on the only path production takes — `bridge.js` passes
  // `{db, logger}`, while every test injects a bucket, so the lazy branch was
  // exercised nowhere. Each object rotation then threw into this module's own
  // swallow and the control reported "nothing rotated" while doing nothing.
  const rotateDeps = {...deps, bucket};

  let docs = [];
  try {
    // `endTime` DESC on its OWN `(employeeIds CONTAINS, endTime DESCENDING)`
    // composite, declared in `firestore.indexes.json` — do NOT delete that
    // entry as redundant on the reasoning that Firestore can serve either
    // direction from one index. A missing index fails `FAILED_PRECONDITION`
    // into this module's swallow, i.e. this security control silently stops
    // running, which is exactly why it is declared explicitly.
    //
    // Newest first is what makes the cap defensible: those are the photos a
    // just-departed employee most plausibly still holds a link to.
    //
    // This pass CANNOT see an appointment with no `endTime` — Firestore omits
    // documents missing the ordered field — which is what the backstop below
    // exists for. Don't fold the two into one unordered query: that would
    // trade a known, small hole for an arbitrary `__name__`-ordered slice,
    // losing the newest-first property the cap rests on.
    const snap = await db.collection("appointments")
        .where("employeeIds", "array-contains", employeeDocId)
        .orderBy("endTime", "desc")
        .limit(ROTATE_APPOINTMENT_MAX)
        .get();
    docs = (snap && snap.docs) || [];
    if (docs.length === ROTATE_APPOINTMENT_MAX && logger) {
      logger.warn("imageTokens: appointment cap hit; older photos keep " +
          "their download tokens", {
        employeeDocId,
        cap: ROTATE_APPOINTMENT_MAX,
      });
    }
  } catch (err) {
    if (logger) {
      logger.error("imageTokens: appointment query failed", {
        employeeDocId,
        error: err && err.message,
      });
    }
    return result;
  }

  // BACKSTOP for the docs the ordered pass structurally cannot return: an
  // appointment with no `endTime` is absent from that index, so its photos
  // would keep their permanent tokens forever with nothing logging it. The
  // Dart model never writes such a record, but legacy and console-written
  // docs reach the server (`day_slice_utils.js` carries its own branch for
  // exactly this), and for a security control "rare" is not "absent".
  //
  // Unordered, so it is served by the automatic `employeeIds` array index —
  // no new composite. Filtered to `endTime == null` (both absent and
  // explicitly null) and deduped by doc id, which keeps it scoped to the hole
  // rather than quietly widening the 500-appointment budget.
  try {
    const seen = new Set(docs.map((doc) => doc.id));
    const snap = await db.collection("appointments")
        .where("employeeIds", "array-contains", employeeDocId)
        .limit(ROTATE_APPOINTMENT_MAX)
        .get();
    const scanned = (snap && snap.docs) || [];
    const undated = scanned.filter(
        (doc) => !seen.has(doc.id) && (doc.data() || {}).endTime == null);
    if (scanned.length === ROTATE_APPOINTMENT_MAX && logger) {
      logger.warn("imageTokens: backstop scan cap hit; an undated " +
          "appointment beyond it keeps its download tokens", {
        employeeDocId,
        cap: ROTATE_APPOINTMENT_MAX,
      });
    }
    if (undated.length > 0) {
      if (logger) {
        logger.warn("imageTokens: rotating appointments with no endTime", {
          employeeDocId,
          count: undated.length,
        });
      }
      docs = docs.concat(undated);
    }
  } catch (err) {
    // Best-effort like everything else here: the ordered pass already
    // succeeded, so a failure now must not discard its results.
    if (logger) {
      logger.warn("imageTokens: backstop scan failed", {
        employeeDocId,
        error: err && err.message,
      });
    }
  }

  for (let i = 0; i < docs.length; i += ROTATE_CONCURRENCY) {
    const chunk = docs.slice(i, i + ROTATE_CONCURRENCY);
    await Promise.all(chunk.map(async (doc) => {
      const pictures = (doc.data() || {}).pictures;
      if (!Array.isArray(pictures) || pictures.length === 0) return;
      try {
        const next = await rotatePictures(rotateDeps, pictures);
        if (!next) return;
        // The subcollection copy omits `url` whenever `storagePath` is
        // present, so only the parent array holds a link worth rewriting.
        // A LEGACY subcollection doc that kept its `url` is reached by the
        // rotation itself — its object token is dead either way; the entry
        // is left alone rather than backfilled, which is the same rule the
        // migration follows.
        await doc.ref.update({pictures: next});
        result.appointments += 1;
        result.photos += next.length;
      } catch (err) {
        if (logger) {
          logger.warn("imageTokens: appointment rotation failed", {
            appointmentId: doc.id,
            error: err && err.message,
          });
        }
      }
    }));
  }

  if (result.photos > 0 && logger) {
    logger.info("imageTokens: download tokens rotated", {
      employeeDocId,
      ...result,
    });
  }
  return result;
}

module.exports = {
  ROTATE_APPOINTMENT_MAX,
  storagePathOf,
  downloadUrl,
  rotateObjectToken,
  rotatePictures,
  rotateAssignedImageTokens,
};

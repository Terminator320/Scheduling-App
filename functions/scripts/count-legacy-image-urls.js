#!/usr/bin/env node
// One-off, READ-ONLY: counts `appointments/{id}/images` documents that carry a
// `url` and no `storagePath`.
//
// WHY this exists: such a document holds a `?alt=media&token=…` download link.
// That link is served with NO auth and NO `storage.rules` evaluation, its token
// is stable per object and it never expires — so it is a transferable,
// permanent credential that deactivating the employee does not reach.
// `rotateAssignedImageTokens` used to invalidate exactly these on deactivation;
// it was deleted at the photo-subcollection CONTRACT step (deployed
// 2026-08-22), so there is no revocation path left. This count is the open
// question that decides what to do about that, and it is S1 in
// `docs/audits/CODEBASE_AUDIT.md`.
//
// What the answer means:
//   ZERO — the deletion premise holds. Drop `url` from the `images` rules
//     allowlist and delete `AppointmentImageLoader`'s url fallback, which makes
//     "there is no such link left to invalidate" true rather than merely
//     hoped-for.
//   ANY  — those bytes need re-homing to a real `storagePath` (then strip the
//     url), or a rotation scoped to just these objects has to come back.
//
// WHY IT SCANS INSTEAD OF QUERYING: `images.url` is index-EXEMPT in
// `firestore.indexes.json` ("indexes": []), so `where("url", ...)` fails
// outright. The filter therefore runs in memory over a `__name__`-paged
// collection-group read. Do not "optimize" this into a where clause without
// first removing that exemption.
//
// Usage:
//   For prod:
//     export GOOGLE_APPLICATION_CREDENTIALS=/path/to/prod-service-account.json
//     node functions/scripts/count-legacy-image-urls.js
//
//   For the local emulator:
//     export FIRESTORE_EMULATOR_HOST=localhost:8080
//     export GCLOUD_PROJECT=schedulingapp-88727
//     node functions/scripts/count-legacy-image-urls.js
//
//   --verbose  also lists the appointment id of every affected photo.

"use strict";

const {initializeApp, applicationDefault} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");
const {assertKnownFlags: rejectUnknownFlags} = require("./_flags");
const {printTargetBanner} = require("./_project");

const EXACT_FLAGS = ["--verbose"];

/**
 * Rejects any argument this script does not recognize. The rule itself lives
 * in the shared `_flags.js` — this wrapper only supplies the flag list.
 * @param {!Array<string>} argv Arguments after the node + script paths.
 */
function assertKnownFlags(argv) {
  rejectUnknownFlags(argv, {exact: EXACT_FLAGS});
}

// Read-only, so this is purely a round-trip dial rather than a write bound.
const PAGE_SIZE = 500;

/**
 * Whether one image document is a legacy permanent link.
 *
 * Mirrors `imageDoc` in `backfill-appointment-images.js`, which writes `url`
 * ONLY when `storagePath` is empty — the two conditions are checked separately
 * anyway, so a document written by some other path is still classified right.
 * @param {!Object} data The image document body.
 * @return {boolean} True when it carries a url and no storagePath.
 */
function isLegacyUrlOnly(data) {
  const storagePath = String((data && data.storagePath) || "").trim();
  const url = String((data && data.url) || "").trim();
  return storagePath === "" && url !== "";
}

/**
 * Counts the legacy documents across every appointment.
 * @param {!Object} db The Firestore handle.
 * @param {boolean} verbose Whether to list each affected appointment id.
 * @return {!Promise<{scanned: number, legacy: number, orphans: number}>} The
 *   tally. `orphans` are documents with NEITHER a storagePath nor a url —
 *   they can never be rendered and the clear script refuses them, so they are
 *   worth surfacing here rather than leaving for that run to discover.
 */
async function countLegacyUrls(db, verbose) {
  let scanned = 0;
  let legacy = 0;
  let orphans = 0;
  let cursor = null;

  for (;;) {
    let query = db.collectionGroup("images")
        .orderBy("__name__")
        .limit(PAGE_SIZE);
    if (cursor) query = query.startAfter(cursor);

    const snap = await query.get();
    if (snap.empty) break;

    for (const doc of snap.docs) {
      scanned += 1;
      const data = doc.data() || {};
      const storagePath = String(data.storagePath || "").trim();
      const url = String(data.url || "").trim();

      if (isLegacyUrlOnly(data)) {
        legacy += 1;
        // `doc.ref.parent.parent` is the appointment; the id is what an
        // operator needs to act on one of these.
        const appointmentId =
          doc.ref.parent.parent ? doc.ref.parent.parent.id : "(unknown)";
        if (verbose) {
          console.log(`  legacy url: appointments/${appointmentId}/` +
            `images/${doc.id}`);
        }
      } else if (storagePath === "" && url === "") {
        orphans += 1;
        const appointmentId =
          doc.ref.parent.parent ? doc.ref.parent.parent.id : "(unknown)";
        console.log(`  NO IDENTITY (neither storagePath nor url): ` +
          `appointments/${appointmentId}/images/${doc.id}`);
      }
    }

    cursor = snap.docs[snap.docs.length - 1];
    if (snap.size < PAGE_SIZE) break;
  }

  return {scanned, legacy, orphans};
}

/**
 * Entry point.
 * @return {!Promise<void>} Resolves when the count has been printed.
 */
async function main() {
  assertKnownFlags(process.argv.slice(2));
  const verbose = process.argv.includes("--verbose");

  const app = initializeApp({credential: applicationDefault()});
  // Read-only: the banner still prints, because knowing which project a count
  // describes is the whole point of reporting a number to act on.
  printTargetBanner(app, {dryRun: false});

  const db = getFirestore();
  const {scanned, legacy, orphans} = await countLegacyUrls(db, verbose);

  console.log(`\nscanned ${scanned} image documents`);
  console.log(`legacy url-only (url set, no storagePath): ${legacy}`);
  if (orphans > 0) {
    console.log(`no identity at all (neither field): ${orphans}`);
  }

  if (legacy === 0) {
    console.log(
        "\nZERO — no permanent rules-free links remain. S1's fix is now " +
        "safe: drop `url` from the images rules allowlist and delete the " +
        "loader's url fallback.");
  } else {
    console.log(
        `\n${legacy} permanent rules-free link(s) remain, with NO revocation ` +
        "path since rotateAssignedImageTokens was deleted. Re-home those " +
        "bytes to a storagePath and strip the url, or restore a rotation " +
        "scoped to just these objects. Re-run with --verbose to list them.");
  }
}

main().then(() => process.exit(0)).catch((err) => {
  console.error(err);
  process.exit(1);
});

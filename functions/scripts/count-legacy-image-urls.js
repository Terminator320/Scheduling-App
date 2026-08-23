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
// ANSWERED 2026-08-22 for the SUBCOLLECTION: 14 documents scanned, ZERO
// carrying a url with no storagePath, so the field was retired (rules
// allowlist, loader fallback, store write) without stranding any bytes.
//
// That is NOT the same as "no rules-free link remains", and the two were
// conflated once. A pre-CONTRACT upload wrote a url alongside the
// storagePath into the parent `pictures[]` array, and those arrays are still
// there until `clear-appointment-picture-arrays.js` runs (step 4 of the
// runbook in docs/DEPLOYMENT.md) - each entry a permanent link readable off
// the appointment document by any assigned employee. `countArrayUrls` counts
// exactly those, so the script now answers BOTH questions and the second one
// is the security claim.
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
      // Both branches below name the document, so `doc.ref.parent.parent` —
      // the appointment, which is what an operator needs to act on one of
      // these — is resolved once for the pair.
      const appointmentId =
        doc.ref.parent.parent ? doc.ref.parent.parent.id : "(unknown)";
      const path = `appointments/${appointmentId}/images/${doc.id}`;

      // The two halves of ONE classification of a document with no
      // storagePath, spelled side by side so neither can drift from the
      // other: a url makes it a legacy permanent link, no url makes it
      // unrenderable, and the clear script refuses an appointment on the
      // second.
      if (storagePath !== "") continue;
      if (url !== "") {
        legacy += 1;
        if (verbose) console.log(`  legacy url: ${path}`);
      } else {
        orphans += 1;
        console.log(`  NO IDENTITY (neither storagePath nor url): ${path}`);
      }
    }

    cursor = snap.docs[snap.docs.length - 1];
    if (snap.size < PAGE_SIZE) break;
  }

  return {scanned, legacy, orphans};
}

/**
 * Counts the `url` strings still sitting in parent `pictures[]` arrays.
 *
 * The subcollection scan above CANNOT see these, and they are the larger set:
 * a pre-CONTRACT upload wrote BOTH `storagePath` and a `getDownloadURL()`
 * link into every array entry, so an entry is typically not url-ONLY but
 * still carries a permanent, rules-free, transferable link - readable off the
 * appointment document by any assigned employee, and unrevocable since
 * `rotateAssignedImageTokens` was deleted. Nothing writes these any more;
 * `clear-appointment-picture-arrays.js` is what removes them, and until that
 * has run "no rules-free link remains" is a statement about the
 * SUBCOLLECTION only.
 * @param {!Object} db The Firestore handle.
 * @param {boolean} verbose Whether to list each affected appointment id.
 * @return {!Promise<{appointments: number, withArray: number, urls: number}>}
 *   The tally.
 */
async function countArrayUrls(db, verbose) {
  let appointments = 0;
  let withArray = 0;
  let urls = 0;
  let cursor = null;

  for (;;) {
    let query = db.collection("appointments")
        .orderBy("__name__")
        .limit(PAGE_SIZE);
    if (cursor) query = query.startAfter(cursor);

    const snap = await query.get();
    if (snap.empty) break;

    for (const doc of snap.docs) {
      appointments += 1;
      const data = doc.data() || {};
      const pictures = Array.isArray(data.pictures) ? data.pictures : [];
      if (pictures.length === 0) continue;
      withArray += 1;

      const carried = pictures.filter(
          (p) => String((p && p.url) || "").trim() !== "").length;
      urls += carried;
      if (carried > 0 && verbose) {
        console.log(`  ${carried} array url(s): appointments/${doc.id}`);
      }
    }

    cursor = snap.docs[snap.docs.length - 1];
    if (snap.size < PAGE_SIZE) break;
  }

  return {appointments, withArray, urls};
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
  const array = await countArrayUrls(db, verbose);

  console.log(`\nscanned ${scanned} image documents`);
  console.log(`legacy url-only (url set, no storagePath): ${legacy}`);
  if (orphans > 0) {
    console.log(`no identity at all (neither field): ${orphans}`);
  }
  console.log(
      `\nscanned ${array.appointments} appointments; ` +
      `${array.withArray} still carry a pictures[] array, ` +
      `holding ${array.urls} url(s)`);

  if (legacy === 0) {
    console.log(
        "\nZERO url-only image documents: dropping `url` from the images " +
        "rules allowlist strands no bytes, which is what S1 asked.");
  } else {
    console.log(
        `\n${legacy} url-only image document(s) remain: those bytes have NO ` +
        "other handle, so re-home them to a storagePath before the field " +
        "goes. Re-run with --verbose to list them.");
  }

  // Deliberately a SECOND sentence. The two counts answer different questions
  // and only the pair supports the security claim: the first says whether
  // dropping the field loses any bytes, this one says whether a permanent
  // rules-free link is still readable ANYWHERE.
  if (array.urls === 0) {
    console.log(
        "ZERO array urls: no permanent rules-free link remains in the " +
        "database at all.");
  } else {
    console.log(
        `${array.urls} permanent rules-free link(s) STILL READABLE off the ` +
        "appointment documents, with no revocation path since " +
        "rotateAssignedImageTokens was deleted. Until " +
        "clear-appointment-picture-arrays.js has run, any claim that none " +
        "remains is about the SUBCOLLECTION only.");
  }
}

main().then(() => process.exit(0)).catch((err) => {
  console.error(err);
  process.exit(1);
});

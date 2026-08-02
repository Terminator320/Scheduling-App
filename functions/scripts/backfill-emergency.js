#!/usr/bin/env node
// One-off: moves emergencyContact / emergencyPhone off each `users` doc into
// its `private/emergency` subcollection, then deletes them from the parent.
//
// WHY this exists: Firestore rules are document-level, and the /users read rule
// deliberately lets every active employee read every active peer (the crew
// pickers, names and colours depend on it). While those two fields sit on the
// parent doc they are broadcast to every employee's device — and they name a
// THIRD PARTY who is not an app user and never consented. The app stopped
// writing them there, and `updateEmployee` scrubs them on every save, but that
// scrub only fires for people an admin happens to re-save. This closes the gap
// for everyone else.
//
// Idempotent: a doc with neither field is skipped, and the subcollection write
// is a merge that never overwrites a non-empty value already stored there.
//
// Usage:
//   For prod:
//     $env:GOOGLE_APPLICATION_CREDENTIALS = "C:\path\to\prod-service-account.json"
//     node functions/scripts/backfill-emergency.js
//
//   For the local emulator:
//     $env:FIRESTORE_EMULATOR_HOST = "localhost:8080"
//     $env:GCLOUD_PROJECT = "schedulingapp-88727"
//     node functions/scripts/backfill-emergency.js
//
// Pass --dry-run to report what it would do without writing.
//
// AFTER this has run against prod, tighten firestore.rules: add
// 'emergencyContact' and 'emergencyPhone' to the /users update denylist beside
// `uid`. Doing that BEFORE the backfill would break deactivateEmployee — a
// partial update still presents the untouched fields in request.resource.data,
// so any doc still carrying them would fail permission-denied.

const { initializeApp, applicationDefault } = require("firebase-admin/app");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");

const DRY_RUN = process.argv.includes("--dry-run");

/**
 * Reads a field as a trimmed string, or "".
 * @param {*} value
 * @return {string}
 */
function str(value) {
  return typeof value === "string" ? value.trim() : "";
}

async function main() {
  // When pointed at the emulator, applicationDefault() is unused. The SDK
  // picks up FIRESTORE_EMULATOR_HOST automatically and ignores creds.
  if (process.env.FIRESTORE_EMULATOR_HOST) {
    initializeApp({
      projectId: process.env.GCLOUD_PROJECT || "schedulingapp-88727",
    });
  } else {
    initializeApp({ credential: applicationDefault() });
  }

  const db = getFirestore();
  const snap = await db.collection("users").get();

  let moved = 0;
  let skipped = 0;

  for (const doc of snap.docs) {
    const data = doc.data() || {};
    const hasKeys =
      "emergencyContact" in data || "emergencyPhone" in data;
    if (!hasKeys) {
      skipped += 1;
      continue;
    }

    const contact = str(data.emergencyContact);
    const phone = str(data.emergencyPhone);

    if (DRY_RUN) {
      console.log(
        `[dry-run] ${doc.id}: would move ` +
          `${contact ? "contact" : "-"}/${phone ? "phone" : "-"} ` +
          "and delete both parent keys"
      );
      moved += 1;
      continue;
    }

    const privateRef = doc.ref.collection("private").doc("emergency");

    // Only write the subcollection when there is something to carry. A doc
    // holding two empty strings just needs the parent keys removed.
    if (contact || phone) {
      const existing = await privateRef.get();
      const current = existing.exists ? existing.data() || {} : {};
      // Never clobber a value the person already saved through My details.
      const merged = {
        contact: str(current.contact) || contact,
        phone: str(current.phone) || phone,
        updatedAt: FieldValue.serverTimestamp(),
      };
      await privateRef.set(merged, { merge: true });
    }

    await doc.ref.update({
      emergencyContact: FieldValue.delete(),
      emergencyPhone: FieldValue.delete(),
    });
    moved += 1;
    console.log(`moved ${doc.id}`);
  }

  console.log(
    `\nDone. ${moved} moved, ${skipped} had nothing to move ` +
      `(${snap.size} users scanned).`
  );
  if (moved > 0 && !DRY_RUN) {
    console.log(
      "Next: add emergencyContact/emergencyPhone to the /users update " +
        "denylist in firestore.rules and deploy firestore:rules."
    );
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});

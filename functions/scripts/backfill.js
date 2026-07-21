#!/usr/bin/env node
// Backfills the usersByUid bridge collection from existing `users` docs.
// Run once after deploying the syncUsersByUid trigger and before deploying
// the stub-free rules. Idempotent and safe to re-run.
//
// Usage:
//   For prod:
//     $env:GOOGLE_APPLICATION_CREDENTIALS = "C:\path\to\prod-service-account.json"
//     node functions/scripts/backfill.js
//
//   For the local emulator:
//     $env:FIRESTORE_EMULATOR_HOST = "localhost:8080"
//     $env:GCLOUD_PROJECT = "schedulingapp-88727"
//     node functions/scripts/backfill.js
//
// The script never writes to `users` — it only reads from it and writes
// to `usersByUid`.

const { initializeApp, applicationDefault } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");

const VALID_ROLES = new Set(["admin", "employee"]);
const VALID_BRIDGE_STATUS = new Set(["active", "disabled"]);

// NOTE: this is a deliberate standalone copy, NOT the shared helper. The
// authoritative runtime version is `shouldHaveBridge` in ../bridge.js, which
// gates on uid + status only and validates `role` later, inside `bridgeBody`.
// This one folds the role check in up front so a one-off backfill skips
// malformed docs outright instead of writing a bridge entry with a bogus role.
// The two are intentionally not shared: re-pointing this at the export would
// change what this script backfills. Keep bridge.js authoritative for runtime
// behavior — if its gating changes, re-read this before running the script
// again.
function shouldHaveBridge(data) {
  if (!data) return false;
  if (typeof data.uid !== "string" || data.uid === "") return false;
  if (!VALID_BRIDGE_STATUS.has(data.status)) return false;
  if (!VALID_ROLES.has(data.role)) return false;
  return true;
}

async function main() {
  // When pointed at the emulator, applicationDefault() is unused; the SDK
  // picks up FIRESTORE_EMULATOR_HOST automatically and ignores creds.
  if (process.env.FIRESTORE_EMULATOR_HOST) {
    initializeApp({ projectId: process.env.GCLOUD_PROJECT || "schedulingapp-88727" });
    console.log(
      `Running against emulator at ${process.env.FIRESTORE_EMULATOR_HOST}`,
    );
  } else {
    if (!process.env.GOOGLE_APPLICATION_CREDENTIALS) {
      console.error(
        "ERROR: set GOOGLE_APPLICATION_CREDENTIALS to a service-account JSON path " +
          "(or FIRESTORE_EMULATOR_HOST for the emulator).",
      );
      process.exit(1);
    }
    initializeApp({ credential: applicationDefault() });
    console.log("Running against PROD project from service account creds");
  }

  const db = getFirestore();
  const usersSnap = await db.collection("users").get();

  const stats = {
    scanned: 0,
    written: 0,
    skippedInvited: 0,
    skippedNoUid: 0,
    skippedInvalid: 0,
    orphansDeleted: 0,
  };

  // Track which uids should have a bridge so we can clean up orphans afterwards.
  const expectedUids = new Set();

  for (const doc of usersSnap.docs) {
    stats.scanned += 1;
    const data = doc.data();

    if (data.status === "invited") {
      stats.skippedInvited += 1;
      continue;
    }
    if (typeof data.uid !== "string" || data.uid === "") {
      stats.skippedNoUid += 1;
      continue;
    }
    if (!shouldHaveBridge(data)) {
      stats.skippedInvalid += 1;
      console.warn(
        `  skipping invalid user doc ${doc.id} (role=${data.role}, status=${data.status})`,
      );
      continue;
    }

    expectedUids.add(data.uid);
    await db.collection("usersByUid").doc(data.uid).set({
      role: data.role,
      docId: doc.id,
      status: data.status,
    });
    stats.written += 1;
  }

  // Orphan cleanup: any usersByUid doc whose uid doesn't appear above is stale.
  const bridgeSnap = await db.collection("usersByUid").get();
  for (const doc of bridgeSnap.docs) {
    if (!expectedUids.has(doc.id)) {
      await doc.ref.delete();
      stats.orphansDeleted += 1;
      console.warn(`  orphan bridge removed: usersByUid/${doc.id}`);
    }
  }

  console.log("\nBackfill complete:");
  console.log(JSON.stringify(stats, null, 2));
}

main().catch((err) => {
  console.error("Backfill failed:", err);
  process.exit(1);
});

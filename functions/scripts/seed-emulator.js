#!/usr/bin/env node
// This is an emulator-only seed script — it creates Firebase Auth accounts
// and matching Firestore `users` docs, which the syncUsersByUid trigger then
// fans into `usersByUid`.
//
// Usage (PowerShell):
//   $env:FIRESTORE_EMULATOR_HOST = "127.0.0.1:8080"
//   $env:FIREBASE_AUTH_EMULATOR_HOST = "127.0.0.1:9099"
//   $env:GCLOUD_PROJECT = "schedulingapp-88727"
//   node functions/scripts/seed-emulator.js
//
// Re-running this script is safe: it clears all auth users and users docs
// first, then re-seeds them.

const { initializeApp } = require("firebase-admin/app");
const { getAuth } = require("firebase-admin/auth");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");

if (!process.env.FIRESTORE_EMULATOR_HOST || !process.env.FIREBASE_AUTH_EMULATOR_HOST) {
  console.error(
    "ERROR: set FIRESTORE_EMULATOR_HOST and FIREBASE_AUTH_EMULATOR_HOST before running.",
  );
  process.exit(1);
}

initializeApp({ projectId: process.env.GCLOUD_PROJECT || "schedulingapp-88727" });

const auth = getAuth();
const db = getFirestore();

const SEEDS = [
  {
    label: "alice (admin/active)",
    email: "alice@example.com",
    password: "password123",
    role: "admin",
    status: "active",
    name: "Alice Admin",
  },
  {
    label: "bob (employee/active)",
    email: "bob@example.com",
    password: "password123",
    role: "employee",
    status: "active",
    name: "Bob Employee",
  },
  {
    label: "carol (employee/invited — no auth account)",
    email: "carol@example.com",
    password: null,
    role: "employee",
    status: "invited",
    name: "Carol Invited",
  },
  {
    label: "dave (employee/disabled)",
    email: "dave@example.com",
    password: "password123",
    role: "employee",
    status: "disabled",
    name: "Dave Disabled",
  },
];

async function wipe() {
  const list = await auth.listUsers(1000);
  if (list.users.length > 0) {
    await auth.deleteUsers(list.users.map((u) => u.uid));
    console.log(`  wiped ${list.users.length} auth user(s)`);
  }
  const users = await db.collection("users").get();
  const bridges = await db.collection("usersByUid").get();
  const batch = db.batch();
  users.docs.forEach((d) => batch.delete(d.ref));
  bridges.docs.forEach((d) => batch.delete(d.ref));
  if (users.size + bridges.size > 0) {
    await batch.commit();
    console.log(`  wiped ${users.size} user doc(s), ${bridges.size} bridge doc(s)`);
  }
}

async function main() {
  console.log("Wiping existing seed data…");
  await wipe();

  console.log("\nSeeding…");
  for (const s of SEEDS) {
    let uid = "";
    if (s.password) {
      const u = await auth.createUser({
        email: s.email,
        password: s.password,
        emailVerified: false,
      });
      uid = u.uid;
    }
    await db.collection("users").add({
      name: s.name,
      email: s.email,
      phone: "+1-514-555-0100",
      role: s.role,
      status: s.status,
      uid,
      colorValue: "4280391411",
      createdAt: FieldValue.serverTimestamp(),
    });
    console.log(`  ${s.label} → uid='${uid || "(none)"}'`);
  }

  console.log("\nWaiting 3s for syncUsersByUid trigger to settle…");
  await new Promise((r) => setTimeout(r, 3000));

  const bridges = await db.collection("usersByUid").get();
  console.log(`\nusersByUid (count=${bridges.size}):`);
  for (const d of bridges.docs) {
    console.log("  " + d.id + " => " + JSON.stringify(d.data()));
  }

  console.log("\nReady. Sign-in credentials for the app:");
  for (const s of SEEDS) {
    if (s.password) {
      console.log(`  ${s.label}: email=${s.email}  password=${s.password}`);
    }
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});

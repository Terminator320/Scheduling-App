"use strict";

// Shared "which project is this about to write to?" banner for the one-off
// scripts in this directory.
//
// Every script here calls `initializeApp({credential: applicationDefault()})`,
// which resolves whatever credentials happen to be in the ambient environment.
// That is convenient and it is also how a bulk rewrite lands on the wrong
// project: nothing in the command line says which one, so the only defence is
// the operator reading a line that does. It is printed BEFORE the first read,
// because after the first write there is nothing to decide.
//
// This module owns the banner AND the resolution, because the resolution is
// the part that was quietly wrong. Three scripts hand-rolled a weaker copy
// that stops at the two env vars, and in the credential setup the runbooks
// actually recommend — `GOOGLE_APPLICATION_CREDENTIALS` pointing at a
// service-account JSON — those print "(unknown)". The banner goes blank
// exactly when credentials were supplied properly, which is the worst possible
// time for it to say nothing.
//
// It also owns `bootstrapScript`, the whole preamble those scripts share --
// flags, dryRun, app, db, banner -- because the WIRING between `_flags.js`
// and this banner is the part that had no owner and drifted.
//
// Companion to `_flags.js` (reject unknown arguments) and `_batch.js` (commit
// in batches): same directory, same purpose, three parts of "a bulk script
// should be hard to point at the wrong thing".

const {readFileSync} = require("fs");
const {initializeApp, applicationDefault} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");

/**
 * The project this run will write to.
 *
 * THE SERVICE-ACCOUNT FILE IS THE CASE THAT MATTERS. `applicationDefault()`
 * reads the project out of that JSON internally and never puts it on
 * `app.options`, so a run authenticated the recommended way resolves through
 * neither of the first two sources — parsing the key file is what makes the
 * banner say something in the setup an operator is most likely to be using.
 *
 * @param {!Object} app The initialized admin app.
 * @return {string} A project id, or a marker saying it could not be resolved.
 */
function resolveProjectId(app) {
  const fromApp = app.options && app.options.projectId;
  if (fromApp) return fromApp;

  const fromEnv =
    process.env.GOOGLE_CLOUD_PROJECT || process.env.GCLOUD_PROJECT;
  if (fromEnv) return fromEnv;

  const keyFile = process.env.GOOGLE_APPLICATION_CREDENTIALS;
  if (keyFile) {
    try {
      const parsed = JSON.parse(readFileSync(keyFile, "utf8"));
      if (parsed && parsed.project_id) return parsed.project_id;
    } catch (err) {
      // Reported, not swallowed: an unreadable key file is worth seeing before
      // the run rather than inferring from a blank banner.
      console.error(
          `could not read the project id out of ${keyFile}: ${err.message}`);
    }
  }
  return "(unknown — check your credentials)";
}

/**
 * Prints the target-project banner. Call it immediately after `initializeApp`
 * and before the first read.
 *
 * `(LIVE)` versus the emulator host is the other half of the question the
 * operator is really asking, so the two are one line rather than two.
 *
 * @param {!Object} app The initialized admin app.
 * @param {{dryRun: boolean}} options Whether this run will actually write.
 * @return {string} The resolved project id, for a caller that wants to log or
 *   assert on it.
 */
function printTargetBanner(app, {dryRun}) {
  const target = resolveProjectId(app);
  const emulator = process.env.FIRESTORE_EMULATOR_HOST;
  console.log(
      `${dryRun ? "[dry-run] " : ""}target: ${target}` +
      `${emulator ? ` via emulator ${emulator}` : " (LIVE)"}\n`);
  return target;
}


/**
 * The whole "point this script at a project" preamble, in one place.
 *
 * `_flags.js` owns rejecting an unknown argument and this module owns the
 * banner, but until now NOTHING owned the six lines that wire them together —
 * resolve `dryRun` once and hand the same value to both. Thirteen scripts
 * spelled that sequence out by hand, which is thirteen chances to print a
 * banner that disagrees with the run: commit `3059ac0a` ("pass the required
 * dryRun flag to the audit's target banner") is exactly that drift, and repo
 * history has a backfill whose `--dry-run` wrote everything anyway. These
 * scripts touch prod, so the wiring is worth an owner.
 *
 * `assertFlags` is the SCRIPT'S OWN wrapper, passed in rather than a
 * `{exact, prefixes}` pair, and that is deliberate: the flag lists legitimately
 * differ per script and each wrapper is separately pinned by jest. Handing over
 * the function keeps one spelling of a script's flag policy — passing the lists
 * again here would create a second one, free to drift from the wrapper the
 * tests actually check, which is the very failure this helper exists to remove.
 *
 * Note what the flag rejection buys the read-only scripts for free: a script
 * whose allowlist has no `--dry-run` (the `audit-*`/`count-*` trio) can never
 * see one in `argv`, so `dryRun` is structurally false for them and they need
 * no special case here.
 *
 * `backfill.js` deliberately does NOT use this: it branches on
 * `FIRESTORE_EMULATOR_HOST` and hard-fails on missing credentials, which is a
 * different preamble rather than this one with a flag.
 *
 * @param {!Array<string>} argv Arguments after the node + script paths.
 * @param {{assertFlags: function(!Array<string>)}} options The script's own
 *   flag-rejection wrapper, called BEFORE any credential is resolved.
 * @return {{app: !Object, db: !Object, dryRun: boolean}} The initialized app,
 *   its Firestore handle, and the one resolved `dryRun` every caller shares.
 */
function bootstrapScript(argv, {assertFlags}) {
  assertFlags(argv);
  const dryRun = argv.includes("--dry-run");

  const app = initializeApp({credential: applicationDefault()});
  const db = getFirestore();

  // Printed BEFORE the first read — `applicationDefault()` resolves whatever
  // credentials are in the environment, and nothing on the command line says
  // which project that is. After the first write there is nothing to decide.
  printTargetBanner(app, {dryRun});

  return {app, db, dryRun};
}

module.exports = {
  resolveProjectId,
  printTargetBanner,
  bootstrapScript,
};

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
// Companion to `_flags.js` (reject unknown arguments) and `_batch.js` (commit
// in batches): same directory, same purpose, three parts of "a bulk script
// should be hard to point at the wrong thing".

const {readFileSync} = require("fs");

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

module.exports = {
  resolveProjectId,
  printTargetBanner,
};

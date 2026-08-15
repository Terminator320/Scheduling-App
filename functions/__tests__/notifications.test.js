"use strict";

/**
 * Wiring tests for the notification trigger module.
 *
 * The orchestration logic itself lives in notification_utils.js and
 * travel_utils.js and is covered there. What this file pins is the one thing
 * that can only go wrong at the wiring layer: the secret-binding split.
 *
 * Only the two functions that BIND `APNS_SECRETS` may build their deps with
 * `liveActivityDeps()` (which reads them). Reading a secret param a function
 * didn't bind logs a "No value found for secret parameter" warning on EVERY
 * invocation — and the digest and overdue sweeps run on a schedule, so that
 * would be continuous log noise. This is stated as an invariant in
 * functions/CLAUDE.md; nothing enforced it.
 *
 * (maintenance.js still has no sibling test: it resolves a Storage bucket at
 * load, so `require()` throws "Missing bucket name" outside the emulator.
 * Its logic lives in image_magic.js and maintenance_policy.js — the purge
 * orchestration moved to the latter precisely so it could be tested.)
 */

const fs = require("fs");
const path = require("path");

const SOURCE = fs.readFileSync(
    path.join(__dirname, "..", "notifications.js"),
    "utf8",
);

/**
 * The body of one `onSchedule`/`onDocumentWritten` registration, sliced from
 * the source between its exported const and the next top-level const.
 * @param {string} name Exported function name.
 * @return {string}
 */
function registrationBody(name) {
  const start = SOURCE.indexOf(`const ${name} = `);
  expect(start).toBeGreaterThan(-1);
  const rest = SOURCE.slice(start + 1);
  const end = rest.indexOf("\nconst ");
  return end === -1 ? rest : rest.slice(0, end);
}

describe("notifications.js module surface", () => {
  test("exports exactly the three triggers index.js re-exports", () => {
    // Three, not four: `sendOverdueJobPrompts` was folded into
    // `sendUpcomingJobReminders` on 2026-08-13 to get the project's timer
    // count inside Cloud Scheduler's 3-free allowance.
    const mod = require("../notifications");
    expect(Object.keys(mod).sort()).toEqual([
      "notifyAppointmentChanges",
      "sendDailyJobDigest",
      "sendUpcomingJobReminders",
    ]);
  });

  test("only THREE scheduled jobs exist across the whole project", () => {
    // The cost invariant. Cloud Scheduler bills per job past the first three,
    // so a fourth timer anywhere in functions/ starts a recurring charge.
    // Prefer riding an existing schedule (see sendDailyJobDigest's riders)
    // over adding one.
    const fs = require("fs");
    const path = require("path");
    const root = path.join(__dirname, "..");
    const files = [];
    (function walk(dir) {
      for (const entry of fs.readdirSync(dir, {withFileTypes: true})) {
        if (entry.name === "node_modules" || entry.name === "__tests__") {
          continue;
        }
        const full = path.join(dir, entry.name);
        if (entry.isDirectory()) walk(full);
        else if (entry.name.endsWith(".js")) files.push(full);
      }
    })(root);

    const scheduled = [];
    for (const file of files) {
      const src = fs.readFileSync(file, "utf8");
      for (const m of src.matchAll(/onSchedule\(/g)) {
        scheduled.push(`${path.relative(root, file)}@${m.index}`);
      }
    }
    expect(scheduled).toHaveLength(3);
  });
});

describe("every scheduler reads the ONE business time zone", () => {
  // functions/CLAUDE.md: "Never re-inline a local `toMillis` or a bare
  // `timeZone: \"America/Toronto\"`." These are the only three Cloud Scheduler
  // jobs in the project, so a hand-written literal here is what would silently
  // split every scheduled run from every time the app renders if the business
  // ever moved. The values are identical today — this is drift prevention.
  const MAINTENANCE = fs.readFileSync(
      path.join(__dirname, "..", "maintenance.js"),
      "utf8",
  );

  test.each([
    ["notifications.js", SOURCE],
    // Read as TEXT rather than required: maintenance.js resolves a Storage
    // bucket at load and throws outside the emulator.
    ["maintenance.js", MAINTENANCE],
  ])("%s inlines no bare timeZone literal", (_name, src) => {
    // Matches the literal as a `timeZone:` VALUE only — the zone name is still
    // legitimate prose in a comment describing when a job runs.
    expect(src).not.toMatch(/timeZone:\s*["']/);
    expect(src).toContain("BUSINESS_TIME_ZONE");
  });

  test("every onSchedule registration names BUSINESS_TIME_ZONE", () => {
    const zones = [...SOURCE.matchAll(/timeZone: (\w+)/g)].map((m) => m[1]);
    const maintenanceZones =
      [...MAINTENANCE.matchAll(/timeZone: (\w+)/g)].map((m) => m[1]);
    expect([...zones, ...maintenanceZones])
        .toEqual(["BUSINESS_TIME_ZONE", "BUSINESS_TIME_ZONE",
          "BUSINESS_TIME_ZONE"]);
  });
});

describe("APNs secret binding matches deps construction", () => {
  // These two push Live Activity cards, so they bind the secrets AND read them.
  test.each([
    "notifyAppointmentChanges",
    "sendUpcomingJobReminders",
  ])("%s binds APNS_SECRETS and uses liveActivityDeps", (name) => {
    const body = registrationBody(name);
    expect(body).toContain("APNS_SECRETS");
    expect(body).toContain("liveActivityDeps()");
  });

  // The digest is Firestore-only (plus the Wave rider, which binds its own
  // secret). Binding or reading the APNs secrets here would log a warning on
  // every scheduled run.
  test("sendDailyJobDigest neither binds APNS_SECRETS nor reads them", () => {
    const body = registrationBody("sendDailyJobDigest");
    expect(body).not.toContain("APNS_SECRETS");
    expect(body).not.toContain("liveActivityDeps()");
    expect(body).toContain("liveDeps()");
  });

  test("the overdue sweep rides the reminder timer on liveDeps, not " +
      "liveActivityDeps", () => {
    // It moved into a function that DOES bind APNS_SECRETS, so the guard that
    // used to be "does not bind" is now "does not read": the overdue half is
    // Firestore-only and must keep taking liveDeps().
    const body = registrationBody("sendUpcomingJobReminders");
    expect(body).toContain("runOverduePromptSweep(liveDeps())");
  });
});

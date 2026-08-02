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
 * (maintenance.js deliberately has no sibling test: it eagerly resolves a
 * Storage bucket at load, so `require()` throws "Missing bucket name" outside
 * the emulator. Its pure logic lives in image_magic.js and is tested there.)
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
  test("exports exactly the four triggers index.js re-exports", () => {
    const mod = require("../notifications");
    expect(Object.keys(mod).sort()).toEqual([
      "notifyAppointmentChanges",
      "sendDailyJobDigest",
      "sendOverdueJobPrompts",
      "sendUpcomingJobReminders",
    ]);
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

  // These two are Firestore-only. Binding or reading the APNs secrets here
  // would log a warning on every scheduled run.
  test.each([
    "sendDailyJobDigest",
    "sendOverdueJobPrompts",
  ])("%s neither binds APNS_SECRETS nor reads them", (name) => {
    const body = registrationBody(name);
    expect(body).not.toContain("APNS_SECRETS");
    expect(body).not.toContain("liveActivityDeps()");
    expect(body).toContain("liveDeps()");
  });
});

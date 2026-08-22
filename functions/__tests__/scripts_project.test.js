"use strict";

const path = require("path");

const {
  resolveProjectId,
  printTargetBanner,
} = require("../scripts/_project");

// The banner is the only thing standing between a bulk write and the wrong
// project — every script here runs under `applicationDefault()`, so nothing on
// the command line names the target. These tests were moved out of
// `backfill_client_phone_formatting.test.js` when the resolver stopped living
// inside that one-off backfill.
describe("resolveProjectId", () => {
  const env = {...process.env};
  afterEach(() => {
    process.env = {...env};
  });

  test("prefers the id already on the app", () => {
    expect(resolveProjectId({options: {projectId: "from-app"}}))
        .toBe("from-app");
  });

  test("falls back to the environment", () => {
    process.env.GOOGLE_CLOUD_PROJECT = "from-env";
    expect(resolveProjectId({options: {}})).toBe("from-env");
  });

  test("reads it out of the service-account key file", () => {
    // The case that printed "(unknown)" on a real run: applicationDefault()
    // resolves the project from this file and never exposes it on the app.
    delete process.env.GOOGLE_CLOUD_PROJECT;
    delete process.env.GCLOUD_PROJECT;
    process.env.GOOGLE_APPLICATION_CREDENTIALS =
      path.join(__dirname, "fixtures", "fake-service-account.json");
    expect(resolveProjectId({options: {}})).toBe("schedulingapp-88727");
  });

  test("reports an unreadable key file instead of going quiet", () => {
    delete process.env.GOOGLE_CLOUD_PROJECT;
    delete process.env.GCLOUD_PROJECT;
    process.env.GOOGLE_APPLICATION_CREDENTIALS =
      path.join(__dirname, "fixtures", "no-such-service-account.json");
    const errors = [];
    const spy = jest.spyOn(console, "error")
        .mockImplementation((msg) => errors.push(msg));
    try {
      expect(resolveProjectId({options: {}})).toMatch(/unknown/);
    } finally {
      spy.mockRestore();
    }
    expect(errors.join("\n")).toMatch(/could not read the project id/);
  });

  test("says so when nothing resolves, rather than guessing", () => {
    delete process.env.GOOGLE_CLOUD_PROJECT;
    delete process.env.GCLOUD_PROJECT;
    delete process.env.GOOGLE_APPLICATION_CREDENTIALS;
    expect(resolveProjectId({options: {}})).toMatch(/unknown/);
  });
});

describe("printTargetBanner", () => {
  const env = {...process.env};
  let lines;
  let spy;

  beforeEach(() => {
    lines = [];
    spy = jest.spyOn(console, "log").mockImplementation((msg) => {
      lines.push(msg);
    });
  });

  afterEach(() => {
    spy.mockRestore();
    process.env = {...env};
  });

  test("says LIVE when there is no emulator, and names the project", () => {
    delete process.env.FIRESTORE_EMULATOR_HOST;
    const target = printTargetBanner({options: {projectId: "prod-1"}},
        {dryRun: false});

    expect(target).toBe("prod-1");
    expect(lines.join("\n")).toContain("target: prod-1");
    expect(lines.join("\n")).toContain("(LIVE)");
    // A run that WILL write must not wear the dry-run label.
    expect(lines.join("\n")).not.toContain("[dry-run]");
  });

  test("labels a dry run and names the emulator instead of LIVE", () => {
    process.env.FIRESTORE_EMULATOR_HOST = "localhost:8080";
    printTargetBanner({options: {projectId: "prod-1"}}, {dryRun: true});

    const out = lines.join("\n");
    expect(out).toContain("[dry-run]");
    expect(out).toContain("via emulator localhost:8080");
    expect(out).not.toContain("(LIVE)");
  });
});

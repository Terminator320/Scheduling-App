"use strict";

const {
  assertKnownFlags,
  formatNanpNumber,
  patchFor,
  resolveProjectId,
} = require("../scripts/backfill-client-phone-formatting");

describe("assertKnownFlags", () => {
  test("accepts the real flags", () => {
    expect(() => assertKnownFlags([])).not.toThrow();
    expect(() => assertKnownFlags(["--dry-run"])).not.toThrow();
  });

  test("refuses a MISTYPED --dry-run rather than going live", () => {
    const typos = ["--dryrun", "--dry_run", "-dry-run", "--dry-run=true"];
    for (const typo of typos) {
      expect(() => assertKnownFlags([typo])).toThrow(/unknown argument/);
    }
  });
});

describe("formatNanpNumber", () => {
  test("formats a bare ten-digit number", () => {
    expect(formatNanpNumber("4506220931")).toBe("(450) 622-0931");
  });

  test("normalizes a number written with other separators", () => {
    expect(formatNanpNumber("450-622-0931")).toBe("(450) 622-0931");
    expect(formatNanpNumber("450.622.0931")).toBe("(450) 622-0931");
  });

  test("returns null for an already-formatted number", () => {
    // Idempotence: the second run must write nothing at all.
    expect(formatNanpNumber("(450) 622-0931")).toBeNull();
  });

  test("drops a leading 1 — it is the +1 country code", () => {
    // The live mask renders these "(151) 455-5123 4", reading the country code
    // as part of the area code. Same number as the ten-digit form.
    expect(formatNanpNumber("15145551234")).toBe("(514) 555-1234");
    expect(formatNanpNumber("1-450-622-0931")).toBe("(450) 622-0931");
    expect(formatNanpNumber("+1 450 622 0931")).toBe("(450) 622-0931");
  });

  test("leaves a genuinely foreign number alone", () => {
    // No fixed 10-digit shape, so bracketing its first three digits as an area
    // code would be wrong. The second is TEN digits, which is why the "+" bar
    // on that branch is load-bearing rather than belt-and-braces.
    expect(formatNanpNumber("+33 1 23 45 67 89")).toBeNull();
    expect(formatNanpNumber("+49 30 123456")).toBeNull();
  });

  test("leaves a short or extension-bearing number alone", () => {
    expect(formatNanpNumber("5551234")).toBeNull();
    expect(formatNanpNumber("4506220931 x42")).toBeNull();
    expect(formatNanpNumber("")).toBeNull();
    expect(formatNanpNumber(undefined)).toBeNull();
  });
});

describe("patchFor", () => {
  test("formats the phone and re-states a name that IS that number", () => {
    expect(patchFor({name: "4506220931", phone: "4506220931"})).toEqual({
      phone: "(450) 622-0931",
      name: "(450) 622-0931",
    });
  });

  test("formats phone and mobile independently", () => {
    expect(patchFor({name: "Marc Tremblay", phone: "4506220931",
      mobile: "5145551234"})).toEqual({
      phone: "(450) 622-0931",
      mobile: "(514) 555-1234",
    });
  });

  test("never touches a BUSINESS name", () => {
    // Its name is its own, not its number — the one field this script must
    // not move.
    expect(patchFor({name: "Yokohama", phone: "4389698652"}))
        .toEqual({phone: "(438) 969-8652"});
  });

  test("leaves a name holding a DIFFERENT number alone", () => {
    // Only this client's own number is a rename artefact; anything else is a
    // name we know nothing about.
    expect(patchFor({name: "5149998888", phone: "4506220931"}))
        .toEqual({phone: "(450) 622-0931"});
  });

  test("is idempotent — a formatted doc needs no patch", () => {
    expect(patchFor({name: "(450) 622-0931", phone: "(450) 622-0931"}))
        .toBeNull();
  });

  test("skips a client with nothing to format", () => {
    expect(patchFor({name: "Marc Tremblay", phone: "", mobile: ""})).toBeNull();
    expect(patchFor({})).toBeNull();
  });
});

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
      require("path").join(__dirname, "fixtures", "fake-service-account.json");
    expect(resolveProjectId({options: {}})).toBe("schedulingapp-88727");
  });

  test("says so when nothing resolves, rather than guessing", () => {
    delete process.env.GOOGLE_CLOUD_PROJECT;
    delete process.env.GCLOUD_PROJECT;
    delete process.env.GOOGLE_APPLICATION_CREDENTIALS;
    expect(resolveProjectId({options: {}})).toMatch(/unknown/);
  });
});

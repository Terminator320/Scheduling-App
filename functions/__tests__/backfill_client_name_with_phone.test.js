"use strict";

const {
  assertKnownFlags,
  baseNameFor,
  otherNumbersIn,
  parseSince,
  patchFor,
} = require("../scripts/backfill-client-name-with-phone");

/** 2026-08-08T00:00:00Z — the script's default cutoff. */
const SINCE = Date.parse("2026-08-08T00:00:00Z");

/**
 * A Firestore-Timestamp-shaped stub.
 * @param {string} iso An ISO-8601 instant.
 * @return {{toMillis: function(): number}}
 */
const ts = (iso) => ({toMillis: () => Date.parse(iso)});

/**
 * An old-enough client with a phone, unless overridden.
 * @param {!Object=} over Fields to replace.
 * @return {!Object} A client document.
 */
const client = (over) => ({
  name: "Marc Tremblay",
  phone: "(514) 555-1234",
  createdAt: ts("2026-01-01T00:00:00Z"),
  ...over,
});

describe("assertKnownFlags", () => {
  test("accepts the real flags", () => {
    expect(() => assertKnownFlags([])).not.toThrow();
    expect(() => assertKnownFlags(["--dry-run"])).not.toThrow();
    expect(() => assertKnownFlags(["--dry-run", "--since=2026-01-01"]))
        .not.toThrow();
  });

  test("refuses a MISTYPED --dry-run rather than going live", () => {
    // The worst failure this script has: `argv.includes("--dry-run")` is an
    // exact match, so every one of these would otherwise read as false and
    // bulk-rename Wave customers for real.
    for (const typo of ["--dryrun", "--dry_run", "-dry-run", "--dry-run=true",
      "--dry"]) {
      expect(() => assertKnownFlags([typo])).toThrow(/unknown argument/);
    }
  });

  test("refuses an unknown flag", () => {
    expect(() => assertKnownFlags(["--force"])).toThrow(/unknown argument/);
  });
});

describe("otherNumbersIn", () => {
  const NUMBER = "(514) 555-1234";

  test("a normal composed name has nothing left over", () => {
    expect(otherNumbersIn("Marc Tremblay (514) 555-1234", NUMBER)).toEqual([]);
  });

  test("flags a name that ended up holding a SECOND number", () => {
    // The doc's name carried an OLD line that is not the number now in
    // `phone`, so the strip left it and the compose appended beside it.
    expect(otherNumbersIn(
        "Marc Tremblay 514-999-8888 (514) 555-1234", NUMBER))
        .toEqual(["5149998888"]);
  });

  test("ignores digit runs that are not phone-shaped", () => {
    // The false positives that would make this report unreadable: a business
    // named with a number, and a unit number in the name.
    expect(otherNumbersIn("Depanneur 2000 (514) 555-1234", NUMBER)).toEqual([]);
    expect(otherNumbersIn("Acme Suite 12345 (514) 555-1234", NUMBER))
        .toEqual([]);
  });

  test("does not depend on the appended number being strippable", () => {
    // Defensive: if the suffix is not found the whole name is scanned, which
    // over-reports rather than under-reports. This list must never go quiet.
    expect(otherNumbersIn("Marc Tremblay 514-999-8888", "").length)
        .toBeGreaterThan(0);
  });
});

describe("parseSince", () => {
  test("defaults to the day the rename ran", () => {
    expect(parseSince([])).toBe(SINCE);
  });

  test("reads an explicit date", () => {
    expect(parseSince(["--since=2026-01-15"]))
        .toBe(Date.parse("2026-01-15T00:00:00Z"));
  });

  test("throws rather than silently widening the scope", () => {
    // A bad flag must never fall back to "every client ever" — this script
    // rewrites customer names in Wave.
    expect(() => parseSince(["--since=last-week"])).toThrow();
    expect(() => parseSince(["--since=2026-13-99"])).toThrow();
  });
});

describe("patchFor", () => {
  test("puts the number back on the end of the name", () => {
    expect(patchFor(client(), SINCE))
        .toEqual({name: "Marc Tremblay (514) 555-1234"});
  });

  test("is idempotent — a second run writes nothing", () => {
    const already = client({name: "Marc Tremblay (514) 555-1234"});
    expect(patchFor(already, SINCE)).toBeNull();
  });

  test("normalizes a legacy number already in the name", () => {
    // The number is there but in the shape it was typed years ago; the patch
    // re-states it in the stored form so Wave and the doc agree.
    expect(patchFor(client({name: "Marc Tremblay 514-555-1234"}), SINCE))
        .toEqual({name: "Marc Tremblay (514) 555-1234"});
  });

  test("skips a client created on or after the cutoff", () => {
    // "Not the ones that were just added" — owner call.
    expect(patchFor(client({createdAt: ts("2026-08-08T00:00:01Z")}), SINCE))
        .toBeNull();
    expect(patchFor(client({createdAt: ts("2026-08-20T00:00:00Z")}), SINCE))
        .toBeNull();
  });

  test("patches a doc with no createdAt", () => {
    // The field is backfilled lazily, so its absence means legacy, not new.
    expect(patchFor(client({createdAt: undefined}), SINCE))
        .toEqual({name: "Marc Tremblay (514) 555-1234"});
  });

  test("skips a client with no number to append", () => {
    expect(patchFor(client({phone: "", mobile: ""}), SINCE)).toBeNull();
  });

  test("uses mobile when there is no phone", () => {
    expect(patchFor(client({phone: "", mobile: "(438) 222-3333"}), SINCE))
        .toEqual({name: "Marc Tremblay (438) 222-3333"});
  });
});

describe("baseNameFor", () => {
  const numbers = {phone: "(514) 555-1234", mobile: ""};

  test("keeps a BUSINESS name rather than its contact person", () => {
    // The load-bearing case. A Wave-imported business carries the business in
    // `name` and a contact person in first/last; taking the halves here would
    // rename "Vogas Plumbing" to "Marc Tremblay" on real Wave invoices.
    expect(baseNameFor({
      name: "Vogas Plumbing",
      firstName: "Marc",
      lastName: "Tremblay",
    }, numbers)).toBe("Vogas Plumbing");
  });

  test("falls back to the halves when the name is only a number", () => {
    expect(baseNameFor({
      name: "(514) 555-1234",
      firstName: "Marc",
      lastName: "Tremblay",
    }, numbers)).toBe("Marc Tremblay");
  });

  test("falls back to the legacy businessName last", () => {
    expect(baseNameFor({name: "", businessName: "Acme Inc"}, numbers))
        .toBe("Acme Inc");
  });

  test("is empty when the doc has no name anywhere", () => {
    expect(baseNameFor({}, numbers)).toBe("");
  });
});

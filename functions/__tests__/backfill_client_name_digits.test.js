"use strict";

const {
  assertKnownFlags,
  patchFor,
} = require("../scripts/backfill-client-name-digits");

/** What the `phone` FIELD stores — formatted, and left that way. */
const NUMBER = "(514) 555-1234";

/** What `name` must end up as, in Wave and in this file. */
const BARE = "5145551234";

/**
 * A person already named by their formatted number, unless overridden.
 * @param {!Object=} over Fields to replace.
 * @return {!Object} A client document.
 */
const client = (over) => ({name: NUMBER, phone: NUMBER, ...over});

describe("assertKnownFlags", () => {
  test("accepts the real flags", () => {
    expect(() => assertKnownFlags([])).not.toThrow();
    expect(() => assertKnownFlags(["--dry-run"])).not.toThrow();
  });

  test("refuses a MISTYPED --dry-run rather than going live", () => {
    for (const typo of ["--dryrun", "--dry_run", "-dry-run", "--dry-run=true",
      "--dry"]) {
      expect(() => assertKnownFlags([typo])).toThrow(/unknown argument/);
    }
  });

  test("refuses --since, which this script deliberately does not take", () => {
    expect(() => assertKnownFlags(["--since=2026-01-01"]))
        .toThrow(/unknown argument/);
  });
});

describe("patchFor", () => {
  test("takes the punctuation off a number-named person", () => {
    expect(patchFor(client())).toEqual({name: BARE});
  });

  test("is idempotent — a second run writes nothing", () => {
    expect(patchFor(client({name: BARE}))).toBeNull();
  });

  test("uses mobile when there is no phone", () => {
    expect(patchFor({name: "(438) 222-3333", phone: "", mobile:
      "(438) 222-3333"})).toEqual({name: "4382223333"});
  });

  test("keeps the country code of an international number", () => {
    // `digitsOf` would shed a leading 1; `bareNumber` must not — the name is a
    // STORED value, not a comparison key.
    expect(patchFor(client({name: "+33 1 42 68 53 00",
      phone: "+33 1 42 68 53 00"}))).toEqual({name: "+33142685300"});
  });

  test("reformats a number stored in a different shape from the field", () => {
    // `stripPhone` digit-matches, so a legacy "514-555-1234" beside a stored
    // "(514) 555-1234" still reduces to nothing and is safe to rewrite.
    expect(patchFor(client({name: "514-555-1234"}))).toEqual({name: BARE});
  });

  test("skips a client with no number to be named after", () => {
    expect(patchFor(client({phone: "", mobile: ""}))).toBeNull();
  });

  test("skips a client with no name", () => {
    expect(patchFor(client({name: ""}))).toBeNull();
  });
});

describe("patchFor CANNOT rename anybody", () => {
  // The whole safety argument: a doc is only ever touched when its name
  // reduces to EMPTY once its own number comes off, so there is no human name
  // in there to lose. Each of these leaves a remainder.

  test("leaves a person still called by their name alone", () => {
    expect(patchFor(client({name: "Marc Tremblay"}))).toBeNull();
  });

  test("leaves a legacy name-plus-number alone", () => {
    // The rename backfill's job, not this one's. Touching it here would drop
    // the typed name with no half to catch it.
    expect(patchFor(client({name: `Marc Tremblay ${NUMBER}`}))).toBeNull();
  });

  test("leaves a BUSINESS alone, by type or by legacy businessName", () => {
    expect(patchFor(client({name: "Vogas Plumbing", type: "commercial"})))
        .toBeNull();
    expect(patchFor(client({name: "Acme", businessName: "Acme Inc"})))
        .toBeNull();
  });

  test("never blanks a business that happens to be named by a number", () => {
    // `composeStored` answers "" for a business — writing that would erase the
    // customer's identity in Wave.
    expect(patchFor(client({type: "commercial"}))).toBeNull();
    expect(patchFor(client({businessName: "3101-5696 qc inc."}))).toBeNull();
  });

  test("leaves a name carrying a DIFFERENT number alone", () => {
    // Not this client's own number, so `stripPhone` leaves it in place and the
    // remainder is non-empty.
    expect(patchFor(client({name: "(438) 999-0000"}))).toBeNull();
  });
});

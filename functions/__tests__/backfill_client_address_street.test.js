"use strict";

// Pins the per-doc rule of `backfill-client-address-street.js`.
//
// The properties that matter are the ones that make a bulk write over the
// whole client collection safe: it never empties an address, it never guesses
// when it has nothing to compare against, and re-running it writes nothing.

const {
  assertKnownFlags,
  hasLocalityFields,
  patchFor,
} = require("../scripts/backfill-client-address-street");

const MONTREAL = {
  city: "Montréal",
  province: "QC",
  postalCode: "H2X 1Y4",
  country: "Canada",
};

describe("patchFor", () => {
  test("reduces a stored full address to its street line", () => {
    expect(patchFor({
      address: "1234 Rue Principale, Montréal, QC H2X 1Y4, Canada",
      ...MONTREAL,
    })).toEqual({address: "1234 Rue Principale"});
  });

  test("keeps the apt prefix", () => {
    expect(patchFor({
      address: "4-1234 Rue Principale, Montréal, QC H2X 1Y4, Canada",
      ...MONTREAL,
    })).toEqual({address: "4-1234 Rue Principale"});
  });

  test("keeps a second street segment that is not a locality", () => {
    expect(patchFor({
      address: "100 Main St, Building A, Montréal, QC H2X 1Y4, Canada",
      ...MONTREAL,
    })).toEqual({address: "100 Main St, Building A"});
  });

  test("IDEMPOTENT — an already-reduced doc is skipped", () => {
    // What makes a crashed run safe to re-run, and a second pass free.
    expect(patchFor({address: "1234 Rue Principale", ...MONTREAL}))
        .toBeNull();
  });

  test("SKIPS a doc with no locality fields rather than guessing", () => {
    // With nothing to identify a tail, the reducer falls back to the first
    // segment — right for the Wave push, a GUESS for a write that replaces
    // stored data. These docs still render correctly through the composer.
    expect(patchFor({address: "77 Rue Peel, Montréal, QC"})).toBeNull();
  });

  test("skips a doc with no address", () => {
    expect(patchFor({...MONTREAL})).toBeNull();
    expect(patchFor({address: "   ", ...MONTREAL})).toBeNull();
    expect(patchFor({})).toBeNull();
  });

  test("NEVER empties an address", () => {
    // A street that IS the city name reduces to itself, not to "". A write of
    // "" here would be destructive, so it has to be unreachable rather than
    // merely unlikely.
    expect(patchFor({address: "Montréal", city: "Montréal"})).toBeNull();
  });

  test("only removes segments the doc itself still carries", () => {
    // The property that makes this incapable of losing information: whatever
    // it strips is still on the document, so the old string can be rebuilt
    // exactly.
    const data = {
      address: "1234 Rue Principale, Montréal, QC H2X 1Y4, Canada",
      ...MONTREAL,
    };
    const {address} = patchFor(data);
    const rebuilt = [
      address,
      data.city,
      `${data.province} ${data.postalCode}`,
      data.country,
    ].join(", ");
    expect(rebuilt).toBe(data.address);
  });

  test("does NOT re-space an address that has no locality tail", () => {
    // Caught by the first prod dry run. Three civic numbers, no locality
    // anywhere in the string — the reducer strips nothing but rejoins with
    // ", ", so a bare `street !== stored` guard wrote a cosmetic re-spelling
    // of data this script has no business touching.
    expect(patchFor({
      address: "2304,2308,2312 Philippe dolbec",
      ...MONTREAL,
    })).toBeNull();
  });

  test("does NOT strip a trailing comma on its own", () => {
    // Same dry run, same cause: the empty segment after the comma is dropped
    // by the split, changing the string while removing no locality.
    expect(patchFor({
      address: "203-3161 Blvd. De La Gare,",
      city: "Terrebonne",
      province: "QC",
    })).toBeNull();
  });

  test("still reduces when a tail IS there, alongside odd spacing", () => {
    // The guard must not become "never touch a differently-spaced address" —
    // a real locality tail still comes off.
    expect(patchFor({
      address: "2304,2308,2312 Philippe dolbec, Montréal, QC H2X 1Y4, Canada",
      ...MONTREAL,
    })).toEqual({address: "2304, 2308, 2312 Philippe dolbec"});
  });

  test("leaves a locality the doc does NOT carry in place", () => {
    // A stale tail that matches nothing on the doc is data, not duplication.
    expect(patchFor({
      address: "12 Rue Ontario, Laval, QC",
      city: "Montréal",
      province: "QC",
    })).toEqual({address: "12 Rue Ontario, Laval"});
  });
});

describe("hasLocalityFields", () => {
  test("true when any one of the four is present", () => {
    expect(hasLocalityFields({city: "Montréal"})).toBe(true);
    expect(hasLocalityFields({country: "Canada"})).toBe(true);
  });

  test("false when all four are missing or blank", () => {
    expect(hasLocalityFields({})).toBe(false);
    expect(hasLocalityFields({city: "  ", province: ""})).toBe(false);
  });
});

describe("assertKnownFlags", () => {
  test("accepts --dry-run", () => {
    expect(() => assertKnownFlags(["--dry-run"])).not.toThrow();
    expect(() => assertKnownFlags([])).not.toThrow();
  });

  test("REJECTS a misspelling that would silently go live", () => {
    // `--dryrun` reads as false to `argv.includes("--dry-run")`, so without
    // this the run writes to prod while the operator thinks it is rehearsing.
    expect(() => assertKnownFlags(["--dryrun"])).toThrow();
    expect(() => assertKnownFlags(["--dry_run"])).toThrow();
  });
});

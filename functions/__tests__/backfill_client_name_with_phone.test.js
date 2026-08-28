"use strict";

const {
  assertKnownFlags,
  parseSince,
  patchFor,
} = require("../scripts/backfill-client-name-with-phone");

/** 2026-08-08T00:00:00Z — the script's default cutoff. */
const SINCE = Date.parse("2026-08-08T00:00:00Z");

/** What the `phone` FIELD stores — formatted, and left that way. */
const NUMBER = "(514) 555-1234";

/** What a renamed person ends up called, in Wave and in this file. */
const BARE = "5145551234";

/**
 * A Firestore-Timestamp-shaped stub.
 * @param {string} iso An ISO-8601 instant.
 * @return {{toMillis: function(): number}}
 */
const ts = (iso) => ({toMillis: () => Date.parse(iso)});

/**
 * An old-enough person with a phone, unless overridden.
 * @param {!Object=} over Fields to replace.
 * @return {!Object} A client document.
 */
const client = (over) => ({
  name: "Marc Tremblay",
  phone: NUMBER,
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

describe("parseSince", () => {
  test("defaults to the day the first rename ran", () => {
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
  test("names a person by their phone number", () => {
    expect(patchFor(client(), SINCE))
        .toEqual({name: BARE, firstName: "Marc", lastName: "Tremblay"});
  });

  test("carries the name into the halves rather than destroying it", () => {
    // THE DATA LOSS THIS CLOSES: `backfill-client-phone-from-name.js` left
    // `name` alone on a doc with neither half, so for those docs `name` held
    // the ONLY copy and renaming it in place lost it — Firestore keeps no
    // history. The halves are what the app renders for a person, so the name
    // survives and no Wave identity changes.
    const patch = patchFor(client({name: "Jean Paul Belanger"}), SINCE);
    expect(patch).toEqual({
      name: BARE,
      firstName: "Jean Paul",
      lastName: "Belanger",
    });
  });

  test("never overwrites a half that already carries a name", () => {
    // On a BUSINESS these are the CONTACT PERSON, not the client.
    expect(patchFor(client({firstName: "Marc-Andre"}), SINCE))
        .toEqual({name: BARE});
  });

  test("is idempotent — a second run writes nothing", () => {
    expect(patchFor(client({name: BARE}), SINCE)).toBeNull();
  });

  test("reduces a name left in the formatted shape by an earlier run", () => {
    expect(patchFor(client({name: NUMBER}), SINCE)).toEqual({name: BARE});
  });

  test("replaces a legacy name-plus-number outright", () => {
    expect(patchFor(client({name: "Marc Tremblay 514-555-1234"}), SINCE))
        .toEqual({name: BARE, firstName: "Marc", lastName: "Tremblay"});
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
        .toEqual({name: BARE, firstName: "Marc", lastName: "Tremblay"});
  });

  test("skips a client with no number to be named after", () => {
    expect(patchFor(client({phone: "", mobile: ""}), SINCE)).toBeNull();
  });

  test("uses mobile when there is no phone", () => {
    expect(patchFor(client({phone: "", mobile: "(438) 222-3333"}), SINCE))
        .toEqual({
          name: "4382223333",
          firstName: "Marc",
          lastName: "Tremblay",
        });
  });
});

describe("patchFor leaves a BUSINESS alone", () => {
  // The load-bearing rule. A business's NAME is what identifies it in Wave, a
  // number in its place is unrecognisable on an invoice, and unlike a person
  // there is usually no first/last for the app to fall back on.

  test("by its type", () => {
    expect(patchFor(client({name: "Vogas Plumbing", type: "commercial"}),
        SINCE)).toBeNull();
    expect(patchFor(client({name: "Les Immeubles X", type: "building"}),
        SINCE)).toBeNull();
  });

  test("by its legacy businessName", () => {
    expect(patchFor(client({businessName: "Acme Inc"}), SINCE)).toBeNull();
  });

  test("by ANY digit left in the name, with no type at all", () => {
    // The Wave import sets no `type`, so these are recognisable only by name.
    // The digit is not always leading — "Condo 706" carries it on the end.
    for (const name of ["1505 Village de Bergerac", "3101-5696 qc inc.",
      "Condo 706", "Appartement 12"]) {
      expect(patchFor(client({name}), SINCE)).toBeNull();
    }
  });

  test("by a property token with no digit at all", () => {
    for (const name of ["Syndicat de copropriété du Parc",
      "Les Immeubles Rivière", "Résidence Bellevue"]) {
      expect(patchFor(client({name}), SINCE)).toBeNull();
    }
  });

  test("by a company token, with no type at all", () => {
    for (const name of ["Plomberie Gagnon inc.", "Gestion Marc Tremblay",
      "Constructions ABC Ltée", "Rénovations Enr.",
      "Information technology group", "Groupe Immobilier Nord"]) {
      expect(patchFor(client({name}), SINCE)).toBeNull();
    }
  });

  test("and never invents CONTACT halves out of a company's own name", () => {
    // The stored name still carries the legacy trailing number, so the patch
    // is real — it strips the number. But `composeStored` did not REPLACE
    // anything, so nothing was destroyed and there is nothing to rescue:
    // splitting here would push "first: Vogas, last: Plumbing" to Wave as this
    // company's contact person. `composeSave` guards this as `stored == base`.
    for (const data of [
      {name: `Vogas Plumbing ${NUMBER}`, type: "commercial"},
      {name: `Vogas Plumbing ${NUMBER}`, businessName: "Vogas Plumbing"},
      {name: `1505 Village de Bergerac ${NUMBER}`},
    ]) {
      const patch = patchFor(client(data), SINCE);
      expect(patch.firstName).toBeUndefined();
      expect(patch.lastName).toBeUndefined();
    }
  });

  test("but a person merely CONTAINING those letters is renamed", () => {
    // The false negative that would rename a real company is the expensive
    // one, but this is the false positive that would leave people unrenamed.
    for (const name of ["Vincent Cormier", "Lucie Ledoux", "Marc Enrico"]) {
      expect(patchFor(client({name}), SINCE)).toMatchObject({name: BARE});
    }
  });
});

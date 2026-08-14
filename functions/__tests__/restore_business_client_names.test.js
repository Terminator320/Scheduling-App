"use strict";

const {
  assertKnownFlags,
  patchFor,
  RESTORE,
} = require("../scripts/restore-business-client-names");

describe("assertKnownFlags", () => {
  test("accepts the real flags", () => {
    expect(() => assertKnownFlags([])).not.toThrow();
    expect(() => assertKnownFlags(["--dry-run"])).not.toThrow();
  });

  test("refuses a MISTYPED --dry-run rather than going live", () => {
    const typos = ["--dryrun", "--dry_run", "-dry-run"];
    for (const typo of typos) {
      expect(() => assertKnownFlags([typo])).toThrow(/unknown argument/);
    }
  });
});

describe("RESTORE", () => {
  test("every entry names a non-empty business", () => {
    const ids = Object.keys(RESTORE);
    expect(ids.length).toBeGreaterThan(0);
    for (const id of ids) {
      expect(typeof RESTORE[id]).toBe("string");
      expect(RESTORE[id].trim()).not.toBe("");
    }
  });

  test("Yokohama restores the COMPANY, not its contact person", () => {
    // The reason this map is hardcoded rather than derived from the halves:
    // this doc's firstName/lastName hold Mathieu Gaudreau, its contact.
    expect(RESTORE["3YCCKXnipIwnfZQcR9z6"]).toBe("Yokohama");
  });
});

describe("patchFor", () => {
  const doc = (over) => ({
    name: "(438) 969-8652",
    phone: "(438) 969-8652",
    firstName: "Mathieu",
    lastName: "Gaudreau",
    ...over,
  });

  test("restores the name and types the client commercial", () => {
    // `type` is the durable half — composeStored re-derives `name` on the next
    // edit, and only a business type stops it.
    expect(patchFor(doc(), "Yokohama"))
        .toEqual({name: "Yokohama", type: "commercial"});
  });

  test("acts on an unformatted number too", () => {
    expect(patchFor(doc({name: "4389698652", phone: "4389698652"}), "Yokohama"))
        .toEqual({name: "Yokohama", type: "commercial"});
  });

  test("leaves a doc that already carries a real name", () => {
    // Re-runnable: this is a repair made earlier, by hand or by this script.
    expect(patchFor(doc({name: "Yokohama"}), "Yokohama")).toBeNull();
  });

  test("leaves a number that is NOT this client's own", () => {
    // Then the name is something we know nothing about, and the report this
    // map came from is out of date for that doc.
    expect(patchFor(doc({name: "5149998888"}), "Yokohama")).toBeNull();
  });

  test("leaves a doc with no name at all", () => {
    expect(patchFor(doc({name: ""}), "Yokohama")).toBeNull();
  });
});

"use strict";

const {
  assertKnownFlags,
  classify,
  composedName,
  historicalNames,
  isRenamed,
  parseMax,
  splitName,
} = require("../scripts/restore-client-name-halves");

describe("isRenamed", () => {
  it("matches a name that is nothing but the doc's own number", () => {
    expect(isRenamed({name: "(514) 555-1234", phone: "(514) 555-1234"}))
        .toBe(true);
  });

  it("ignores the stored formatting on either side", () => {
    // The collection holds both shapes — the rename wrote `phone` verbatim.
    expect(isRenamed({name: "5145551234", phone: "(514) 555-1234"}))
        .toBe(true);
  });

  it("matches against `mobile` too", () => {
    expect(isRenamed({name: "(450) 622-0931", mobile: "4506220931"}))
        .toBe(true);
  });

  it("rejects a real name", () => {
    expect(isRenamed({name: "Marc Tremblay", phone: "(514) 555-1234"}))
        .toBe(false);
  });

  it("rejects a number that is NOT this client's", () => {
    // A business genuinely named with digits keeps its name.
    expect(isRenamed({name: "Depanneur 2000", phone: "(514) 555-1234"}))
        .toBe(false);
  });

  it("rejects a doc with no name", () => {
    expect(isRenamed({name: "", phone: "(514) 555-1234"})).toBe(false);
  });
});

describe("classify", () => {
  const renamed = {name: "(514) 555-1234", phone: "(514) 555-1234"};

  it("accepts a renamed doc with neither half", () => {
    expect(classify(renamed)).toBe("candidate");
  });

  it("refuses to clobber an existing first name", () => {
    // This is also what makes the script idempotent — a second run sees the
    // half it wrote last time and stops.
    expect(classify({...renamed, firstName: "Marc"})).toBe("hasName");
  });

  it("refuses to clobber an existing last name", () => {
    expect(classify({...renamed, lastName: "Tremblay"})).toBe("hasName");
  });

  it("names a typed business as its own reason, not as `hasName`", () => {
    // The tally is printed, and calling a business "already has a name" hides
    // the one class the header tells the operator to go and read.
    expect(classify({...renamed, type: "commercial"})).toBe("typedBusiness");
  });

  it("names a legacy business carrying `businessName` the same way", () => {
    expect(classify({...renamed, businessName: "Vogas Plumbing"}))
        .toBe("typedBusiness");
  });

  it("skips a doc that was never renamed", () => {
    expect(classify({name: "Marc Tremblay", phone: "(514) 555-1234"}))
        .toBe("notRenamed");
  });
});

describe("historicalNames", () => {
  const HOUR = 60 * 60 * 1000;

  /**
   * Minimal Firestore stand-in capturing the query it was asked for.
   *
   * @param {!Array<!Object>} docs Appointment documents to return.
   * @return {{db: !Object, asked: !Object}} The fake and the recorded query.
   */
  function fakeDb(docs) {
    const asked = {};
    const query = {
      where: (field, op, value) => {
        asked[field] = {op, value};
        return query;
      },
      orderBy: (field, dir) => {
        asked.orderBy = {field, dir};
        return query;
      },
      limit: (n) => {
        asked.limit = n;
        return query;
      },
      get: async () => ({docs: docs.map((d) => ({data: () => d}))}),
    };
    return {db: {collection: () => query}, asked};
  }

  const settled = (name, agoMs, extra = {}) => ({
    clientName: name,
    startTime: {toMillis: () => Date.now() - agoMs - HOUR},
    endTime: {toMillis: () => Date.now() - agoMs},
    ...extra,
  });

  it("orders newest-first and bounds the scan", async () => {
    // Without the orderBy the limit takes an ARBITRARY slice, so a busy
    // client's whole window can be future visits and the name reads as lost.
    const {db, asked} = fakeDb([]);
    await historicalNames(db, "c1");
    expect(asked.orderBy).toEqual({field: "startTime", dir: "desc"});
    expect(asked.limit).toBe(25);
    expect(asked.startTime.op).toBe("<");
  });

  it("returns the newest remembered name first", async () => {
    const {db} = fakeDb([
      settled("Marc Tremblay", HOUR),
      settled("Marc T", 48 * HOUR),
    ]);
    expect(await historicalNames(db, "c1"))
        .toEqual(["Marc Tremblay", "Marc T"]);
  });

  it("drops a visit that has not settled", async () => {
    // Still live means propagateClientEdits rewrote it, so it echoes the NEW
    // name and would remember the phone number back at us.
    const {db} = fakeDb([{
      clientName: "Marc Tremblay",
      startTime: {toMillis: () => Date.now() - HOUR},
      endTime: {toMillis: () => Date.now() + HOUR},
    }]);
    expect(await historicalNames(db, "c1")).toEqual([]);
  });

  it("drops a remembered value with no letters in it", async () => {
    expect(await historicalNames(fakeDb([settled("(514) 555-1234", HOUR)]).db,
        "c1")).toEqual([]);
  });

  it("de-duplicates a name repeated across visits", async () => {
    const {db} = fakeDb([
      settled("Marc Tremblay", HOUR),
      settled("Marc Tremblay", 72 * HOUR),
    ]);
    expect(await historicalNames(db, "c1")).toEqual(["Marc Tremblay"]);
  });

  it("falls back to startTime when a doc carries no endTime", async () => {
    // Console and Admin-SDK writes reach this script; the Dart model never
    // emits one.
    const {db} = fakeDb([{
      clientName: "Marc Tremblay",
      startTime: {toMillis: () => Date.now() - HOUR},
    }]);
    expect(await historicalNames(db, "c1")).toEqual(["Marc Tremblay"]);
  });
});

describe("splitName", () => {
  it("takes the last token as the surname", () => {
    expect(splitName("Marc Tremblay"))
        .toEqual({firstName: "Marc", lastName: "Tremblay"});
  });

  it("keeps every earlier token in the given name", () => {
    expect(splitName("Jean Paul Belanger"))
        .toEqual({firstName: "Jean Paul", lastName: "Belanger"});
  });

  it("leaves a one-token name with no surname", () => {
    // `displayFor` renders the first half alone unchanged, which beats
    // guessing which of the two halves a lone name is.
    expect(splitName("Cher")).toEqual({firstName: "Cher", lastName: ""});
  });

  it("collapses runs of whitespace", () => {
    expect(splitName("  Marc   Tremblay  "))
        .toEqual({firstName: "Marc", lastName: "Tremblay"});
  });

  it("yields nothing for an empty name", () => {
    expect(splitName("   ")).toEqual({firstName: "", lastName: ""});
  });
});

describe("composedName", () => {
  it("joins both halves", () => {
    expect(composedName({firstName: "Marc", lastName: "Tremblay"}))
        .toBe("Marc Tremblay");
  });

  it("returns one half on its own", () => {
    expect(composedName({firstName: "Marc"})).toBe("Marc");
  });

  it("returns empty when neither half is present", () => {
    expect(composedName({firstName: "  ", lastName: ""})).toBe("");
  });
});

describe("parseMax", () => {
  it("defaults to no limit", () => {
    expect(parseMax([])).toBe(Infinity);
  });

  it("reads a positive bound", () => {
    expect(parseMax(["--max=100"])).toBe(100);
  });

  it("throws on zero", () => {
    expect(() => parseMax(["--max=0"])).toThrow(/positive whole number/);
  });

  it("throws on a non-number rather than widening the run", () => {
    expect(() => parseMax(["--max=all"])).toThrow(/positive whole number/);
  });
});

describe("assertKnownFlags", () => {
  it("accepts the flags this script knows", () => {
    expect(() => assertKnownFlags(["--dry-run", "--max=10"])).not.toThrow();
  });

  it("rejects a mistyped --dry-run instead of going live", () => {
    // The whole point: `--dryrun` reads as false to `includes("--dry-run")`,
    // so a typo of the safety flag would otherwise be a live bulk write.
    expect(() => assertKnownFlags(["--dryrun"])).toThrow();
  });

  it("rejects an unknown flag", () => {
    expect(() => assertKnownFlags(["--force"])).toThrow();
  });
});

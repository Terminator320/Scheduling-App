const {
  extractPhone,
  patchFor,
} = require("../scripts/backfill-client-phone-from-name");

describe("extractPhone", () => {
  it("lifts a number out of a name in whatever shape it was typed", () => {
    expect(extractPhone("Marc Tremblay 514-555-1234")).toBe("(514) 555-1234");
    expect(extractPhone("Marc Tremblay (514) 555-1234")).toBe("(514) 555-1234");
    expect(extractPhone("Marc Tremblay 514.555.1234")).toBe("(514) 555-1234");
    expect(extractPhone("Marc Tremblay 5145551234")).toBe("(514) 555-1234");
    expect(extractPhone("Marc Tremblay 514 555 1234")).toBe("(514) 555-1234");
  });

  it("drops a leading NANP 1", () => {
    expect(extractPhone("Chez Luc 1-514-555-1234")).toBe("(514) 555-1234");
  });

  it("finds a number sitting before the name", () => {
    expect(extractPhone("514-555-1234 Marc Tremblay")).toBe("(514) 555-1234");
  });

  // The exactly-10 threshold is the whole guard against wrecking a name that
  // merely contains digits.
  it("ignores digits that are not a 10-digit number", () => {
    expect(extractPhone("Plomberie ABC")).toBeNull();
    expect(extractPhone("Chez Luc 2024")).toBeNull();
    expect(extractPhone("1450 Rue Principale")).toBeNull();
    expect(extractPhone("Depot H2X 1Y4")).toBeNull();
    expect(extractPhone("Unit 12-14 Boul Cure")).toBeNull();
    expect(extractPhone("")).toBeNull();
    expect(extractPhone(null)).toBeNull();
  });

  // An international number has no fixed shape, so bracketing its first three
  // digits as an area code would be wrong.
  it("leaves an international number alone", () => {
    expect(extractPhone("Fournisseur +33 1 42 68 53 00")).toBeNull();
  });

  it("takes the first clean number when several are present", () => {
    expect(extractPhone("Marc 514-555-1234 / 438-555-9876")).toBe(
        "(514) 555-1234",
    );
  });
});

describe("patchFor", () => {
  it("sets the phone and rebuilds the name from both halves", () => {
    expect(
        patchFor({
          name: "Marc Tremblay 514-555-1234",
          firstName: "Marc",
          lastName: "Tremblay",
          phone: "",
        }),
    ).toEqual({phone: "(514) 555-1234", name: "Marc Tremblay"});
  });

  // The number is lifted from either field — an unreachable client is the
  // whole problem — but the RENAME is gated on `name`, and this doc's name is
  // empty, so ClientRecord.fromMap displays it from businessName. Writing a
  // name here would shadow that fallback and replace the business with a
  // person, which is the same loss as the case below.
  it("lifts a number from the legacy businessName, without renaming", () => {
    expect(
        patchFor({
          name: "",
          businessName: "Plomberie ABC 514-555-1234",
          firstName: "Luc",
          lastName: "Gagnon",
          phone: "",
        }),
    ).toEqual({phone: "(514) 555-1234"});
  });

  // The dangerous shape: a CLEAN business name beside a polluted legacy
  // businessName. Searching the two joined found a number and renamed `name`
  // to the contact person, destroying "Plomberie ABC" irreversibly.
  it("never renames a clean name when only businessName has the number", () => {
    expect(
        patchFor({
          name: "Plomberie ABC",
          businessName: "Plomberie ABC 514-555-1234",
          firstName: "Luc",
          lastName: "Gagnon",
          phone: "",
        }),
    ).toEqual({phone: "(514) 555-1234"});
  });

  // A space-join let digits ending `name` meet digits starting `businessName`
  // and match a 10-digit run that exists in neither field.
  it("does not synthesise a number across the field boundary", () => {
    expect(
        patchFor({
          name: "Atelier 514",
          businessName: "5551234 Quebec Inc",
          firstName: "Luc",
          lastName: "Gagnon",
          phone: "",
        }),
    ).toBeNull();
  });

  // businessName is read-only legacy — the app never emits it, and fromMap's
  // name-falls-back-to-businessName half depends on it staying put.
  it("never writes businessName", () => {
    const patch = patchFor({
      name: "Plomberie ABC 514-555-1234",
      businessName: "Plomberie ABC 514-555-1234",
      firstName: "Luc",
      lastName: "Gagnon",
      phone: "",
    });
    expect(patch).not.toHaveProperty("businessName");
  });

  // A doc with no number in its name is a Wave-imported business client with a
  // contact person in first/last. Renaming it would replace the business. This
  // is the guard that lets the rename fall back to a single half safely.
  it("skips a doc with no number in its name, however complete it is", () => {
    expect(
        patchFor({
          name: "Plomberie ABC",
          firstName: "Luc",
          lastName: "Gagnon",
          phone: "",
        }),
    ).toBeNull();

    expect(
        patchFor({
          name: "Plomberie ABC",
          firstName: "Luc",
          lastName: "",
          phone: "",
        }),
    ).toBeNull();
  });

  it("never overwrites a phone that is already stored", () => {
    expect(
        patchFor({
          name: "Marc Tremblay 514-555-1234",
          firstName: "Marc",
          lastName: "Tremblay",
          phone: "(438) 555-9876",
        }),
    ).toEqual({name: "Marc Tremblay"});
  });

  // Owner call after the prod dry-run: requiring both halves left 39 of 347
  // docs still displayed as a bare phone number. Safe because the patched set
  // only ever has a number in `name` — there is nothing there to lose.
  it("renames from ONE half when that is all there is", () => {
    expect(
        patchFor({
          name: "5145551234",
          firstName: "Luc",
          lastName: "",
          phone: "",
        }),
    ).toEqual({phone: "(514) 555-1234", name: "Luc"});

    expect(
        patchFor({
          name: "5145551234",
          firstName: "",
          lastName: "Tremblay",
          phone: "",
        }),
    ).toEqual({phone: "(514) 555-1234", name: "Tremblay"});
  });

  it("leaves the name alone when there is no half at all", () => {
    expect(
        patchFor({
          name: "5145551234",
          firstName: "",
          lastName: "",
          phone: "",
        }),
    ).toEqual({phone: "(514) 555-1234"});
  });

  // A second run must find nothing left to do.
  it("is idempotent", () => {
    const first = patchFor({
      name: "Marc Tremblay 514-555-1234",
      firstName: "Marc",
      lastName: "Tremblay",
      phone: "",
    });
    expect(
        patchFor({
          name: first.name,
          firstName: "Marc",
          lastName: "Tremblay",
          phone: first.phone,
        }),
    ).toBeNull();
  });
});

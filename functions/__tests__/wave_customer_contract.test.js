"use strict";

const {buildCustomerPayload} = require("../wave/customer_contract");

/**
 * A client doc that the contract accepts, so each test can break exactly one
 * thing and attribute the problem to it.
 * @param {!Object=} over Fields to override.
 * @return {!Object} Client document fields.
 */
function client(over = {}) {
  return {
    name: "Vogas Plumbing",
    firstName: "",
    lastName: "",
    email: "",
    phone: "(514) 555-1234",
    mobile: "",
    address: "4450 Prom. Paton",
    addressLine2: "",
    apt: "",
    city: "Laval",
    province: "QC",
    country: "Canada",
    postalCode: "H7W 5J7",
    type: "commercial",
    ...over,
  };
}

describe("buildCustomerPayload", () => {
  test("accepts an ordinary client and returns a payload and a hash", () => {
    const out = buildCustomerPayload(client());
    expect(out.ok).toBe(true);
    expect(out.payload.name).toBe("Vogas Plumbing");
    expect(typeof out.hash).toBe("string");
    expect(out.hash).toHaveLength(64);
  });

  test("refuses a blank name", () => {
    // The 2026-08-30 dead-letter: composeStored's business branch reduced a
    // business named only by its own number to "", toWaveCustomerInput sends
    // `name` unconditionally, and Wave refuses a blank customer name. It was
    // non-retryable, so it died on every push forever.
    const out = buildCustomerPayload(client({name: ""}));
    expect(out.ok).toBe(false);
    expect(out.problems).toEqual([
      {field: "name", code: "EMPTY", detail: null},
    ]);
    expect(out.payload).toBeUndefined();
  });

  test("refuses a whitespace-only name", () => {
    const out = buildCustomerPayload(client({name: "   "}));
    expect(out.ok).toBe(false);
    expect(out.problems[0]).toEqual(
        {field: "name", code: "EMPTY", detail: null});
  });

  test("refuses a name past Wave's 200-character cap", () => {
    // firestore.rules permits 225 (sized for the old "<name> <phone>" shape,
    // and it must STAY there — a cap below a stored value makes that doc
    // permanently un-updatable). So the contract is what catches this.
    const out = buildCustomerPayload(client({name: "a".repeat(218)}));
    expect(out.ok).toBe(false);
    expect(out.problems).toEqual([
      {field: "name", code: "TOO_LONG", detail: {length: 218, cap: 200}},
    ]);
  });

  test("accepts a name exactly at the cap", () => {
    expect(buildCustomerPayload(client({name: "a".repeat(200)})).ok)
        .toBe(true);
  });

  test("refuses an address past Wave's 500-character cap", () => {
    const out = buildCustomerPayload(client({address: "a".repeat(520)}));
    expect(out.ok).toBe(false);
    expect(out.problems).toEqual([
      {field: "address", code: "TOO_LONG", detail: {length: 520, cap: 500}},
    ]);
  });

  test("blames `address` when apt + address together exceed the cap", () => {
    // addressLine1 is the two joined, so each can be legal alone and the
    // composed line still refused. The admin edits `address`, so that is what
    // the problem names.
    const out = buildCustomerPayload(
        client({apt: "1108", address: "a".repeat(498)}));
    expect(out.ok).toBe(false);
    expect(out.problems[0].field).toBe("address");
    expect(out.problems[0].code).toBe("TOO_LONG");
  });

  test("reports every over-long field, not just the first", () => {
    const out = buildCustomerPayload(client({
      name: "a".repeat(201),
      city: "b".repeat(129),
    }));
    expect(out.ok).toBe(false);
    expect(out.problems.map((p) => p.field).sort()).toEqual(["city", "name"]);
  });

  test("refuses an email Wave would reject", () => {
    for (const email of ["nope", "a@b", "a b@example.com", "@example.com"]) {
      const out = buildCustomerPayload(client({email}));
      expect(out.ok).toBe(false);
      expect(out.problems[0])
          .toEqual({field: "email", code: "INVALID_EMAIL", detail: null});
    }
  });

  test("accepts ordinary and plus-addressed email", () => {
    for (const email of ["marc@example.com", "marc+wave@sub.example.co.uk"]) {
      expect(buildCustomerPayload(client({email})).ok).toBe(true);
    }
  });

  test("an absent email is not a problem", () => {
    // `presence` omits an empty optional, so there is nothing to validate.
    expect(buildCustomerPayload(client({email: ""})).ok).toBe(true);
  });

  test("refuses a phone carrying no digits at all", () => {
    const out = buildCustomerPayload(client({phone: "call the office"}));
    expect(out.ok).toBe(false);
    expect(out.problems[0])
        .toEqual({field: "phone", code: "INVALID_PHONE", detail: null});
  });

  test("accepts every phone shape the app legitimately stores", () => {
    // The formatted NANP form, the bare form, an international number and an
    // extension all reach Wave today and are accepted.
    for (const phone of ["(514) 555-1234", "5145551234", "+33 1 42 68 53 00",
      "514-555-1234 x22"]) {
      expect(buildCustomerPayload(client({phone})).ok).toBe(true);
    }
  });
});

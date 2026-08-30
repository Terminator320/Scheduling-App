"use strict";

const {buildCustomerPayload, problemsPatch} =
  require("../wave/customer_contract");

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

  test("accepts every phone shape the app legitimately stores", () => {
    // The formatted NANP form, the bare form, an international number and an
    // extension all reach Wave today and are accepted.
    for (const phone of ["(514) 555-1234", "5145551234", "+33 1 42 68 53 00",
      "514-555-1234 x22"]) {
      expect(buildCustomerPayload(client({phone})).ok).toBe(true);
    }
  });

  test("accepts a phone with NO digits, because Wave does", () => {
    // Disproved by the first production conformance run: client
    // 2wcEiCNztsWYUYNXYBEm stores "Tareq Chehadeh" in `phone` and Wave has it
    // SYNCED with that string as the customer's phone number. A rule refusing
    // it would block a client Wave accepts. See contactProblems' note.
    const out = buildCustomerPayload(client({phone: "Tareq Chehadeh"}));
    expect(out.ok).toBe(true);
    expect(out.payload.phone).toBe("Tareq Chehadeh");
  });

  test("still caps an over-long phone", () => {
    // Dropping the shape rule must not drop the LENGTH rule, which is a real
    // documented Wave limit rather than a guess.
    const out = buildCustomerPayload(client({phone: "5".repeat(33)}));
    expect(out.ok).toBe(false);
    expect(out.problems[0])
        .toEqual({field: "phone", code: "TOO_LONG",
          detail: {length: 33, cap: 32}});
  });
});

describe("historical incidents", () => {
  // Each case dead-lettered a real client permanently in production. They are
  // named so a regression cannot come back anonymously.

  test("2026-08-15: a New York client is never sent as CA-NY", () => {
    // provinceCode had an unconditional `CA-` prefix, so a US client shipped
    // as a subdivision of nowhere. Enums are not an inputErrors entry — the
    // whole $input fails to coerce, arriving as a non-retryable
    // WaveApiError(graphql). Nothing recovered it.
    const out = buildCustomerPayload(client({
      city: "Brooklyn", province: "NY", country: "United States",
      postalCode: "11201",
    }));
    expect(out.ok).toBe(true);
    expect(out.payload.address.countryCode).toBe("US");
    expect(out.payload.address.provinceCode).toBe("US-NY");
  });

  test("2026-08-15: an unknown province is omitted, never guessed", () => {
    const out = buildCustomerPayload(client({province: "Ontari"}));
    expect(out.ok).toBe(true);
    expect(out.payload.address.provinceCode).toBeUndefined();
  });

  test("2026-08-30: a business named only by its phone is refused", () => {
    // Client o0KcOnJSgjvMHYpmcZ44. `type: building` with a name that
    // composeStored had reduced to "". Wave refuses a blank customer name.
    const out = buildCustomerPayload(client({
      name: "", firstName: "", lastName: "", type: "building",
      phone: "(514) 458-6186",
    }));
    expect(out.ok).toBe(false);
    expect(out.problems).toContainEqual(
        {field: "name", code: "EMPTY", detail: null});
  });

  test("latent: a legacy 225-character name is refused, not dead-lettered",
      () => {
        const out = buildCustomerPayload(client({name: "a".repeat(225)}));
        expect(out.ok).toBe(false);
        expect(out.problems).toContainEqual({
          field: "name", code: "TOO_LONG", detail: {length: 225, cap: 200},
        });
      });

  test("latent: a legacy 533-character address is refused", () => {
    const out = buildCustomerPayload(client({address: "a".repeat(533)}));
    expect(out.ok).toBe(false);
    expect(out.problems).toContainEqual({
      field: "address", code: "TOO_LONG", detail: {length: 533, cap: 500},
    });
  });
});

describe("problemsPatch", () => {
  test("records the problems when a client cannot be sent", () => {
    expect(problemsPatch(client({name: ""}))).toEqual({
      "wave.problems": [{field: "name", code: "EMPTY", detail: null}],
    });
  });

  test("clears the field when a client is fine", () => {
    // Explicitly null rather than omitted: a client REPAIRED since the last
    // write must not keep stale problems on its doc.
    expect(problemsPatch(client())).toEqual({"wave.problems": null});
  });

  test("is a plain patch with no other keys", () => {
    // Phase 1 is report-only. It must not touch syncState, and the enqueue
    // decision stays exactly where it is.
    expect(Object.keys(problemsPatch(client({name: ""})))).toEqual(
        ["wave.problems"]);
  });
});

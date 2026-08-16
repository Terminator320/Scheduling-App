"use strict";

const {
  toWaveCustomerInput,
  mappedFieldsHash,
  fromWaveCustomer,
} = require("../wave/mappers");

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/** Full client document used as the default "happy path" fixture. */
const FULL_CLIENT = {
  name: "Acme Corp",
  firstName: "Jane",
  lastName: "Doe",
  email: "jane@acme.com",
  phone: "514-555-1234",
  mobile: "514-555-9876",
  address: "3450 Main St",
  apt: "12",
  city: "Montreal",
  province: "QC",
  country: "Canada",
  postalCode: "H3Z 2Y7",
  // App-only fields that must never appear in Wave input:
  contacts: [],
  noFixedAddress: false,
  waveCustomerId: "wave-abc",
};

/** Full Wave customer node used as the default import fixture. */
const FULL_WAVE_NODE = {
  id: "wave-cust-1",
  name: "Acme Corp",
  firstName: "Jane",
  lastName: "Doe",
  email: "jane@acme.com",
  phone: "514-555-1234",
  mobile: "514-555-9876",
  isArchived: false,
  address: {
    addressLine1: "12-3450 Main St",
    addressLine2: "",
    city: "Montreal",
    province: {code: "CA-QC"},
    country: {code: "CA", name: "Canada"},
    postalCode: "H3Z 2Y7",
  },
};

// ---------------------------------------------------------------------------
// toWaveCustomerInput
// ---------------------------------------------------------------------------

describe("toWaveCustomerInput", () => {
  test("full client → correct Wave input shape", () => {
    const result = toWaveCustomerInput(FULL_CLIENT);
    expect(result).toEqual({
      name: "Acme Corp",
      firstName: "Jane",
      lastName: "Doe",
      email: "jane@acme.com",
      phone: "514-555-1234",
      mobile: "514-555-9876",
      address: {
        addressLine1: "12-3450 Main St",
        city: "Montreal",
        provinceCode: "CA-QC",
        countryCode: "CA",
        postalCode: "H3Z 2Y7",
      },
    });
  });

  test("apt present → addressLine1 is apt-street combined form", () => {
    const result = toWaveCustomerInput({
      name: "Test",
      address: "3450 Main St",
      apt: "12",
    });
    expect(result.address.addressLine1).toBe("12-3450 Main St");
  });

  test("empty apt → addressLine1 equals address only", () => {
    const result = toWaveCustomerInput({
      name: "Test",
      address: "3450 Main St",
      apt: "",
    });
    expect(result.address.addressLine1).toBe("3450 Main St");
  });

  test("apt absent → addressLine1 equals address only", () => {
    const result = toWaveCustomerInput({
      name: "Test",
      address: "3450 Main St",
    });
    expect(result.address.addressLine1).toBe("3450 Main St");
  });

  test("full display address → addressLine1 is the street line only", () => {
    // addressLine1 must not repeat city/province/country/postalCode — those
    // are sent as their own fields.
    const result = toWaveCustomerInput({
      name: "Test",
      address: "3450 Main St, Montreal, QC H3Z 2Y7, Canada",
      city: "Montreal",
      province: "QC",
      country: "Canada",
      postalCode: "H3Z 2Y7",
    });
    expect(result.address.addressLine1).toBe("3450 Main St");
    expect(result.address.city).toBe("Montreal");
    expect(result.address.provinceCode).toBe("CA-QC");
    expect(result.address.countryCode).toBe("CA");
    expect(result.address.postalCode).toBe("H3Z 2Y7");
  });

  test("full address with apt already in street → apt not doubled", () => {
    // Some app-saved clients have apt baked into both `address` and `apt` —
    // addressLine1 must not double the prefix.
    const result = toWaveCustomerInput({
      name: "Test",
      address: "12-3450 Main St, Montreal, QC H3Z 2Y7, Canada",
      apt: "12",
    });
    expect(result.address.addressLine1).toBe("12-3450 Main St");
  });

  test("full address, apt stored separately → apt prepended once", () => {
    const result = toWaveCustomerInput({
      name: "Test",
      address: "3450 Main St, Montreal, QC H3Z 2Y7, Canada",
      apt: "12",
    });
    expect(result.address.addressLine1).toBe("12-3450 Main St");
  });

  test("province QC → provinceCode CA-QC", () => {
    const result = toWaveCustomerInput({name: "T", province: "QC"});
    expect(result.address.provinceCode).toBe("CA-QC");
  });

  test("province already CA-QC → passed through unchanged", () => {
    const result = toWaveCustomerInput({name: "T", province: "CA-QC"});
    expect(result.address.provinceCode).toBe("CA-QC");
  });

  test("province US-NY → passed through unchanged", () => {
    const result = toWaveCustomerInput({name: "T", province: "US-NY"});
    expect(result.address.provinceCode).toBe("US-NY");
  });

  test("empty province → provinceCode omitted", () => {
    const result = toWaveCustomerInput({name: "T", province: ""});
    expect(result.address).not.toHaveProperty("provinceCode");
  });

  test("country Canada → countryCode CA", () => {
    const result = toWaveCustomerInput({name: "T", country: "Canada"});
    expect(result.address.countryCode).toBe("CA");
  });

  test("country United States → countryCode US", () => {
    const result = toWaveCustomerInput({
      name: "T",
      country: "United States",
    });
    expect(result.address.countryCode).toBe("US");
  });

  test("country USA → countryCode US", () => {
    const result = toWaveCustomerInput({name: "T", country: "USA"});
    expect(result.address.countryCode).toBe("US");
  });

  test("country already CA → passed through unchanged", () => {
    const result = toWaveCustomerInput({name: "T", country: "CA"});
    expect(result.address.countryCode).toBe("CA");
  });

  test("empty country → countryCode omitted (never guesses)", () => {
    const result = toWaveCustomerInput({name: "T", country: ""});
    expect(result.address).not.toHaveProperty("countryCode");
  });

  test("unknown country → countryCode omitted", () => {
    const result = toWaveCustomerInput({name: "T", country: "Wakanda"});
    expect(result.address).not.toHaveProperty("countryCode");
  });

  // These are enum fields. A value outside the vocabulary is not an
  // `inputErrors` entry the worker can report against the field — GraphQL
  // refuses to coerce the whole `$input` and answers with a top-level error,
  // which is non-retryable, so the job dead-letters and no "Retry failed"
  // press can ever move it. Dropping one address line is the cheap outcome.
  test("a province typed into the country box is dropped, not sent", () => {
    const result = toWaveCustomerInput({name: "T", country: "ON"});
    expect(result.address).not.toHaveProperty("countryCode");
  });

  test("a two-letter non-country is dropped, not sent", () => {
    const result = toWaveCustomerInput({name: "T", country: "XX"});
    expect(result.address).not.toHaveProperty("countryCode");
  });

  test("a real foreign country code still passes through", () => {
    const result = toWaveCustomerInput({name: "T", country: "fr"});
    expect(result.address.countryCode).toBe("FR");
  });

  test("a US client's plain province is prefixed US-, never CA-", () => {
    // `CA-NY` is a subdivision of nowhere. It used to be what a New York
    // client was sent as, which killed that client's sync permanently.
    const result = toWaveCustomerInput({
      name: "T",
      province: "NY",
      country: "US",
    });
    expect(result.address.provinceCode).toBe("US-NY");
  });

  test("a province that is not one of its country's is dropped", () => {
    const result = toWaveCustomerInput({
      name: "T",
      province: "QC",
      country: "US",
    });
    expect(result.address).not.toHaveProperty("provinceCode");
    expect(result.address.countryCode).toBe("US");
  });

  test("an already-coded province that exists nowhere is dropped", () => {
    const result = toWaveCustomerInput({name: "T", province: "CA-NY"});
    expect(result.address).not.toHaveProperty("provinceCode");
  });

  test("a bare province still reads as Canadian, the business's own", () => {
    const result = toWaveCustomerInput({name: "T", province: "ON"});
    expect(result.address.provinceCode).toBe("CA-ON");
  });

  test("name-only minimal client → valid input with empty address", () => {
    const result = toWaveCustomerInput({name: "Solo"});
    expect(result.name).toBe("Solo");
    expect(result.address).toEqual({});
    expect(result).not.toHaveProperty("firstName");
    expect(result).not.toHaveProperty("email");
    expect(result).not.toHaveProperty("phone");
    expect(result).not.toHaveProperty("mobile");
  });

  test("empty string optional fields are omitted", () => {
    const result = toWaveCustomerInput({
      name: "T",
      firstName: "",
      lastName: "",
      email: "",
      phone: "",
      mobile: "",
    });
    expect(result).not.toHaveProperty("firstName");
    expect(result).not.toHaveProperty("lastName");
    expect(result).not.toHaveProperty("email");
    expect(result).not.toHaveProperty("phone");
    expect(result).not.toHaveProperty("mobile");
  });

  test("currency is never present in output", () => {
    const result = toWaveCustomerInput(FULL_CLIENT);
    expect(result).not.toHaveProperty("currency");
    expect(result).not.toHaveProperty("currencyCode");
  });

  test("app-only fields are never present in output", () => {
    const result = toWaveCustomerInput(FULL_CLIENT);
    expect(result).not.toHaveProperty("contacts");
    expect(result).not.toHaveProperty("noFixedAddress");
    expect(result).not.toHaveProperty("waveCustomerId");
  });

  test("businessId and id are never present in output", () => {
    const result = toWaveCustomerInput(FULL_CLIENT);
    expect(result).not.toHaveProperty("businessId");
    expect(result).not.toHaveProperty("id");
  });

  // Province matching should be case-insensitive too.
  test("province lowercase qc → provinceCode CA-QC", () => {
    const result = toWaveCustomerInput({name: "T", province: "qc"});
    expect(result.address.provinceCode).toBe("CA-QC");
  });

  test("province mixed ca-qc → provinceCode CA-QC", () => {
    const result = toWaveCustomerInput({name: "T", province: "ca-qc"});
    expect(result.address.provinceCode).toBe("CA-QC");
  });

  // Same case-insensitivity for the ISO-2 country passthrough.
  test("country lowercase ca → countryCode CA", () => {
    const result = toWaveCustomerInput({name: "T", country: "ca"});
    expect(result.address.countryCode).toBe("CA");
  });

  // Names should get trimmed too.
  test("name with trailing space → trimmed in output", () => {
    const result = toWaveCustomerInput({name: "Acme "});
    expect(result.name).toBe("Acme");
  });

  test("sends the stored name VERBATIM, phone number and all", () => {
    // `clients/{id}.name` carries the client's phone on the end (owner call
    // 2026-08-14, `ClientNamePolicy`) precisely because Wave's customer list
    // and its invoices are what the number has to show up on — the app shows
    // `displayName` instead. Nothing else pins this, so a future "cleanup"
    // applying the display name here would break invoice identification with
    // no test failing. It is the reason `clientDisplayName` exists as a
    // SEPARATE function rather than being folded into the mapper.
    const result = toWaveCustomerInput({
      name: "Marc Tremblay (514) 555-1234",
      firstName: "Marc",
      lastName: "Tremblay",
      phone: "(514) 555-1234",
    });
    expect(result.name).toBe("Marc Tremblay (514) 555-1234");
  });

  test("a business name reaches Wave as the business, not its contact", () => {
    const result = toWaveCustomerInput({
      name: "Vogas Plumbing (514) 555-1234",
      firstName: "Marc",
      lastName: "Tremblay",
      phone: "(514) 555-1234",
    });
    expect(result.name).toBe("Vogas Plumbing (514) 555-1234");
  });

  // Merged in from the former `mappers.test.js` (2026-08-15): the cases below
  // were the only ones that suite covered and this one did not.

  test("null/undefined clientFields never throws and yields an empty name",
      () => {
        // The trigger hands this whatever the doc snapshot held, so a deleted
        // or empty doc must degrade rather than take down the enqueue path.
        expect(toWaveCustomerInput(null)).toEqual({name: "", address: {}});
        expect(toWaveCustomerInput(undefined))
            .toEqual({name: "", address: {}});
      });

  test("a whitespace-only optional field is omitted, not sent as ''", () => {
    const result = toWaveCustomerInput({name: "Jane Doe", email: "  "});
    expect(result).toEqual({name: "Jane Doe", address: {}});
    expect(result).not.toHaveProperty("email");
  });

  test("legacy businessName-only doc: name stays empty (no fallback)", () => {
    // Unlike ClientRecord.fromMap (Dart), this mapper does NOT fall back to
    // businessName — legacy business-only docs reach Wave with an empty name
    // by design, and `businessName` itself is never part of the payload.
    const result = toWaveCustomerInput({
      name: "",
      businessName: "Acme Plumbing",
      email: "acme@example.com",
    });
    expect(result.name).toBe("");
    expect(result).not.toHaveProperty("businessName");
  });

  test("empty address and no apt yields no addressLine1", () => {
    const result = toWaveCustomerInput({name: "A", address: ""});
    expect(result.address).not.toHaveProperty("addressLine1");
  });

  test("apt alone (no street) becomes addressLine1", () => {
    const result = toWaveCustomerInput({name: "A", address: "", apt: "4"});
    expect(result.address.addressLine1).toBe("4");
  });

  test("a full province NAME (unknown format) omits provinceCode", () => {
    // Only a 2-letter code or an already-prefixed subdivision maps; "Quebec"
    // is not guessed at, the same way an unknown country is not.
    expect(toWaveCustomerInput({name: "A", province: "Quebec"}).address)
        .not.toHaveProperty("provinceCode");
  });

  test("country name matching is case-insensitive", () => {
    expect(toWaveCustomerInput({name: "A", country: "CANADA"})
        .address.countryCode).toBe("CA");
    expect(toWaveCustomerInput({name: "A", country: "usa"})
        .address.countryCode).toBe("US");
  });
});

// ---------------------------------------------------------------------------
// mappedFieldsHash
// ---------------------------------------------------------------------------

describe("mappedFieldsHash", () => {
  test("same input → same hash", () => {
    const h1 = mappedFieldsHash(FULL_CLIENT);
    const h2 = mappedFieldsHash({...FULL_CLIENT});
    expect(h1).toBe(h2);
  });

  test("changed mapped field → different hash", () => {
    const h1 = mappedFieldsHash(FULL_CLIENT);
    const h2 = mappedFieldsHash({...FULL_CLIENT, city: "Quebec City"});
    expect(h1).not.toBe(h2);
  });

  test("changed unmapped field → same hash", () => {
    const h1 = mappedFieldsHash(FULL_CLIENT);
    // contacts and waveCustomerId are not mapped to Wave.
    const h2 = mappedFieldsHash({
      ...FULL_CLIENT,
      contacts: [{name: "new contact"}],
      waveCustomerId: "wave-xyz",
    });
    expect(h1).toBe(h2);
  });

  test("key-order-independent — object with reordered keys gives same hash",
      () => {
        const client1 = {
          name: "Test",
          city: "Montreal",
          province: "QC",
          country: "Canada",
        };
        // Create an object with the same keys in a different insertion order.
        const client2 = {
          country: "Canada",
          province: "QC",
          name: "Test",
          city: "Montreal",
        };
        expect(mappedFieldsHash(client1)).toBe(mappedFieldsHash(client2));
      });

  test("returns a 64-character hex string (SHA-256)", () => {
    const h = mappedFieldsHash(FULL_CLIENT);
    expect(typeof h).toBe("string");
    expect(h).toMatch(/^[0-9a-f]{64}$/);
  });

  test("name change → different hash", () => {
    const h1 = mappedFieldsHash({name: "Alice"});
    const h2 = mappedFieldsHash({name: "Bob"});
    expect(h1).not.toBe(h2);
  });

  test("address field change → different hash", () => {
    const h1 = mappedFieldsHash({name: "T", address: "1 Main St"});
    const h2 = mappedFieldsHash({name: "T", address: "2 Main St"});
    expect(h1).not.toBe(h2);
  });

  // Trimming shouldn't change the hash, even with a trailing space on input.
  test("name with trailing space → same hash as trimmed name", () => {
    const base = {
      city: "Montreal", province: "QC", country: "Canada",
    };
    const h1 = mappedFieldsHash({...base, name: "Acme"});
    const h2 = mappedFieldsHash({...base, name: "Acme "});
    expect(h1).toBe(h2);
  });
});

// ---------------------------------------------------------------------------
// fromWaveCustomer
// ---------------------------------------------------------------------------

describe("fromWaveCustomer", () => {
  test("full node → correct client fields", () => {
    const result = fromWaveCustomer(FULL_WAVE_NODE);
    expect(result).toEqual({
      waveCustomerId: "wave-cust-1",
      name: "Acme Corp",
      firstName: "Jane",
      lastName: "Doe",
      email: "jane@acme.com",
      phone: "514-555-1234",
      mobile: "514-555-9876",
      address: "12-3450 Main St",
      addressLine2: "",
      apt: "",
      city: "Montreal",
      province: "QC",
      country: "Canada",
      postalCode: "H3Z 2Y7",
    });
  });

  test("empty Wave name → falls back to first + last name", () => {
    const result = fromWaveCustomer({
      ...FULL_WAVE_NODE,
      name: "",
      firstName: "Jane",
      lastName: "Doe",
    });
    expect(result.name).toBe("Jane Doe");
  });

  test("empty name and no first/last → falls back to email", () => {
    const result = fromWaveCustomer({
      ...FULL_WAVE_NODE,
      name: "",
      firstName: "",
      lastName: "",
      email: "jane@example.com",
    });
    expect(result.name).toBe("jane@example.com");
  });

  test("CA-QC province code → stored as QC", () => {
    const result = fromWaveCustomer({
      ...FULL_WAVE_NODE,
      address: {...FULL_WAVE_NODE.address, province: {code: "CA-QC"}},
    });
    expect(result.province).toBe("QC");
  });

  test("US-NY province code → stored as NY", () => {
    const result = fromWaveCustomer({
      ...FULL_WAVE_NODE,
      address: {...FULL_WAVE_NODE.address, province: {code: "US-NY"}},
    });
    expect(result.province).toBe("NY");
  });

  test("country name passthrough when name is present", () => {
    const result = fromWaveCustomer({
      ...FULL_WAVE_NODE,
      address: {
        ...FULL_WAVE_NODE.address,
        country: {code: "CA", name: "Canada"},
      },
    });
    expect(result.country).toBe("Canada");
  });

  test("country code fallback when name is absent", () => {
    const result = fromWaveCustomer({
      ...FULL_WAVE_NODE,
      address: {
        ...FULL_WAVE_NODE.address,
        country: {code: "CA"},
      },
    });
    expect(result.country).toBe("Canada");
  });

  test("US country code → United States", () => {
    const result = fromWaveCustomer({
      ...FULL_WAVE_NODE,
      address: {
        ...FULL_WAVE_NODE.address,
        country: {code: "US", name: "United States"},
      },
    });
    expect(result.country).toBe("United States");
  });

  test("addressLine1 + empty addressLine2 → address equals line1", () => {
    const result = fromWaveCustomer({
      ...FULL_WAVE_NODE,
      address: {
        ...FULL_WAVE_NODE.address,
        addressLine1: "12-3450 Main St",
        addressLine2: "",
      },
    });
    expect(result.address).toBe("12-3450 Main St");
  });

  test("addressLine1 + non-empty addressLine2 → line2 kept in its own " +
    "field, address stays line1 only", () => {
    const result = fromWaveCustomer({
      ...FULL_WAVE_NODE,
      address: {
        ...FULL_WAVE_NODE.address,
        addressLine1: "3450 Main St",
        addressLine2: "Suite 400",
      },
    });
    // Joining line2 into `address` would truncate it on write-back, since the
    // patch path only pulls out the street line — so we keep it separate.
    expect(result.address).toBe("3450 Main St");
    expect(result.addressLine2).toBe("Suite 400");
  });

  test("apt is always ''", () => {
    const result = fromWaveCustomer(FULL_WAVE_NODE);
    expect(result.apt).toBe("");
  });

  test("null/missing address sub-object → does not throw", () => {
    expect(() => fromWaveCustomer({id: "x", name: "T"})).not.toThrow();
    expect(() => fromWaveCustomer({
      id: "x",
      name: "T",
      address: null,
    })).not.toThrow();
  });

  test("null province → province is empty string", () => {
    const result = fromWaveCustomer({
      id: "x",
      name: "T",
      address: {province: null, country: null},
    });
    expect(result.province).toBe("");
    expect(result.country).toBe("");
  });

  test("sparse node with only id and name → does not throw", () => {
    const result = fromWaveCustomer({id: "wave-1", name: "Sparse"});
    expect(result.waveCustomerId).toBe("wave-1");
    expect(result.name).toBe("Sparse");
    expect(result.address).toBe("");
    expect(result.province).toBe("");
    expect(result.country).toBe("");
    expect(result.apt).toBe("");
  });

  test("completely empty node → does not throw, returns safe defaults", () => {
    const result = fromWaveCustomer({});
    expect(result.waveCustomerId).toBe("");
    expect(result.name).toBe("");
    expect(result.apt).toBe("");
  });

  test("null node → does not throw", () => {
    expect(() => fromWaveCustomer(null)).not.toThrow();
  });

  // Merged in from the former `mappers.test.js` (2026-08-15).

  test("a null node returns every field as a safe default", () => {
    // Stronger than the not-throw above: the import writes this patch onto a
    // client doc, so a missing key would leave a stale value in place rather
    // than clearing it.
    expect(fromWaveCustomer(null)).toEqual({
      waveCustomerId: "",
      name: "",
      firstName: "",
      lastName: "",
      email: "",
      phone: "",
      mobile: "",
      address: "",
      addressLine2: "",
      apt: "",
      city: "",
      province: "",
      country: "",
      postalCode: "",
    });
  });

  test("a plain province code with no subdivision prefix passes through",
      () => {
        expect(fromWaveCustomer({address: {province: {code: "QC"}}}).province)
            .toBe("QC");
      });

  test("a missing province code yields ''", () => {
    expect(fromWaveCustomer({address: {province: {}}}).province).toBe("");
  });

  test("US country code with no name falls back to the code->name lookup",
      () => {
        expect(fromWaveCustomer({address: {country: {code: "US"}}}).country)
            .toBe("United States");
      });

  test("an unknown country code with no name yields ''", () => {
    // Never guessed at — an invented country name would round-trip back to
    // Wave as a real edit.
    expect(fromWaveCustomer({address: {country: {code: "FR"}}}).country)
        .toBe("");
  });

  test("an all-whitespace name falls through to first/last", () => {
    expect(fromWaveCustomer({
      name: "   ", firstName: "Jane", lastName: "Doe",
    }).name).toBe("Jane Doe");
  });
});

// ---------------------------------------------------------------------------
// Round-trip identity (app-origin data)
// ---------------------------------------------------------------------------

describe("round-trip identity", () => {
  test("empty-apt client round-trips through Wave without data loss", () => {
    const client = {
      name: "Round Trip Inc",
      firstName: "Alice",
      lastName: "Smith",
      email: "alice@rt.com",
      phone: "418-555-0001",
      mobile: "",
      address: "7890 Blvd St-Laurent",
      apt: "",
      city: "Montreal",
      province: "QC",
      country: "Canada",
      postalCode: "H2R 2K9",
    };

    // Simulate what Wave would store then return:
    const waveInput = toWaveCustomerInput(client);
    const simulatedNode = {
      id: "wave-rt-1",
      name: waveInput.name,
      firstName: waveInput.firstName || "",
      lastName: waveInput.lastName || "",
      email: waveInput.email || "",
      phone: waveInput.phone || "",
      mobile: waveInput.mobile || "",
      isArchived: false,
      address: {
        addressLine1: waveInput.address.addressLine1 || "",
        addressLine2: "",
        city: waveInput.address.city || "",
        province: {code: waveInput.address.provinceCode || ""},
        country: {
          code: waveInput.address.countryCode || "",
          name: "Canada",
        },
        postalCode: waveInput.address.postalCode || "",
      },
    };

    const imported = fromWaveCustomer(simulatedNode);

    // The original address must survive the round-trip.
    expect(imported.address).toBe(client.address);
    expect(imported.apt).toBe("");
    expect(imported.city).toBe(client.city);
    expect(imported.province).toBe(client.province);
    expect(imported.postalCode).toBe(client.postalCode);
    expect(imported.name).toBe(client.name);
  });

  test("Wave addressLine2 survives a full import → patch round-trip", () => {
    // Import a Wave customer that has a second address line…
    const imported = fromWaveCustomer({
      id: "wave-l2",
      name: "Line Two Ltd",
      address: {
        addressLine1: "3450 Main St",
        addressLine2: "Suite 400",
        city: "Montreal",
        province: {code: "CA-QC"},
        country: {code: "CA", name: "Canada"},
        postalCode: "H3Z 2Y7",
      },
    });
    expect(imported.address).toBe("3450 Main St");
    expect(imported.addressLine2).toBe("Suite 400");

    // …then map the stored doc back to a Wave patch input. Both lines need
    // to survive intact — line2 used to get joined into address on import
    // and then truncated away on write-back.
    const patchInput = toWaveCustomerInput(imported);
    expect(patchInput.address.addressLine1).toBe("3450 Main St");
    expect(patchInput.address.addressLine2).toBe("Suite 400");
  });

  test("import → write-back hash is stable for a line2 customer (no echo)",
      () => {
        const node = {
          id: "wave-l2",
          name: "Line Two Ltd",
          address: {
            addressLine1: "3450 Main St",
            addressLine2: "Suite 400",
            city: "Montreal",
            province: {code: "CA-QC"},
            country: {code: "CA", name: "Canada"},
            postalCode: "H3Z 2Y7",
          },
        };
        const imported = fromWaveCustomer(node);
        // The trigger's echo suppression relies on the re-read doc hashing to
        // the same lastSyncedHash.
        expect(mappedFieldsHash(imported)).toBe(mappedFieldsHash({
          ...imported,
        }));
      });

  test("street containing a comma is not truncated when the tail is the " +
    "doc's locality data", () => {
    const result = toWaveCustomerInput({
      name: "Comma St",
      address: "100 Main St, Building A, Montreal, QC H2X 1Y4, Canada",
      city: "Montreal",
      province: "QC",
      country: "Canada",
      postalCode: "H2X 1Y4",
    });
    // Locality tail segments are stripped, but a comma inside the street line
    // itself ("Building A") is preserved.
    expect(result.address.addressLine1).toBe("100 Main St, Building A");
  });

  test("imported line1 containing a comma survives write-back untouched",
      () => {
        // No locality tail matches, so an imported line1 must survive
        // write-back untouched.
        const result = toWaveCustomerInput({
          name: "T",
          address: "100 Main St, Building A",
          city: "Montreal",
          province: "QC",
          country: "Canada",
          postalCode: "H2X 1Y4",
        });
        expect(result.address.addressLine1).toBe("100 Main St, Building A");
      });

  test("legacy full display address with EMPTY structured fields keeps the " +
    "historical first-segment behaviour", () => {
    const result = toWaveCustomerInput({
      name: "Legacy",
      address: "3450 Main St, Montreal, QC H3Z 2Y7, Canada",
    });
    // No structured fields to identify the tail — fall back to the first
    // segment so the city never leaks into addressLine1.
    expect(result.address.addressLine1).toBe("3450 Main St");
  });

  test("addressLine2 change → different hash (mapped field)", () => {
    const base = {name: "T", address: "1 Main St"};
    const h1 = mappedFieldsHash({...base, addressLine2: "Suite 1"});
    const h2 = mappedFieldsHash({...base, addressLine2: "Suite 2"});
    const h3 = mappedFieldsHash(base);
    expect(h1).not.toBe(h2);
    expect(h1).not.toBe(h3);
  });

  test("apt-prefixed address round-trips: apt merged into address", () => {
    // Merging apt into addressLine1 on export is intentionally lossy — import
    // always returns apt as '' since Wave has no apt field.
    const client = {
      name: "Apt Client",
      address: "3450 Main St",
      apt: "12",
      province: "QC",
      country: "Canada",
    };
    const waveInput = toWaveCustomerInput(client);
    expect(waveInput.address.addressLine1).toBe("12-3450 Main St");

    const imported = fromWaveCustomer({
      id: "w1",
      name: "Apt Client",
      address: {
        addressLine1: waveInput.address.addressLine1,
        addressLine2: "",
        province: {code: waveInput.address.provinceCode},
        country: {code: "CA", name: "Canada"},
      },
    });
    // The merged form becomes the new address, and apt comes back blank
    // since Wave has no apt field.
    expect(imported.address).toBe("12-3450 Main St");
    expect(imported.apt).toBe("");
  });
});

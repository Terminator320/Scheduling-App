"use strict";

const {
  toWaveCustomerInput,
  mappedFieldsHash,
  fromWaveCustomer,
} = require("../mappers");

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

  // Fix 1: province case-insensitivity
  test("province lowercase qc → provinceCode CA-QC", () => {
    const result = toWaveCustomerInput({name: "T", province: "qc"});
    expect(result.address.provinceCode).toBe("CA-QC");
  });

  test("province mixed ca-qc → provinceCode CA-QC", () => {
    const result = toWaveCustomerInput({name: "T", province: "ca-qc"});
    expect(result.address.provinceCode).toBe("CA-QC");
  });

  // Fix 1: country ISO-2 passthrough case-insensitivity
  test("country lowercase ca → countryCode CA", () => {
    const result = toWaveCustomerInput({name: "T", country: "ca"});
    expect(result.address.countryCode).toBe("CA");
  });

  // Fix 2: name trimming
  test("name with trailing space → trimmed in output", () => {
    const result = toWaveCustomerInput({name: "Acme "});
    expect(result.name).toBe("Acme");
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

  // Fix 2: name trim produces identical hash regardless of trailing space
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

  test("addressLine1 + non-empty addressLine2 → joined with ', '", () => {
    const result = fromWaveCustomer({
      ...FULL_WAVE_NODE,
      address: {
        ...FULL_WAVE_NODE.address,
        addressLine1: "3450 Main St",
        addressLine2: "Suite 400",
      },
    });
    expect(result.address).toBe("3450 Main St, Suite 400");
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

  test("apt-prefixed address round-trips: apt merged into address", () => {
    // When apt is present, toWaveCustomerInput merges it into addressLine1.
    // On import the merged string becomes `address` and apt is always ''.
    // This is the intended lossy-for-apt behaviour (Wave has no apt field).
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
    // The merged form becomes the new address; apt is blank (Wave has no apt).
    expect(imported.address).toBe("12-3450 Main St");
    expect(imported.apt).toBe("");
  });
});

"use strict";

const {
  toWaveCustomerInput,
  mappedFieldsHash,
  fromWaveCustomer,
} = require("../wave/mappers");

describe("toWaveCustomerInput", () => {
  test("maps a representative full client record", () => {
    const input = toWaveCustomerInput({
      name: "Jane Doe",
      firstName: "Jane",
      lastName: "Doe",
      email: "jane@example.com",
      phone: "5145551234",
      mobile: "5145555678",
      address: "123 Main St, Montreal, QC J4B1A1, Canada",
      city: "Montreal",
      province: "QC",
      postalCode: "J4B1A1",
      country: "Canada",
    });

    expect(input).toEqual({
      name: "Jane Doe",
      firstName: "Jane",
      lastName: "Doe",
      email: "jane@example.com",
      phone: "5145551234",
      mobile: "5145555678",
      address: {
        addressLine1: "123 Main St",
        city: "Montreal",
        provinceCode: "CA-QC",
        countryCode: "CA",
        postalCode: "J4B1A1",
      },
    });
  });

  test("null/undefined clientFields never throws and yields an empty name",
      () => {
        expect(toWaveCustomerInput(null)).toEqual({name: "", address: {}});
        expect(toWaveCustomerInput(undefined))
            .toEqual({name: "", address: {}});
      });

  test("optional string fields are omitted rather than sent as ''", () => {
    const input = toWaveCustomerInput({name: "Jane Doe", email: "  "});
    expect(input).toEqual({name: "Jane Doe", address: {}});
    expect(input).not.toHaveProperty("email");
  });

  // See CLAUDE.md's ClientRecord legacy back-compat note: pre-Wave-reshape
  // "business-only" client docs store the name under `businessName` with an
  // empty `name`. `ClientRecord.fromMap` (Dart) falls back name<-businessName
  // when READING such a doc, but this server-side mapper only ever reads
  // `f.name` when building the Wave input — it does not replicate that
  // fallback. For a legacy business-only doc this currently produces an
  // empty `name`, which Wave requires. Documented here as observed behavior,
  // not changed.
  test("legacy businessName-only doc: name stays empty (no fallback)", () => {
    const input = toWaveCustomerInput({
      name: "",
      businessName: "Acme Plumbing",
      email: "acme@example.com",
    });
    expect(input.name).toBe("");
    expect(input).not.toHaveProperty("businessName");
  });

  describe("street line extraction (via addressLine1)", () => {
    test("empty address and no apt yields no addressLine1", () => {
      const input = toWaveCustomerInput({name: "A", address: ""});
      expect(input.address).not.toHaveProperty("addressLine1");
    });

    test("a single-segment address (no commas) is used as-is", () => {
      const input = toWaveCustomerInput({
        name: "A",
        address: "123 Main St",
      });
      expect(input.address.addressLine1).toBe("123 Main St");
    });

    test("strips a locality tail matching city/province+postal/country",
        () => {
          const input = toWaveCustomerInput({
            name: "A",
            address: "123 Main St, Montreal, QC J4B1A1, Canada",
            city: "Montreal",
            province: "QC",
            postalCode: "J4B1A1",
            country: "Canada",
          });
          expect(input.address.addressLine1).toBe("123 Main St");
        });

    test("preserves a comma that is legitimately part of the street", () => {
      const input = toWaveCustomerInput({
        name: "A",
        address: "100 Main St, Building A, Montreal, QC J4B1A1, Canada",
        city: "Montreal",
        province: "QC",
        postalCode: "J4B1A1",
        country: "Canada",
      });
      expect(input.address.addressLine1).toBe("100 Main St, Building A");
    });

    test("legacy doc with no structured locality fields falls back to " +
        "the first segment", () => {
      const input = toWaveCustomerInput({
        name: "A",
        address: "123 Main St, Montreal, QC, Canada",
      });
      expect(input.address.addressLine1).toBe("123 Main St");
    });

    test("apt is prefixed onto the street when not already present", () => {
      const input = toWaveCustomerInput({
        name: "A",
        address: "123 Main St",
        apt: "4",
      });
      expect(input.address.addressLine1).toBe("4-123 Main St");
    });

    test("apt is not double-prefixed when the street already carries it",
        () => {
          const input = toWaveCustomerInput({
            name: "A",
            address: "4-123 Main St",
            apt: "4",
          });
          expect(input.address.addressLine1).toBe("4-123 Main St");
        });

    test("apt alone (no street) becomes addressLine1", () => {
      const input = toWaveCustomerInput({name: "A", address: "", apt: "4"});
      expect(input.address.addressLine1).toBe("4");
    });
  });

  describe("province code mapping", () => {
    test("a plain 2-letter province is prefixed with CA-", () => {
      expect(toWaveCustomerInput({name: "A", province: "QC"})
          .address.provinceCode).toBe("CA-QC");
    });

    test("an already-prefixed subdivision code passes through", () => {
      expect(toWaveCustomerInput({name: "A", province: "CA-QC"})
          .address.provinceCode).toBe("CA-QC");
    });

    test("a US-style subdivision code passes through unchanged", () => {
      expect(toWaveCustomerInput({name: "A", province: "US-NY"})
          .address.provinceCode).toBe("US-NY");
    });

    test("lowercase input is normalized to uppercase", () => {
      expect(toWaveCustomerInput({name: "A", province: "qc"})
          .address.provinceCode).toBe("CA-QC");
    });

    test("an empty province omits provinceCode", () => {
      expect(toWaveCustomerInput({name: "A", province: ""}).address)
          .not.toHaveProperty("provinceCode");
    });

    test("a full province name (unknown format) omits provinceCode", () => {
      expect(toWaveCustomerInput({name: "A", province: "Quebec"}).address)
          .not.toHaveProperty("provinceCode");
    });
  });

  describe("country code mapping", () => {
    test("a full country name maps to its ISO-2 code", () => {
      expect(toWaveCustomerInput({name: "A", country: "Canada"})
          .address.countryCode).toBe("CA");
    });

    test("mapping is case-insensitive on the name", () => {
      expect(toWaveCustomerInput({name: "A", country: "CANADA"})
          .address.countryCode).toBe("CA");
      expect(toWaveCustomerInput({name: "A", country: "usa"})
          .address.countryCode).toBe("US");
    });

    test("an already-2-letter ISO code passes through uppercased", () => {
      expect(toWaveCustomerInput({name: "A", country: "us"})
          .address.countryCode).toBe("US");
    });

    test("an unknown country name omits countryCode", () => {
      expect(toWaveCustomerInput({name: "A", country: "France"}).address)
          .not.toHaveProperty("countryCode");
    });

    test("an empty country omits countryCode", () => {
      expect(toWaveCustomerInput({name: "A", country: ""}).address)
          .not.toHaveProperty("countryCode");
    });
  });
});

describe("mappedFieldsHash", () => {
  const base = {
    name: "Jane Doe",
    firstName: "Jane",
    lastName: "Doe",
    email: "jane@example.com",
    phone: "5145551234",
    address: "123 Main St",
    city: "Montreal",
    province: "QC",
    postalCode: "J4B1A1",
    country: "Canada",
  };

  test("is a lowercase hex sha256 digest", () => {
    expect(mappedFieldsHash(base)).toMatch(/^[0-9a-f]{64}$/);
  });

  test("identical client fields produce an identical hash", () => {
    expect(mappedFieldsHash(base)).toBe(mappedFieldsHash({...base}));
  });

  test("changing a mapped field (email) changes the hash", () => {
    const changed = {...base, email: "other@example.com"};
    expect(mappedFieldsHash(changed)).not.toBe(mappedFieldsHash(base));
  });

  test("changing a mapped field (province) changes the hash", () => {
    const changed = {...base, province: "ON"};
    expect(mappedFieldsHash(changed)).not.toBe(mappedFieldsHash(base));
  });

  test("changing an unmapped field (contacts) leaves the hash unchanged",
      () => {
        const changed = {...base, contacts: [{phone: "999"}]};
        expect(mappedFieldsHash(changed)).toBe(mappedFieldsHash(base));
      });

  test("changing an unmapped field (waveCustomerId) leaves the hash " +
      "unchanged", () => {
    const changed = {...base, waveCustomerId: "cust-123"};
    expect(mappedFieldsHash(changed)).toBe(mappedFieldsHash(base));
  });
});

describe("fromWaveCustomer", () => {
  test("maps a representative Wave customer node", () => {
    const patch = fromWaveCustomer({
      id: "cust-123",
      name: "Jane Doe",
      firstName: "Jane",
      lastName: "Doe",
      email: "jane@example.com",
      phone: "5145551234",
      mobile: "5145555678",
      address: {
        addressLine1: "123 Main St",
        addressLine2: "Suite 200",
        city: "Montreal",
        province: {code: "CA-QC"},
        country: {code: "CA", name: "Canada"},
        postalCode: "J4B1A1",
      },
    });

    expect(patch).toEqual({
      waveCustomerId: "cust-123",
      name: "Jane Doe",
      firstName: "Jane",
      lastName: "Doe",
      email: "jane@example.com",
      phone: "5145551234",
      mobile: "5145555678",
      address: "123 Main St",
      addressLine2: "Suite 200",
      apt: "",
      city: "Montreal",
      province: "QC",
      country: "Canada",
      postalCode: "J4B1A1",
    });
  });

  test("apt is always returned as '' regardless of input", () => {
    expect(fromWaveCustomer({name: "A"}).apt).toBe("");
  });

  test("is defensive against a null node", () => {
    expect(() => fromWaveCustomer(null)).not.toThrow();
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

  test("is defensive against a missing address sub-object", () => {
    expect(() => fromWaveCustomer({name: "A"})).not.toThrow();
    const patch = fromWaveCustomer({name: "A"});
    expect(patch.address).toBe("");
    expect(patch.city).toBe("");
    expect(patch.province).toBe("");
    expect(patch.country).toBe("");
  });

  test("is defensive against a null province/country sub-object", () => {
    const patch = fromWaveCustomer({
      name: "A",
      address: {province: null, country: null},
    });
    expect(patch.province).toBe("");
    expect(patch.country).toBe("");
  });

  describe("province code round-trip", () => {
    test("a CA-XX subdivision code strips to the plain 2-letter code",
        () => {
          expect(fromWaveCustomer({address: {province: {code: "CA-QC"}}})
              .province).toBe("QC");
        });

    test("a plain code with no subdivision prefix passes through", () => {
      expect(fromWaveCustomer({address: {province: {code: "QC"}}})
          .province).toBe("QC");
    });

    test("a missing province code yields ''", () => {
      expect(fromWaveCustomer({address: {province: {}}}).province).toBe("");
    });
  });

  describe("country name recovery", () => {
    test("country.name is used directly when present", () => {
      expect(fromWaveCustomer({
        address: {country: {code: "CA", name: "Canada"}},
      }).country).toBe("Canada");
    });

    test("falls back to a code->name lookup when name is absent", () => {
      expect(fromWaveCustomer({address: {country: {code: "US"}}}).country)
          .toBe("United States");
    });

    test("an unknown code with no name yields ''", () => {
      expect(fromWaveCustomer({address: {country: {code: "FR"}}}).country)
          .toBe("");
    });
  });

  describe("name derivation", () => {
    test("uses node.name when present", () => {
      expect(fromWaveCustomer({
        name: "Jane Doe", firstName: "J", lastName: "D",
        email: "j@e.com",
      }).name).toBe("Jane Doe");
    });

    test("falls back to first+last name when node.name is absent", () => {
      expect(fromWaveCustomer({
        firstName: "Jane", lastName: "Doe", email: "j@e.com",
      }).name).toBe("Jane Doe");
    });

    test("falls back to email when name and first/last are all absent",
        () => {
          expect(fromWaveCustomer({email: "j@e.com"}).name)
              .toBe("j@e.com");
        });

    test("an all-whitespace name falls through to first/last", () => {
      expect(fromWaveCustomer({
        name: "   ", firstName: "Jane", lastName: "Doe",
      }).name).toBe("Jane Doe");
    });
  });
});

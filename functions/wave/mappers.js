"use strict";

/**
 * @fileoverview Pure field mapper between the app's Firestore client document
 * and Wave Accounting's customer GraphQL shapes.
 *
 * No Firebase, no network, no I/O — this module is fully synchronous and
 * deterministic so it can be unit-tested in isolation.
 *
 * @module wave/mappers
 */

const crypto = require("crypto");

// ---------------------------------------------------------------------------
// Country name ↔ ISO-3166-1 alpha-2 tables
// ---------------------------------------------------------------------------

/** @type {!Object<string, string>} Lowercase country name → ISO-2 code. */
const COUNTRY_NAME_TO_CODE = {
  "canada": "CA",
  "united states": "US",
  "usa": "US",
  "united states of america": "US",
};

/** @type {!Object<string, string>} ISO-2 code → display name. */
const COUNTRY_CODE_TO_NAME = {
  "CA": "Canada",
  "US": "United States",
};

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/**
 * Returns the string only if it is non-empty after trimming, else undefined.
 * Used to omit optional Wave fields that are empty strings.
 * @param {*} v Value to check.
 * @return {string|undefined}
 */
function presence(v) {
  if (typeof v !== "string") return undefined;
  const s = v.trim();
  return s.length > 0 ? s : undefined;
}

/**
 * Converts a stored province value to a Wave `provinceCode` (e.g. `CA-QC`).
 * - Already in `XX-YY` form → passed through unchanged.
 * - A plain 2-letter code → prefixed with `CA-`.
 * - Empty / falsy → returns undefined (field omitted).
 * @param {*} province Stored province field.
 * @return {string|undefined}
 */
function toProvinceCode(province) {
  if (!province || typeof province !== "string") return undefined;
  const p = province.trim().toUpperCase();
  if (!p) return undefined;
  // Already in subdivision-code form (e.g. CA-QC, US-NY).
  if (/^[A-Z]{2}-[A-Z]{2,3}$/.test(p)) return p;
  // Plain 2-letter province abbreviation → prepend CA-.
  if (/^[A-Z]{2}$/.test(p)) return `CA-${p}`;
  return undefined;
}

/**
 * Converts a stored country value to a Wave `countryCode` (ISO-2).
 * - Already a 2-letter ISO code → passed through unchanged.
 * - Known country name (case-insensitive) → mapped to ISO code.
 * - Unknown / empty → returns undefined (field omitted; never guesses).
 * @param {*} country Stored country field.
 * @return {string|undefined}
 */
function toCountryCode(country) {
  if (!country || typeof country !== "string") return undefined;
  const c = country.trim();
  if (!c) return undefined;
  // Already a 2-letter ISO code.
  if (/^[A-Z]{2}$/.test(c.toUpperCase())) return c.toUpperCase();
  // Look up by name (case-insensitive).
  return COUNTRY_NAME_TO_CODE[c.toLowerCase()] || undefined;
}

/**
 * Strips a leading subdivision prefix (e.g. `CA-`) from a Wave province code
 * to recover the stored 2-letter province abbreviation.
 * @param {*} code Wave province.code value.
 * @return {string} Plain 2-letter code, or empty string when absent.
 */
function fromProvinceCode(code) {
  if (!code || typeof code !== "string") return "";
  const m = code.trim().match(/^[A-Z]{2}-([A-Z]{2,3})$/);
  return m ? m[1] : code.trim();
}

/**
 * Converts a Wave country object (with code and optional name) to a stored
 * country display name.
 * - `country.name` is used directly when present.
 * - Falls back to a code→name lookup.
 * - Returns empty string when nothing is available.
 * @param {Object|null|undefined} country Wave country sub-object.
 * @return {string}
 */
function fromCountry(country) {
  if (!country) return "";
  const name = typeof country.name === "string" ? country.name.trim() : "";
  if (name) return name;
  const code = typeof country.code === "string" ? country.code.trim() : "";
  return COUNTRY_CODE_TO_NAME[code] || "";
}

// ---------------------------------------------------------------------------
// Exported functions
// ---------------------------------------------------------------------------

/**
 * Converts a Firestore client document's fields to a Wave customer input
 * object suitable for the Wave GraphQL `CustomerCreateInput` /
 * `CustomerPatchInput`. The caller is responsible for adding `businessId`
 * (and `id` for patch operations) — those are never included here.
 *
 * Empty optional strings are omitted rather than sent as `""`. `name` is
 * always included (it is required by Wave). The `address` sub-object is
 * always included with whatever address pieces are present; callers that do
 * not want a partial address object should check `clientFields.address`
 * before calling.
 *
 * Currency is intentionally omitted — Wave defaults to the business currency
 * and the app does not store a per-client currency override.
 *
 * @param {!Object} clientFields Firestore client document fields. Expected
 *   keys: name (required), firstName, lastName, email, phone, mobile,
 *   address, apt, city, province, country, postalCode.
 * @return {!Object} Wave customer input shape (without businessId/id).
 */
function toWaveCustomerInput(clientFields) {
  const f = clientFields || {};

  // Build addressLine1: when apt is present prefix it to the street address.
  // Stored as the combined form "12-3450 Main St" passed straight to Wave.
  // addressLine2 is intentionally omitted (Wave has it; the app does not).
  const apt = typeof f.apt === "string" ? f.apt.trim() : "";
  const street = typeof f.address === "string" ? f.address.trim() : "";
  const addressLine1 = apt.length > 0 ? `${apt}-${street}` : street;

  const addr = {};
  if (addressLine1) addr.addressLine1 = addressLine1;
  const city = presence(f.city);
  if (city) addr.city = city;
  const provinceCode = toProvinceCode(f.province);
  if (provinceCode) addr.provinceCode = provinceCode;
  const countryCode = toCountryCode(f.country);
  if (countryCode) addr.countryCode = countryCode;
  const postalCode = presence(f.postalCode);
  if (postalCode) addr.postalCode = postalCode;

  const rawName = typeof f.name === "string" ? f.name.trim() : "";
  const input = {name: rawName};
  const firstName = presence(f.firstName);
  if (firstName) input.firstName = firstName;
  const lastName = presence(f.lastName);
  if (lastName) input.lastName = lastName;
  const email = presence(f.email);
  if (email) input.email = email;
  const phone = presence(f.phone);
  if (phone) input.phone = phone;
  const mobile = presence(f.mobile);
  if (mobile) input.mobile = mobile;
  input.address = addr;

  return input;
}

/**
 * Computes a stable SHA-256 hex hash over the Wave customer input fields
 * derived from the given client document. The hash is key-order-independent
 * (keys are sorted before serialization), so the same logical data always
 * produces the same hash regardless of property insertion order in JS.
 *
 * Identical client fields → identical hash.
 * Any change to a mapped field → different hash.
 * Fields not mapped to Wave (contacts, waveCustomerId, etc.) are excluded.
 *
 * Use this to detect whether a sync patch would be a no-op.
 *
 * @param {!Object} clientFields Firestore client document fields.
 * @return {string} Lowercase hex SHA-256 digest.
 */
function mappedFieldsHash(clientFields) {
  const input = toWaveCustomerInput(clientFields);
  const canonical = stableStringify(input);
  return crypto.createHash("sha256").update(canonical, "utf8").digest("hex");
}

/**
 * Recursively serializes a value to a JSON string with object keys sorted
 * alphabetically so the result is independent of JS property-insertion order.
 * Arrays preserve their order (index order is semantically significant).
 * @param {*} value Any JSON-serializable value.
 * @return {string}
 */
function stableStringify(value) {
  if (value === null || typeof value !== "object") {
    return JSON.stringify(value);
  }
  if (Array.isArray(value)) {
    return "[" + value.map(stableStringify).join(",") + "]";
  }
  const sortedKeys = Object.keys(value).sort();
  const pairs = sortedKeys.map(
      (k) => JSON.stringify(k) + ":" + stableStringify(value[k]),
  );
  return "{" + pairs.join(",") + "}";
}

/**
 * Converts a Wave customer query node to a Firestore client document field
 * patch. Only fields that Wave owns are returned; callers merge this patch
 * onto the existing client doc.
 *
 * Defensive against sparse/null sub-objects: a missing `address` or nested
 * `province`/`country` never throws.
 *
 * `apt` is always returned as `''` — Wave's `addressLine2` is written blank
 * for app-origin customers, so the round-trip is lossless for that field.
 *
 * @param {!Object} node Wave customer GraphQL node. Expected shape:
 *   { id, name, firstName, lastName, email, phone, mobile, isArchived,
 *     address: { addressLine1, addressLine2, city,
 *       province: { code }, country: { code, name }, postalCode } }
 * @return {!Object} Partial client document fields.
 */
function fromWaveCustomer(node) {
  const n = node || {};
  const addr = (n.address && typeof n.address === "object") ?
    n.address : {};

  // Join addressLine1 and addressLine2 (non-empty only) with ", ".
  const line1 = typeof addr.addressLine1 === "string" ?
    addr.addressLine1.trim() : "";
  const line2 = typeof addr.addressLine2 === "string" ?
    addr.addressLine2.trim() : "";
  const address = [line1, line2].filter(Boolean).join(", ");

  const prov = (addr.province && typeof addr.province === "object") ?
    addr.province : {};
  const province = fromProvinceCode(prov.code);
  const country = fromCountry(
      addr.country && typeof addr.country === "object" ?
        addr.country : null,
  );

  return {
    waveCustomerId: typeof n.id === "string" ? n.id : "",
    name: typeof n.name === "string" ? n.name : "",
    firstName: typeof n.firstName === "string" ? n.firstName : "",
    lastName: typeof n.lastName === "string" ? n.lastName : "",
    email: typeof n.email === "string" ? n.email : "",
    phone: typeof n.phone === "string" ? n.phone : "",
    mobile: typeof n.mobile === "string" ? n.mobile : "",
    address,
    apt: "",
    city: typeof addr.city === "string" ? addr.city.trim() : "",
    province,
    country,
    postalCode: typeof addr.postalCode === "string" ?
      addr.postalCode.trim() : "",
  };
}

module.exports = {toWaveCustomerInput, mappedFieldsHash, fromWaveCustomer};

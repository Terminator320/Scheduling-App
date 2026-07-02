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
 * Extracts the street line (Wave `addressLine1`) from the app's stored
 * `address` display string.
 *
 * App-saved clients store `address` as a full display address
 * ("[apt-]street, city, province postal, country") while Wave keeps
 * city/province/country/postalCode as separate structured fields. Rather than
 * blindly taking the first comma-segment (which destroys street lines that
 * legitimately contain commas, e.g. "100 Main St, Building A"), trailing
 * segments are stripped ONLY when they duplicate the doc's structured
 * locality fields (city / "province postal" / province / postalCode /
 * country, in any trailing order) and the remaining segments — commas and
 * all — form the street line. Docs with NO structured locality fields at all
 * (legacy full-display addresses) fall back to the historical first-segment
 * behaviour so city names never leak into addressLine1.
 *
 * @param {string} fullAddress Trimmed stored address display string.
 * @param {!Object} f The client document fields (for city/province/etc.).
 * @return {string} The street line.
 */
function streetFromAddress(fullAddress, f) {
  if (!fullAddress) return "";
  const segments = fullAddress.split(",")
      .map((s) => s.trim())
      .filter((s) => s.length > 0);
  if (segments.length <= 1) return segments[0] || "";

  const norm = (s) => s.replace(/\s+/g, " ").trim().toLowerCase();
  const city = typeof f.city === "string" ? norm(f.city) : "";
  const province = typeof f.province === "string" ? norm(f.province) : "";
  const postalCode = typeof f.postalCode === "string" ?
    norm(f.postalCode) : "";
  const country = typeof f.country === "string" ? norm(f.country) : "";
  const localityTails = new Set([
    city, province, postalCode, country,
    province && postalCode ? `${province} ${postalCode}` : "",
  ].filter(Boolean));

  // No structured locality fields to identify a tail (legacy docs): keep the
  // historical behaviour (first segment) so a full display address doesn't
  // dump the city into line1.
  if (localityTails.size === 0) return segments[0];

  let end = segments.length;
  while (end > 1 && localityTails.has(norm(segments[end - 1]))) {
    end -= 1;
  }
  return segments.slice(0, end).join(", ");
}

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

  // addressLine1 holds ONLY the street line. The app stores `address` as a
  // full display address ("[apt-]street, city, province postal, country")
  // for its own map/display use, but Wave keeps city/province/country/
  // postalCode as separate structured fields, so the whole string would
  // duplicate them here. streetFromAddress strips the locality tail while
  // preserving commas inside the street itself; for app-saved clients the
  // street already carries the apt prefix, so only prepend `apt` for legacy
  // docs that kept it separate, never doubling it. addressLine2 round-trips
  // through the function-owned `addressLine2` doc field (written by the Wave
  // import, never emitted by the Flutter client's toMap) so a Wave customer's
  // second address line survives an app-side edit → patch cycle.
  const apt = typeof f.apt === "string" ? f.apt.trim() : "";
  const fullAddress = typeof f.address === "string" ? f.address.trim() : "";
  const street = streetFromAddress(fullAddress, f);
  let addressLine1 = street;
  if (apt && !street.startsWith(`${apt}-`)) {
    addressLine1 = street ? `${apt}-${street}` : apt;
  }

  const addr = {};
  if (addressLine1) addr.addressLine1 = addressLine1;
  const addressLine2 = presence(f.addressLine2);
  if (addressLine2) addr.addressLine2 = addressLine2;
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
 * `apt` is always returned as `''`; Wave's `addressLine2` is preserved in the
 * dedicated `addressLine2` doc field (NOT joined into `address`) so the
 * round-trip is lossless: `toWaveCustomerInput` re-emits it as
 * `addressLine2` on patch, and the street line is never truncated at the
 * first comma of a joined string.
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

  // `address` carries ONLY the street line (addressLine1). addressLine2 is
  // kept in its own field so a later write-back can re-emit it faithfully —
  // joining the two with ", " would make the patch path truncate line2 away.
  const line1 = typeof addr.addressLine1 === "string" ?
    addr.addressLine1.trim() : "";
  const line2 = typeof addr.addressLine2 === "string" ?
    addr.addressLine2.trim() : "";
  const address = line1;

  const prov = (addr.province && typeof addr.province === "object") ?
    addr.province : {};
  const province = fromProvinceCode(prov.code);
  const country = fromCountry(
      addr.country && typeof addr.country === "object" ?
        addr.country : null,
  );

  const firstName = typeof n.firstName === "string" ? n.firstName : "";
  const lastName = typeof n.lastName === "string" ? n.lastName : "";
  const email = typeof n.email === "string" ? n.email : "";
  // Derive a non-empty display name: Wave's `name` when present, else the
  // first/last name, else the email. The app lists clients ordered by `name`,
  // so a blank name would float the doc to the top with no label.
  const rawName = typeof n.name === "string" ? n.name.trim() : "";
  const name = rawName ||
    [firstName.trim(), lastName.trim()].filter(Boolean).join(" ") ||
    email.trim();

  return {
    waveCustomerId: typeof n.id === "string" ? n.id : "",
    name,
    firstName,
    lastName,
    email,
    phone: typeof n.phone === "string" ? n.phone : "",
    mobile: typeof n.mobile === "string" ? n.mobile : "",
    address,
    addressLine2: line2,
    apt: "",
    city: typeof addr.city === "string" ? addr.city.trim() : "",
    province,
    country,
    postalCode: typeof addr.postalCode === "string" ?
      addr.postalCode.trim() : "",
  };
}

module.exports = {toWaveCustomerInput, mappedFieldsHash, fromWaveCustomer};

"use strict";

/**
 * @fileoverview Maps between the app's Firestore client doc and Wave's
 * customer GraphQL shapes. Pure and synchronous — no Firebase, network, or
 * I/O — so it stays deterministic and easy to unit test in isolation.
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
 * Per-field length caps applied to everything the IMPORT writes, mirroring
 * `isValidClientData` in `firestore.rules`.
 *
 * `importCustomers` runs under the Admin SDK, which BYPASSES rules — so a Wave
 * customer whose name or address is longer than the app's own cap imports
 * fine and then makes that client permanently un-editable: every in-app save
 * re-emits the whole `toMap()` projection, so the over-cap field fails the
 * rules and takes the address, contacts and billing edits in the same save
 * with it, as an opaque `permission-denied` the admin cannot repair from the
 * form (a seeded controller bypasses `LengthLimitingTextInputFormatter`,
 * which only limits SUBSEQUENT edits).
 *
 * `name` is capped at 200, not at its 225 rules cap. The 225 was sized to the
 * retired "<typed name> <phone>" shape; the cap that matters now is the one
 * the FORM enforces, `TextLimits.personName` (200), since a business's name
 * round-trips through that field on every in-app save (`ClientNamePolicy`).
 * Importing at the rules cap would leave a name the form itself cannot hold.
 *
 * The trade is deliberate and worth stating: a truncated name that is later
 * edited in-app pushes the truncated form BACK to Wave, renaming that
 * customer. That needs a Wave name over 200 characters, and the alternative
 * is a client nobody can edit at all. It only bites a BUSINESS — a person's
 * name is recomposed from their phone number on save and never carries the
 * imported string forward at all.
 * @type {!Object<string, number>}
 */
const IMPORT_FIELD_CAPS = {
  name: 200,
  firstName: 200,
  lastName: 200,
  email: 320,
  phone: 32,
  mobile: 32,
  address: 500,
  city: 128,
  province: 128,
  country: 128,
  postalCode: 32,
};

/**
 * `value` truncated to the cap registered for `field`, if any.
 * @param {string} field Client document field name.
 * @param {string} value Already-trimmed value.
 * @return {string}
 */
function capped(field, value) {
  const max = IMPORT_FIELD_CAPS[field];
  if (typeof max !== "number" || value.length <= max) return value;
  return value.slice(0, max);
}

/**
 * Returns the string only if non-empty after trimming, else undefined. Lets
 * callers omit optional Wave fields that are just empty strings.
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
 * Passes an already-coded value straight through, prefixes a plain 2-letter
 * code with `CA-`, and omits the field entirely when it's empty.
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
 * Converts a stored country value to a Wave `countryCode` (ISO-2). Passes an
 * existing code straight through, maps a known country name, and otherwise
 * omits the field rather than guessing.
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
 * Converts a Wave country object to a stored display name. Prefers
 * `country.name`, falls back to a code→name lookup, and otherwise returns
 * an empty string.
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
 * Extracts the street line (Wave `addressLine1`) from the app's full display
 * `address` string. We strip only the trailing segments that duplicate the
 * doc's structured locality fields, rather than naively splitting on the
 * first comma — a naive split would break a street like
 * "100 Main St, Building A". Legacy docs with no locality fields keep the
 * old first-segment behavior.
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
 * Converts a Firestore client doc's fields to a Wave customer input for
 * `CustomerCreateInput`/`CustomerPatchInput` (the caller still needs to add
 * `businessId`/`id`). Empty optional strings are omitted, and we leave out
 * currency entirely since Wave just defaults to the business currency.
 * `name` and an `address` sub-object are always included.
 * @param {!Object} clientFields Firestore client document fields. Expected
 *   keys: name (required), firstName, lastName, email, phone, mobile,
 *   address, apt, city, province, country, postalCode.
 * @return {!Object} Wave customer input shape (without businessId/id).
 */
function toWaveCustomerInput(clientFields) {
  const f = clientFields || {};

  // addressLine1 holds only the street line — streetFromAddress already
  // stripped the locality tail. We only prepend `apt` for legacy docs where
  // the street doesn't already carry it. addressLine2 round-trips through
  // its own doc field so it survives an edit → patch cycle.
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
 * Computes a stable, key-order-independent SHA-256 hash over the Wave-mapped
 * fields of a client document (unmapped fields like `waveCustomerId` aren't
 * included). Used to detect whether a sync patch would actually be a no-op.
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
 * alphabetically (array order is left alone). That way the result doesn't
 * depend on JS property-insertion order.
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
 * Converts a Wave customer query node to a Firestore client field patch
 * (Wave-owned fields only — the caller merges these in). Defensive against
 * sparse/null sub-objects. `apt` is always `''`, and `addressLine2` stays in
 * its own field so the round-trip through `toWaveCustomerInput` stays lossless.
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

  // `address` carries only the street line. addressLine2 stays in its own
  // field, since joining them with ", " would truncate line2 on a later patch.
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
  // Wave's customer name, mirrored VERBATIM — it is not a display name, and
  // the app never renders a person's (`ClientNamePolicy`). The fallbacks to
  // first/last and then email exist only to avoid storing a blank, which
  // would float the doc to the top of the name-ordered client list. A person
  // whose Wave name is not yet their phone number is recomposed on the next
  // in-app save; the import must not pre-empt that, or it would push a rename
  // to Wave for every customer it read.
  const rawName = typeof n.name === "string" ? n.name.trim() : "";
  const name = rawName ||
    [firstName.trim(), lastName.trim()].filter(Boolean).join(" ") ||
    email.trim();

  // Every mapped field is length-capped on the way in — see IMPORT_FIELD_CAPS.
  return {
    waveCustomerId: typeof n.id === "string" ? n.id : "",
    name: capped("name", name),
    firstName: capped("firstName", firstName),
    lastName: capped("lastName", lastName),
    email: capped("email", email),
    phone: capped("phone", typeof n.phone === "string" ? n.phone : ""),
    mobile: capped("mobile", typeof n.mobile === "string" ? n.mobile : ""),
    address: capped("address", address),
    addressLine2: line2,
    apt: "",
    city: capped("city",
        typeof addr.city === "string" ? addr.city.trim() : ""),
    province: capped("province", province),
    country: capped("country", country),
    postalCode: capped("postalCode",
        typeof addr.postalCode === "string" ? addr.postalCode.trim() : ""),
  };
}

module.exports = {toWaveCustomerInput, mappedFieldsHash, fromWaveCustomer};

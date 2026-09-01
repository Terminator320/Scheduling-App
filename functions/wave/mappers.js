"use strict";

/**
 * @fileoverview Maps between the app's Firestore client doc and Wave's
 * customer GraphQL shapes. Pure and synchronous — no Firebase, network, or
 * I/O — so it stays deterministic and easy to unit test in isolation.
 * @module wave/mappers
 */

const crypto = require("node:crypto");

const {formatNanpNumber, liftPhoneFromName} =
  require("../client_name_utils");
// The street/locality rule has ONE owner, shared with `client_propagation.js`
// and the backfill script — it started here, and moved out when a module that
// must not import from `wave/` needed the same answer.
const {streetFromAddress} = require("../client_address_utils");

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

/**
 * ISO-3166-1 alpha-2, the vocabulary of Wave's `CountryCode` enum.
 *
 * This is a MEMBERSHIP TEST, and it is the difference between one field being
 * dropped and a client never reaching Wave again. `countryCode` is an ENUM, so
 * an unrecognised value is not an `inputErrors` entry the worker can report
 * against the field — GraphQL refuses to coerce the whole `$input` variable
 * and answers with a top-level error, which arrives here as a
 * `WaveApiError(graphql)`. That is non-retryable by design, so the job
 * dead-letters, and no amount of pressing "Retry failed" can ever move it: the
 * same value is sent and rejected the same way.
 *
 * The old test was `/^[A-Z]{2}$/`, which passes any two letters — a `country`
 * of "ON" or "QC" (a province typed into the country box) sailed through as a
 * country code and killed that client's sync permanently, for one stray field
 * on one address.
 */
const ISO_COUNTRY_CODES = new Set((
  "AD AE AF AG AI AL AM AO AQ AR AS AT AU AW AX AZ BA BB BD BE BF BG BH BI " +
  "BJ BL BM BN BO BQ BR BS BT BV BW BY BZ CA CC CD CF CG CH CI CK CL CM CN " +
  "CO CR CU CV CW CX CY CZ DE DJ DK DM DO DZ EC EE EG EH ER ES ET FI FJ FK " +
  "FM FO FR GA GB GD GE GF GG GH GI GL GM GN GP GQ GR GS GT GU GW GY HK HM " +
  "HN HR HT HU ID IE IL IM IN IO IQ IR IS IT JE JM JO JP KE KG KH KI KM KN " +
  "KP KR KW KY KZ LA LB LC LI LK LR LS LT LU LV LY MA MC MD ME MF MG MH MK " +
  "ML MM MN MO MP MQ MR MS MT MU MV MW MX MY MZ NA NC NE NF NG NI NL NO NP " +
  "NR NU NZ OM PA PE PF PG PH PK PL PM PN PR PS PT PW PY QA RE RO RS RU RW " +
  "SA SB SC SD SE SG SH SI SJ SK SL SM SN SO SR SS ST SV SX SY SZ TC TD TF " +
  "TG TH TJ TK TL TM TN TO TR TT TV TW TZ UA UG UM US UY UZ VA VC VE VG VI " +
  "VN VU WF WS YE YT ZA ZM ZW"
).split(" "));

/**
 * ISO-3166-2 subdivisions, by country, for the two countries this integration
 * speaks — the vocabulary of Wave's `ProvinceCode` enum.
 *
 * Same enum-coercion stakes as [ISO_COUNTRY_CODES], plus a second bug the old
 * code had on its own: a plain two-letter province was prefixed `CA-`
 * UNCONDITIONALLY, so a US client in "NY" was sent as `CA-NY` — a code that
 * exists in no country — and dead-lettered forever. The prefix now follows the
 * client's resolved country, and the result has to be a real subdivision of it
 * or the field is dropped.
 */
const SUBDIVISION_CODES = {
  CA: new Set("AB BC MB NB NL NS NT NU ON PE QC SK YT".split(" ")),
  US: new Set((
    "AK AL AR AZ CA CO CT DC DE FL GA HI IA ID IL IN KS KY LA MA MD ME MI " +
    "MN MO MS MT NC ND NE NH NJ NM NV NY OH OK OR PA RI SC SD TN TX UT VA " +
    "VT WA WI WV WY AS GU MP PR UM VI"
  ).split(" ")),
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
 *
 * This is the ONE owner of Wave's field caps. `wave/customer_contract.js`
 * reads it rather than restating the numbers: it applies them on the PUSH
 * direction, where `capped()` below applies them on the IMPORT direction, and
 * a second hand-written copy is how a widened Wave cap gets applied in one
 * place and not the other.
 *
 * It is exported for that caller only.
 * `test/core/validators/text_limits_test.dart` reads this file back as TEXT
 * and asserts every cap clears its
 * firestore.rules cap — Dart, CEL and JS cannot share a constant, so that test
 * is the only thing stopping a tightened rule from letting the import write
 * client docs the app can never update again. It matches the literal below, so
 * exporting the binding does not weaken it.
 * @type {!Object<string, number>}
 */
const IMPORT_FIELD_CAPS = {
  name: 200,
  firstName: 200,
  lastName: 200,
  email: 320,
  // No `mobile` entry: the import folds Wave's mobile into the one `phone`
  // field and always writes `mobile: ""` — see `importedPhone`.
  phone: 32,
  address: 500,
  // 500, matching `address` and NOT the app's 64-char `apt`: Wave models
  // `addressLine2` as a peer street line of `addressLine1`, and
  // `fromWaveCustomer` keeps it in its own field rather than joining it onto
  // `address`. It also
  // round-trips straight back out through `toWaveCustomerInput`, so the tighter
  // cap would push a truncated real address back to Wave (the trade spelled out
  // for `name` above) on a field the app itself never surfaces or repairs.
  addressLine2: 500,
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
 * Converts a stored province value to a Wave `provinceCode` (e.g. `CA-QC`),
 * or omits it when the result would not be a real subdivision.
 *
 * **Omitting is the whole job here.** `provinceCode` is a GraphQL ENUM, so a
 * value outside its vocabulary is not a per-field `inputErrors` entry — it
 * fails variable coercion and Wave answers with a top-level GraphQL error,
 * which the worker classifies non-retryable and dead-letters. One typo in one
 * address field then costs that client every future sync, permanently and
 * silently. A dropped province costs the Wave address one line.
 *
 * The country matters because the prefix does: a plain "NY" is `US-NY` for a
 * US client and nothing at all for a Canadian one. It used to be `CA-` in
 * every case, which is how a US client became the non-existent `CA-NY`.
 *
 * @param {*} province Stored province field.
 * @param {string=} countryCode Resolved ISO-2 country for this client, if
 *   known. Defaults to `CA` — this business's own country, and the only
 *   sensible reading of a bare "QC".
 * @return {string|undefined}
 */
function toProvinceCode(province, countryCode) {
  if (!province || typeof province !== "string") return undefined;
  const p = province.trim().toUpperCase();
  if (!p) return undefined;
  // Already in subdivision-code form (e.g. CA-QC, US-NY) — honoured only if
  // that subdivision actually exists.
  const coded = p.match(/^([A-Z]{2})-([A-Z0-9]{1,3})$/);
  if (coded) {
    const set = SUBDIVISION_CODES[coded[1]];
    return set && set.has(coded[2]) ? p : undefined;
  }
  if (!/^[A-Z]{2}$/.test(p)) return undefined;
  // Plain abbreviation → qualify it with the client's own country.
  const country = SUBDIVISION_CODES[countryCode] ? countryCode : "CA";
  return SUBDIVISION_CODES[country].has(p) ? `${country}-${p}` : undefined;
}

/**
 * Converts a stored country value to a Wave `countryCode` (ISO-2), or omits it
 * when the value is not one.
 *
 * Same enum-coercion stakes as [toProvinceCode]: this doc block always claimed
 * it "omits the field rather than guessing", but the code accepted ANY two
 * letters, so a province typed into the country box ("ON", "QC") became a
 * country code and dead-lettered that client's sync forever.
 *
 * @param {*} country Stored country field.
 * @return {string|undefined}
 */
function toCountryCode(country) {
  if (!country || typeof country !== "string") return undefined;
  const c = country.trim();
  if (!c) return undefined;
  const upper = c.toUpperCase();
  if (ISO_COUNTRY_CODES.has(upper)) return upper;
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
  // Country first: it decides which country's subdivisions a bare "NY" or
  // "QC" is read against.
  const countryCode = toCountryCode(f.country);
  if (countryCode) addr.countryCode = countryCode;
  const provinceCode = toProvinceCode(f.province, countryCode);
  if (provinceCode) addr.provinceCode = provinceCode;
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
 * The single `phone` the APP would hold for this Wave customer.
 *
 * Wave models a customer's number in three places and the app has one field,
 * so mirroring Wave's shape left the number somewhere nothing could dial —
 * neither the detail view's Call button, nor the `clientPhone` denormalized
 * onto every appointment, nor the next push back to Wave. Resolved here
 * exactly the way the app resolves it, in the app's own order of preference:
 *
 * 1. Wave's `phone`.
 * 2. Wave's `mobile` — `mobile` stopped being an editable field (owner change
 *    5), and `EditClientSheet._save` promotes a stored one into `phone` and
 *    clears it on every save. An import that kept writing `mobile` un-healed
 *    that on the next run, since it re-reads the value still sitting in Wave.
 * 3. The customer NAME. This business names a person by their phone number in
 *    Wave (`ClientNamePolicy`), so a customer added there is routinely called
 *    "5145551234" with the phone box left empty — the same shape
 *    `liftPhoneFromName` catches at the keyboard on both client sheets.
 *
 * **Only the phone half of the lift is taken.** `clients/{id}.name` IS Wave's
 * customer name and is mirrored verbatim; rewriting it here would push a
 * rename to Wave on that client's next edit.
 *
 * The result is rendered "(514) 555-1234" when it is a NANP number, which is
 * the shape `PhoneInputFormatter` gives anything typed into the app — Wave
 * holds whatever was typed there, and bare digits were reaching the client
 * detail screen and every appointment card. Anything else (an extension, a
 * genuine foreign number) is stored exactly as Wave has it.
 *
 * Note what this does NOT do: the caller hashes these same resolved fields
 * into `wave.lastSyncedHash`, so a reshaped number does not enqueue a push —
 * Wave keeps its own spelling until that client is next edited in-app.
 *
 * @param {{name: string, phone: *, mobile: *}} fields The resolved stored
 *   name, and Wave's two raw number fields.
 * @return {string} The number to store, possibly empty.
 */
function importedPhone({name, phone, mobile}) {
  const stored = presence(phone) || presence(mobile);
  if (stored) return formatNanpNumber(stored) || stored;

  const lifted = liftPhoneFromName({name, phone: ""});
  return lifted ? lifted.phone : "";
}

/**
 * Converts a Wave customer query node to a Firestore client field patch
 * (Wave-owned fields only — the caller merges these in). Defensive against
 * sparse/null sub-objects. `apt` is always `''`, `mobile` is always `''` (see
 * [importedPhone]), and `addressLine2` stays in its own field so the
 * round-trip through `toWaveCustomerInput` stays lossless.
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
    phone: capped("phone", importedPhone({
      name, phone: n.phone, mobile: n.mobile,
    })),
    // One phone field, like the app's — never a second stranded number.
    mobile: "",
    address: capped("address", address),
    addressLine2: capped("addressLine2", line2),
    apt: "",
    city: capped("city",
        typeof addr.city === "string" ? addr.city.trim() : ""),
    province: capped("province", province),
    country: capped("country", country),
    postalCode: capped("postalCode",
        typeof addr.postalCode === "string" ? addr.postalCode.trim() : ""),
  };
}

module.exports = {
  IMPORT_FIELD_CAPS,
  toWaveCustomerInput,
  mappedFieldsHash,
  fromWaveCustomer,
};

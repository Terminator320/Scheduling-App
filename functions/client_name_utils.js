"use strict";

/**
 * @fileoverview The stored/displayed split for a client's name.
 *
 * `clients/{id}.name` IS THE WAVE CUSTOMER NAME (`toWaveCustomerInput`,
 * `wave/mappers.js`), and as of 2026-08-14 that means two things:
 *
 *   - a PERSON is named by their phone number with the punctuation off,
 *     "5145551234", which is what the invoicing workflow identifies them by
 *     (owner call 2026-08-16; the `phone` FIELD stays formatted);
 *   - a BUSINESS keeps its name, "3101-5696 qc inc.", because that name is the
 *     identity there and a number in its place is unrecognisable.
 *
 * The app never renders a person's: `clientDisplayName` reads the first/last
 * halves or `businessName`, and the `clientName` denormalized onto each
 * appointment is that display form. `propagateClientEdits` therefore has to
 * resolve the display name too, or a client edit would fan the phone number
 * onto every future appointment card.
 *
 * HAND-MIRROR of
 * `lib/features/clients/domain/policies/client_name_policy.dart`.
 * The jest cases here deliberately reuse the Dart tests' worked examples, so a
 * divergence fails a test instead of shipping. Change both together.
 *
 * Pure and synchronous — no Firebase, no I/O.
 * @module client_name_utils
 */

/**
 * A phone-shaped run anchored to the END of the string, with whatever
 * separator was typed in front of it. Deliberately loose — a match is only
 * ever ACTED on when its digits equal the doc's own stored number, so this
 * cannot mistake a street number, a postal code or a year for a phone.
 */
const TRAILING_PHONE = /[\s,;:\-–—·|]*(\+?\d[\d\s().+-]{5,}\d)\s*$/;

/**
 * Separator runs at either end. Leading matters for the Dart side's
 * lift-from-name rule, and the two must trim identically or a name that
 * round-trips through the app stops matching one that round-trips here.
 */
const EDGE_SEPARATORS = /^[\s,;:\-–—·|]+|[\s,;:\-–—·|]+$/g;

/**
 * The number's OWN wrapper, at the seam the lift cut it out of.
 *
 * [PHONE_CANDIDATE] starts and ends on a digit, so a number written the way
 * the app renders it — "(514) 555-1234" — leaves its brackets behind. These
 * are deliberately NOT folded into [EDGE_SEPARATORS]: that set is shared with
 * [stripPhone], where a trailing bracket is usually the name's own
 * ("Depanneur (Nord)"). Only the characters touching the cut are suspect.
 *
 * Mirrors `ClientNamePolicy._openSeam` / `._closeSeam`.
 */
const OPEN_SEAM = /[\s(]+$/;
const CLOSE_SEAM = /^[\s)]+/;

/**
 * The doc's number reduced to comparable digits. A NANP number typed with its
 * leading country code ("1-514-555-1234") is the same number as
 * "(514) 555-1234", so the 11-digit form sheds its leading 1.
 * @param {*} value Any stored phone value.
 * @return {string} Bare digits, possibly empty.
 */
function digitsOf(value) {
  const digits = String(value == null ? "" : value).replace(/\D/g, "");
  if (digits.length === 11 && digits.startsWith("1")) return digits.slice(1);
  return digits;
}

/**
 * A stored number reduced to its bare form — "(514) 555-1234" becomes
 * "5145551234" — keeping a leading "+" so an international number survives.
 *
 * DISTINCT FROM [digitsOf], which additionally sheds the leading 1 of an
 * 11-digit NANP number. That is right for COMPARING two spellings of the same
 * number and wrong for a value that gets stored: it would silently drop a
 * country code the admin typed. Never swap one for the other.
 *
 * Falls back to the trimmed input when there is nothing to strip, so an
 * extension-only or alphabetic entry is handed on rather than blanked.
 *
 * Hand-mirrors `bareNumber` in `lib/core/validators/phone_format.dart`.
 *
 * @param {*} value Any stored phone value.
 * @return {string}
 */
function bareNumber(value) {
  const trimmed = str(value);
  const digits = trimmed.replace(/\D/g, "");
  if (!digits) return trimmed;
  return trimmed.startsWith("+") ? `+${digits}` : digits;
}

/**
 * @param {string} value Text with a possible trailing separator run.
 * @return {string} [value] with trailing separators and whitespace removed.
 */
function trimSeparators(value) {
  return value.replace(EDGE_SEPARATORS, "").trim();
}

/**
 * @param {*} value Any value.
 * @return {string} Trimmed string, or "" for a non-string.
 */
function str(value) {
  return typeof value === "string" ? value.trim() : "";
}

/**
 * [name] with the client's own trailing phone number removed.
 *
 * Returns [name] unchanged when the trailing run is not this client's number —
 * that is what keeps a business genuinely named with digits ("Depanneur 2000")
 * intact. Returns "" when the name is nothing BUT the number; callers decide
 * what to show instead.
 *
 * @param {*} name Stored display name.
 * @param {{phone: (string|undefined), mobile: (string|undefined)}=} opts The
 *   doc's stored numbers.
 * @return {string}
 */
function stripPhone(name, opts) {
  const base = str(name);
  if (!base) return "";
  const phone = str((opts || {}).phone);
  const mobile = str((opts || {}).mobile);

  // Exact suffix first. This is the shape composeStored writes, so an
  // app-written name round-trips losslessly whatever the number looks like —
  // including the international and extension forms the Dart formatter
  // deliberately passes through unmasked.
  for (const candidate of [phone, mobile]) {
    if (!candidate) continue;
    if (base.endsWith(candidate)) {
      return trimSeparators(base.slice(0, base.length - candidate.length));
    }
  }

  // Digit-matched trailing run. Legacy docs were typed with the number in a
  // different shape from the stored one ("Marc Tremblay 514-555-1234" beside a
  // stored "(514) 555-1234"), so an exact suffix misses them.
  const wanted = new Set(
      [phone, mobile].map(digitsOf).filter((d) => d.length > 0));
  if (wanted.size === 0) return base;

  const match = base.match(TRAILING_PHONE);
  if (!match) return base;
  if (!wanted.has(digitsOf(match[1]))) return base;
  return trimSeparators(base.slice(0, match.index));
}

/**
 * Company-name tokens, bounded by non-letters so "Inc." is a business and
 * "Vincent" is not. Matched against an accent-folded, lowercased name.
 *
 * Deliberately short. A false positive only leaves a client named the way it
 * already was; a false NEGATIVE renames a real customer to a phone number on
 * live Wave invoices.
 */
const BUSINESS_TOKEN = new RegExp(
    "(^|[^a-z])(inc|ltd|ltee|llc|llp|enr|senc|sencrl|cie|corp|corporation|" +
    "company|holdings|group|groupe|services|solutions|technology|" +
    "technologies|entreprise|entreprises|immobilier|immeuble|immeubles|" +
    "gestion|construction|condo|condos|syndicat|copropriete|residence|" +
    "residences|habitations|logements|appartements)([^a-z]|$)",
);

/**
 * ANY digit left in the name once the client's own number is off it —
 * "1505 Village de Bergerac", "3101-5696 qc inc.", "Condo 706".
 *
 * Deliberately blunt and biased. A person's name does not contain digits, so
 * the only false positives are a person carrying a SECOND, older number in
 * their name — they simply keep the name they already had, and the backfill
 * reports it. The opposite mistake renames a real company on live invoices.
 */
const ANY_DIGIT = /\d/;

/**
 * Whether [name] reads as an ORGANIZATION on its face.
 *
 * The fallback for docs carrying no `type` — the Wave import sets none, so
 * every imported business would otherwise read as a person and be renamed to
 * its phone number.
 *
 * @param {*} name Any stored name.
 * @return {boolean}
 */
function looksLikeBusinessName(name) {
  const value = str(name);
  if (!value) return false;
  if (ANY_DIGIT.test(value)) return true;
  const folded = value.toLowerCase().replace(/[éèê]/g, "e");
  return BUSINESS_TOKEN.test(folded);
}

/**
 * What gets PERSISTED, and what Wave shows as the CUSTOMER name (owner call
 * 2026-08-14).
 *
 * A PERSON is named by their phone number, BARE — "5145551234", not the
 * "(514) 555-1234" the `phone` field itself stores (owner call 2026-08-16).
 * The invoicing workflow in Wave identifies people by number and wants it
 * unpunctuated; their real name is in `firstName`/`lastName`, which is what
 * `clientDisplayName` renders.
 *
 * `stripPhone` recognises the bare form as this client's own number — it
 * digit-matches, not just suffix-matches — which is what keeps this branch
 * idempotent across the formatting change.
 *
 * A BUSINESS keeps its name: "3101-5696 qc inc.", "1505 Village de Bergerac".
 * That name IS the identity in Wave, and unlike a person there is rarely a
 * first/last to fall back on.
 *
 * Both branches are idempotent. `baseName` is also the answer for a person
 * with no number at all — a blank floats the doc to the top of the
 * name-ordered client list.
 *
 * @param {{baseName: string, phone: (string|undefined),
 *   mobile: (string|undefined), type: (string|undefined),
 *   businessName: (string|undefined)}} opts The clean name, the doc's numbers,
 *   and what is known about whether this client is a business.
 * @return {string}
 */
function composeStored(opts) {
  const o = opts || {};
  const phone = str(o.phone);
  const mobile = str(o.mobile);
  const base = stripPhone(o.baseName, {phone, mobile});

  if (isBusiness({type: o.type, businessName: o.businessName}) ||
      looksLikeBusinessName(base)) {
    return base;
  }

  const number = phone || mobile;
  return number ? bareNumber(number) : base;
}

/**
 * The stored `type` values that mean "organization". Hand-mirrors
 * `ClientType.commercial` / `ClientType.building` — an apartment or condo
 * building is a business with an on-site contact person, which is exactly the
 * shape `clientDisplayName` has to get right.
 */
const BUSINESS_TYPES = new Set(["commercial", "building"]);

/**
 * Whether this client is an ORGANIZATION rather than a person.
 *
 * The legacy `businessName` clause is not belt-and-braces: pre-Wave-reshape
 * business docs predate the `type` field entirely, so they carry no type and
 * would otherwise be read as people. That field is only ever populated on a
 * business.
 *
 * @param {!Object} data Client document fields.
 * @return {boolean}
 */
function isBusiness(data) {
  const d = data || {};
  return BUSINESS_TYPES.has(str(d.type)) || Boolean(str(d.businessName));
}

/**
 * What every in-app surface shows, and what gets denormalized onto an
 * appointment as `clientName`.
 *
 * A BUSINESS shows its business name; a person shows their first/last halves
 * (owner call 2026-08-14). The two branches exist because `firstName`/
 * `lastName` mean different things on the two kinds of client: on a person
 * they ARE the client, on a business they are only its contact person — so
 * preferring them everywhere would render "Vogas Plumbing" as "Marc Tremblay"
 * on the card for a commercial job.
 *
 * For a person the halves win over the stored `name` because `name` is Wave's
 * field: it carries the phone number, and on an imported customer it is
 * whatever Wave had.
 *
 * Every branch ends at the same three fallbacks in a different order, so a
 * client missing the field its own branch prefers still renders something.
 *
 * @param {!Object} data Client document fields.
 * @return {string}
 */
function clientDisplayName(data) {
  const d = data || {};
  const phone = str(d.phone);
  const mobile = str(d.mobile);

  const base = stripPhone(d.name, {phone, mobile});
  const composed = [str(d.firstName), str(d.lastName)]
      .filter(Boolean)
      .join(" ");

  if (isBusiness(d)) {
    if (base) return base;
    const business = stripPhone(d.businessName, {phone, mobile});
    if (business) return business;
    // No company name on file at all — the contact person is better than
    // rendering the phone number.
    if (composed) return composed;
    return str(d.name);
  }

  // No `businessName` leg here, and that is not an omission: `isBusiness` is
  // true for ANY non-empty `businessName`, so on this branch it is provably
  // blank.
  if (composed) return composed;
  if (base) return base;
  // Nothing else to say. The bare number beats an empty string.
  return str(d.name);
}

/**
 * `value` rendered the way the app stores a number — "(514) 555-1234" — or
 * null when it must be left exactly as it is.
 *
 * TWO SHAPES ARE ACCEPTED, and both are the same number:
 *   - ten digits, with no "+";
 *   - ELEVEN digits beginning with 1, with or without a "+". That leading 1 is
 *     the NANP country code (`+1`), so it is dropped and the remaining ten are
 *     formatted. [digitsOf] already treats the two as equal, which is why a
 *     doc in either shape matches its own name.
 *
 * DELIBERATELY NARROWER THAN `formatPhoneNumber`
 * (`lib/core/validators/phone_format.dart`), which this otherwise mirrors.
 * That one masks as the admin TYPES, so it formats progressively and appends
 * digits past the tenth verbatim — reasonable live, wrong for a value being
 * rewritten in bulk or read off a Wave customer. It renders the 11-digit form
 * as "(151) 455-5123 4", reading the country code as part of the area code,
 * and would rewrite a 7-digit or half-entered number into a shape claiming to
 * be complete.
 *
 * Everything else is left exactly as stored, and NULL is how that is said —
 * callers use it as their "nothing to change" test. The "+" bar on the
 * ten-digit case is what keeps a genuine foreign number out: "+49 30 123456"
 * is ten digits and bracketing its first three as an area code would be wrong.
 *
 * @param {*} value Any stored phone value.
 * @return {?string} The formatted number, or null to leave the field as it is.
 */
function formatNanpNumber(value) {
  const raw = String(value == null ? "" : value).trim();
  if (!raw) return null;

  let digits = raw.replace(/\D/g, "");
  if (digits.length === 11 && digits.startsWith("1")) {
    digits = digits.slice(1);
  } else if (digits.length !== 10 || raw.includes("+")) {
    return null;
  }

  const formatted =
    `(${digits.slice(0, 3)}) ${digits.slice(3, 6)}-${digits.slice(6)}`;
  return formatted === raw ? null : formatted;
}

/**
 * A run of digits and the separators a person types between them, ANYWHERE in
 * the string. The `\d` at each end keeps a trailing "(" or "-" out of the
 * match.
 *
 * Only ever acted on when it reduces to a clean 10-digit number — see
 * [matchPhoneInName], which is what makes this loose pattern safe against a
 * street number, a postal code or a year.
 */
const PHONE_CANDIDATE = /\+?\d[\d\s().-]{7,}\d/g;

/**
 * The first run in [text] that is really a phone number, located and rendered.
 * @param {string} text Any name.
 * @return {?{start: number, end: number, formatted: string}}
 */
function matchPhoneInName(text) {
  for (const match of text.matchAll(PHONE_CANDIDATE)) {
    const candidate = match[0];
    // An international number has no fixed shape, so bracketing its first
    // three digits as an area code would be wrong. Leave it in the name.
    if (candidate.includes("+")) continue;
    const digits = digitsOf(candidate);
    if (digits.length !== 10) continue;
    return {
      start: match.index,
      end: match.index + candidate.length,
      formatted: formatNanpNumber(digits),
    };
  }
  return null;
}

/**
 * Moves a phone number sitting in the NAME over into the phone field, and
 * takes it back out of the name.
 *
 * Returns null when there is nothing to do — which is the common case, so
 * callers can use it as their "did anything change" test.
 *
 * Two rules, both carried over from the one-off backfill the Dart side
 * replaced: a stored phone always WINS (an existing number means the name's is
 * a duplicate or a second line, and guessing between them is worse than
 * leaving it), and a name that is NOTHING but the number keeps it — the name
 * is required, so emptying it would look like the number had vanished.
 *
 * HAND-MIRROR of `ClientNamePolicy.liftPhoneFromName`, which is wired to both
 * client sheets' name field. **The Wave import takes only the `phone` half**
 * (`fromWaveCustomer`, `wave/mappers.js`): `clients/{id}.name` IS Wave's
 * customer name, so rewriting it locally would push a rename to Wave on that
 * client's next edit.
 *
 * @param {{name: (string|undefined), phone: (string|undefined)}} opts The name
 *   to read and the phone already on file.
 * @return {?{name: string, phone: string}} The two new values, or null.
 */
function liftPhoneFromName(opts) {
  const o = opts || {};
  const name = typeof o.name === "string" ? o.name : "";
  if (str(o.phone)) return null;
  const match = matchPhoneInName(name);
  if (!match) return null;

  const before = name.slice(0, match.start).replace(OPEN_SEAM, "");
  const after = name.slice(match.end).replace(CLOSE_SEAM, "");
  const remaining = trimSeparators(`${before} ${after}`);
  if (!remaining) return {name, phone: match.formatted};
  return {name: remaining, phone: match.formatted};
}

module.exports = {
  bareNumber,
  clientDisplayName,
  composeStored,
  digitsOf,
  formatNanpNumber,
  isBusiness,
  liftPhoneFromName,
  looksLikeBusinessName,
  stripPhone,
};

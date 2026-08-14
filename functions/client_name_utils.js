"use strict";

/**
 * @fileoverview The stored/displayed split for a client's name.
 *
 * `clients/{id}.name` carries the client's phone number on the END —
 * "Marc Tremblay (514) 555-1234" — because that field is synced VERBATIM to
 * Wave as the customer name (`toWaveCustomerInput`, `wave/mappers.js`), and
 * the invoicing workflow there identifies customers by number.
 *
 * The app never renders that; it strips the number back off for display, and
 * the `clientName` denormalized onto each appointment is the STRIPPED form.
 * `propagateClientEdits` therefore has to strip too, or a client edit would
 * fan the number onto every future appointment card.
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
 * What gets PERSISTED (and what Wave shows): `"<base name> <phone>"`.
 *
 * Stripping first is what makes this idempotent — re-running the backfill, or
 * re-saving a client, never appends a second copy of the number.
 *
 * @param {{baseName: string, phone: (string|undefined),
 *   mobile: (string|undefined)}} opts The clean name plus the doc's numbers.
 * @return {string}
 */
function composeStored(opts) {
  const o = opts || {};
  const phone = str(o.phone);
  const mobile = str(o.mobile);
  const base = stripPhone(o.baseName, {phone, mobile});
  const number = phone || mobile;
  if (!number) return base;
  // A client with no name but a number is still better identified by the
  // number than by a blank, which would float the doc to the top of the
  // name-ordered client list.
  if (!base) return number;
  return `${base} ${number}`;
}

/**
 * The stored `type` values that mean "organization". Hand-mirrors
 * `ClientType.commercial` / `ClientType.propertyManagement` — a
 * property-management company is a business with a contact person, which is
 * exactly the shape `clientDisplayName` has to get right.
 */
const BUSINESS_TYPES = new Set(["commercial", "property_mgmt"]);

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
  const business = stripPhone(d.businessName, {phone, mobile});
  const composed = [str(d.firstName), str(d.lastName)]
      .filter(Boolean)
      .join(" ");

  if (isBusiness(d)) {
    if (base) return base;
    if (business) return business;
    // No company name on file at all — the contact person is better than
    // rendering the phone number.
    if (composed) return composed;
    return str(d.name);
  }

  if (composed) return composed;
  if (base) return base;
  if (business) return business;
  // Nothing else to say. The bare number beats an empty string.
  return str(d.name);
}

module.exports = {
  clientDisplayName,
  composeStored,
  digitsOf,
  isBusiness,
  stripPhone,
};

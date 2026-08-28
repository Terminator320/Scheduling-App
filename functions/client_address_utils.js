"use strict";

/**
 * @fileoverview The street-vs-locality rule for `clients/{id}.address`, and the
 * JS half of a hand-mirrored pair.
 *
 * `city`/`province`/`postalCode`/`country` are their own fields, so an
 * `address` that ALSO carries them stores each one twice and lets the two
 * copies drift. The field is the STREET LINE; everything that shows a whole
 * address composes it back.
 *
 * The collection holds both shapes and always will — the Wave import writes a
 * street line, the app wrote the whole picked string until 2026-08-28, and the
 * console can write either. So `composeFullAddress` reduces through
 * `streetFromAddress` BEFORE it rejoins: skip that and a legacy doc renders its
 * city twice.
 *
 * Hand-mirrors `AddressParser.streetOnly` / `composeFull`
 * (`lib/features/maps/domain/address_parser.dart`). Their tests share worked
 * examples, so a divergence fails a test on one side.
 *
 * `streetFromAddress` lived in `wave/mappers.js`, which is where the rule was
 * first needed — the Wave push has always had to reduce `address` down to an
 * `addressLine1`. It moved here when `client_propagation.js` needed the same
 * rule: a propagation module must not import from `wave/`, and a second copy
 * of a rule this sharp is how the two answers drift apart.
 *
 * @module client_address_utils
 */

/**
 * Collapses inner whitespace and case so two spellings of the same locality
 * compare equal.
 * @param {*} value Any value; non-strings read as empty.
 * @return {string}
 */
function localityKey(value) {
  if (typeof value !== "string") return "";
  return value.replace(/\s+/g, " ").trim().toLowerCase();
}

/**
 * The street line alone — [stored] with any trailing segments that merely
 * repeat the doc's structured locality fields removed.
 *
 * Strips from the TAIL rather than splitting on the first comma, so a street
 * like "100 Main St, Building A" keeps its second segment. With no locality
 * fields to identify a tail (a legacy doc predating them) it falls back to the
 * first segment rather than guessing, and it never strips the last remaining
 * one — a street that IS the city name must not reduce to nothing.
 *
 * IDEMPOTENT: an already-reduced street passes through untouched. That is what
 * makes it safe to run on a collection holding both shapes, and what makes the
 * backfill re-runnable.
 *
 * @param {string} stored Stored `address` value.
 * @param {!Object} f The client document fields (for city/province/etc.).
 * @return {string} The street line.
 */
function streetFromAddress(stored, f) {
  if (!stored) return "";
  const segments = String(stored).split(",")
      .map((s) => s.trim())
      .filter((s) => s.length > 0);
  if (segments.length <= 1) return segments[0] || "";

  const d = f || {};
  const city = localityKey(d.city);
  const province = localityKey(d.province);
  const postalCode = localityKey(d.postalCode);
  const country = localityKey(d.country);
  const localityTails = new Set([
    city, province, postalCode, country,
    province && postalCode ? `${province} ${postalCode}` : "",
  ].filter(Boolean));

  // No structured locality fields to identify a tail (legacy docs): keep the
  // historical behaviour (first segment) so a full display address doesn't
  // dump the city into line1.
  if (localityTails.size === 0) return segments[0];

  let end = segments.length;
  while (end > 1 && localityTails.has(localityKey(segments[end - 1]))) {
    end -= 1;
  }
  return segments.slice(0, end).join(", ");
}

/**
 * The whole address on one line, rebuilt from the street plus the structured
 * fields — "1234 Rue Principale, Montréal, QC H2X 1Y4, Canada".
 *
 * Reducing through [streetFromAddress] first is the load-bearing half: it is
 * what makes this answer the same string for both stored shapes, and therefore
 * what makes normalizing the field a NO-OP everywhere this is compared.
 *
 * Unlike the Dart twin this does NOT re-render the apt as "#4" — the server
 * has no display concern and must not rewrite a stored appointment address
 * into a different spelling of itself.
 *
 * @param {!Object} f The client document fields.
 * @return {string} The composed address, or "" when there is nothing to show.
 */
function composeFullAddress(f) {
  const d = f || {};
  const stored = typeof d.address === "string" ? d.address.trim() : "";
  const street = streetFromAddress(stored, d);
  const text = (value) => (typeof value === "string" ? value.trim() : "");
  // Province and postal code share a segment, the way an address is written.
  const region = [text(d.province), text(d.postalCode)]
      .filter(Boolean).join(" ");
  return [street, text(d.city), region, text(d.country)]
      .filter(Boolean).join(", ");
}

module.exports = {
  streetFromAddress,
  composeFullAddress,
};

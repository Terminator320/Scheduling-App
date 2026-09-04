"use strict";

const TOKEN_QUERY_LIMIT = 10;
const TOKEN_FIELD_LIMIT = 240;

/**
 * Normalizes text for prefix search.
 * @param {*} value Raw value.
 * @return {string}
 */
function normalize(value) {
  return String(value == null ? "" : value)
      .normalize("NFD")
      .replace(/[\u0300-\u036f]/g, "")
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, " ")
      .trim();
}

/**
 * Keeps only phone digits.
 * @param {*} value Raw phone-ish value.
 * @return {string}
 */
function digitsOnly(value) {
  return String(value == null ? "" : value).replace(/\D/g, "");
}

/**
 * Builds capped query tokens for array-contains-any.
 * @param {string} query User query.
 * @return {!Array<string>}
 */
function searchQueryTokens(query) {
  const tokens = new Set();
  for (const word of normalize(query).split(" ")) {
    if (word) tokens.add(`t:${word}`);
  }
  const digits = digitsOnly(query);
  if (digits) tokens.add(`p:${digits}`);
  return Array.from(tokens).slice(0, TOKEN_QUERY_LIMIT);
}

/**
 * Builds capped prefix/substr tokens for one stored document.
 * @param {!Object} input Token inputs.
 * @param {!Array<*>} input.texts Text fields.
 * @param {!Array<*>} input.phones Phone fields.
 * @return {!Array<string>}
 */
function searchIndexTokens({texts = [], phones = []}) {
  const tokens = new Set();
  for (const value of texts) {
    for (const word of normalize(value).split(" ")) {
      if (!word) continue;
      const max = Math.min(word.length, 24);
      for (let i = 1; i <= max; i++) {
        tokens.add(`t:${word.slice(0, i)}`);
      }
    }
  }
  for (const phone of phones) {
    const digits = digitsOnly(phone);
    if (!digits) continue;
    for (let start = 0; start < digits.length; start++) {
      const remaining = digits.length - start;
      if (remaining < 3) break;
      const max = Math.min(remaining, 12);
      for (let len = 3; len <= max; len++) {
        tokens.add(`p:${digits.slice(start, start + len)}`);
      }
    }
  }
  return Array.from(tokens).slice(0, TOKEN_FIELD_LIMIT);
}

/**
 * Tokenizes one client document.
 * @param {!Object} data Client fields.
 * @return {!Array<string>}
 */
function clientSearchTokens(data) {
  const d = data || {};
  const contacts = Array.isArray(d.contacts) ? d.contacts : [];
  const contactText = (c) => {
    const contact = c || {};
    return `${contact.name || ""} ${contact.email || ""}`;
  };
  return searchIndexTokens({
    texts: [
      d.name,
      d.businessName,
      d.firstName,
      d.lastName,
      d.email,
      d.address,
      d.city,
      d.province,
      d.postalCode,
      d.country,
      ...contacts.map(contactText),
    ],
    phones: [
      d.phone,
      d.mobile,
      ...contacts.map((c) => c && c.phone),
    ],
  });
}

/**
 * Tokenizes one appointment document into all/employee history scopes.
 * @param {!Object} data Appointment fields.
 * @return {!Array<string>}
 */
function appointmentHistoryScopes(data) {
  const d = data || {};
  const employeeIds = Array.isArray(d.employeeIds) ? d.employeeIds : [];
  const employeeNames = Array.isArray(d.employeeNames) ? d.employeeNames : [];
  const scopeCount = 1 + employeeIds.length;
  const perScopeLimit = Math.max(
      1,
      Math.min(TOKEN_QUERY_LIMIT, Math.floor(TOKEN_FIELD_LIMIT / scopeCount)),
  );
  const tokens = searchIndexTokens({
    texts: [d.clientName, ...employeeNames],
    phones: [d.clientPhone],
  }).slice(0, perScopeLimit);
  const scoped = [];
  for (const token of tokens) scoped.push(`all:${token}`);
  for (const employeeId of employeeIds) {
    for (const token of tokens) scoped.push(`emp:${employeeId}:${token}`);
  }
  return scoped.slice(0, TOKEN_FIELD_LIMIT);
}

/**
 * Verifies a token query still matches the full document text or digits.
 * @param {!Object} data Stored document.
 * @param {string} query User query.
 * @return {boolean}
 */
function recordMatchesQuery(data, query) {
  const q = normalize(query);
  const qDigits = digitsOnly(query);
  const d = data || {};
  const contacts = Array.isArray(d.contacts) ? d.contacts : [];
  const contactText = (c) => {
    const contact = c || {};
    return `${contact.name || ""} ${contact.email || ""}`;
  };
  const text = normalize([
    d.name,
    d.businessName,
    d.firstName,
    d.lastName,
    d.email,
    d.address,
    d.city,
    d.province,
    d.postalCode,
    d.country,
    d.clientName,
    ...(Array.isArray(d.employeeNames) ? d.employeeNames : []),
    ...contacts.map(contactText),
  ].join(" "));
  const digits = digitsOnly([
    d.phone,
    d.mobile,
    d.clientPhone,
    ...contacts.map((c) => c && c.phone),
  ].join(" "));
  return Boolean((q && text.includes(q)) ||
      (qDigits && digits.includes(qDigits)));
}

module.exports = {
  TOKEN_FIELD_LIMIT,
  TOKEN_QUERY_LIMIT,
  appointmentHistoryScopes,
  clientSearchTokens,
  digitsOnly,
  normalize,
  recordMatchesQuery,
  searchIndexTokens,
  searchQueryTokens,
};

"use strict";

/**
 * @fileoverview Neutral Wave customer infrastructure shared by both halves of
 * customer sync — the connected business id and the two customer-listing
 * GraphQL documents. A leaf module on purpose: it requires neither
 * `./customers` (App → Wave push) nor `./customers_import` (Wave → App pull),
 * so both can require it at module scope without closing a cycle.
 * @module wave/customer_queries
 */

/**
 * Reads the connected Wave `businessId` from the `wave/connection` doc.
 * @param {!Object} db Firestore instance.
 * @return {!Promise<string>} The business id.
 * @throws {Error} When the connection doc or its businessId is missing.
 */
async function readBusinessId(db) {
  const snap = await db.collection("wave").doc("connection").get();
  const data = snap && snap.exists ? snap.data() : null;
  const id = data && typeof data.businessId === "string" ? data.businessId : "";
  if (!id) {
    throw new Error("wave/connection businessId is missing — not connected.");
  }
  return id;
}

// One owner for the listing's page + node selection, so the full and delta
// documents below can't drift on what they read back.
const LIST_CUSTOMERS_BODY = `
      pageInfo { currentPage totalPages totalCount }
      edges {
        node {
          id
          name
          firstName
          lastName
          email
          phone
          mobile
          isArchived
          address {
            addressLine1
            addressLine2
            city
            province { code }
            country { code name }
            postalCode
          }
        }
      }`;

const LIST_CUSTOMERS = `
query ListCustomers($id: ID!, $page: Int!, $pageSize: Int!) {
  business(id: $id) {
    customers(page: $page, pageSize: $pageSize, sort: [NAME_ASC]) {${
  LIST_CUSTOMERS_BODY}
    }
  }
}`;

// Delta listing. `modifiedAtAfter` filters SERVER-SIDE, so Wave returns only
// what changed — strictly better than paging everything and stopping early.
// Confirmed against the live schema 2026-08-04 (see
// scripts/wave-introspect-customer-sort.js).
//
// This is a SEPARATE document rather than one query with a nullable `$since`:
// omitting a variable to make an argument "not present" is real GraphQL, but
// it is subtle third-party behaviour, and a server that instead read it as
// `modifiedAtAfter: null` would silently return nothing — a full import that
// imports zero customers and reports success. Two documents make that
// unrepresentable.
//
// Sort stays NAME_ASC: we page the entire filtered set either way, so
// MODIFIED_AT_ASC would buy nothing and gives the two documents a second
// difference to keep in step.
const LIST_CUSTOMERS_SINCE = `
query ListCustomersSince(
  $id: ID!, $page: Int!, $pageSize: Int!, $since: DateTime!
) {
  business(id: $id) {
    customers(
      page: $page, pageSize: $pageSize, sort: [NAME_ASC]
      modifiedAtAfter: $since
    ) {${LIST_CUSTOMERS_BODY}
    }
  }
}`;

module.exports = {
  readBusinessId,
  LIST_CUSTOMERS,
  LIST_CUSTOMERS_SINCE,
};

#!/usr/bin/env node
// Read-only: asks Wave's GraphQL schema what the `customers` connection can
// sort and filter by.
//
// WHY this exists: the import is O(all customers) — it pages every customer
// on every run, because `LIST_CUSTOMERS` sorts by NAME_ASC and there is no
// way to ask "what changed". If `CustomerSort` exposes a MODIFIED_AT_* value,
// the import can sort newest-modified-first and stop at a stored watermark,
// turning ~7 pages into ~1 and making the run O(changes).
//
// Public sources confirm `InvoiceSort` has MODIFIED_AT_DESC and that
// `CustomerSort` has NAME_ASC, but none of them enumerate CustomerSort — so
// this asks the server rather than guessing. Cheap: one introspection query,
// no mutations, nothing written anywhere.
//
// Usage (PowerShell):
//   $env:WAVE_FULL_ACCESS_TOKEN = (gcloud secrets versions access latest `
//     --secret=WAVE_FULL_ACCESS_TOKEN --project=schedulingapp-88727)
//   node functions/scripts/wave-introspect-customer-sort.js
//   Remove-Item Env:\WAVE_FULL_ACCESS_TOKEN
//
// The token is a full-access Wave credential. It is read from the env, sent
// in one Authorization header, and never logged, echoed, written to disk, or
// interpolated into an error message — the HTTP failure path deliberately
// prints the status code only, since a Wave error body can quote the request.
// `scripts/**` is in firebase.json's deploy ignore, so this file never reaches
// Cloud Functions. Clear the variable when you're done (the value never enters
// shell history — it's the output of gcloud, not something you type).

"use strict";

// Mirrors WAVE_GQL_URL in wave/client.js. Not imported from there on purpose:
// that module resolves the token through a `defineSecret` param, which only
// binds inside a deployed function.
const ENDPOINT = "https://gql.waveapps.com/graphql/public";

// A one-off CLI with no timeout hangs forever on a stalled connection.
const REQUEST_TIMEOUT_MS = 30_000;

const QUERY = `
{
  sortEnum: __type(name: "CustomerSort") {
    enumValues { name }
  }
  customersField: __type(name: "Business") {
    fields(includeDeprecated: true) {
      name
      args { name type { name kind ofType { name kind } } }
    }
  }
}`;

/**
 * Runs the introspection query and prints what the customers connection
 * supports.
 * @return {!Promise<void>}
 */
async function main() {
  const token = process.env.WAVE_FULL_ACCESS_TOKEN;
  if (!token) {
    console.error(
        "WAVE_FULL_ACCESS_TOKEN is not set — see the usage note at the top.");
    process.exitCode = 1;
    return;
  }

  const res = await fetch(ENDPOINT, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Authorization": `Bearer ${token}`,
    },
    body: JSON.stringify({query: QUERY}),
    signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
  });

  if (!res.ok) {
    // Status only — a Wave error body can echo the request.
    console.error(`Wave returned HTTP ${res.status}`);
    process.exitCode = 1;
    return;
  }

  const body = await res.json();
  if (body.errors) {
    console.error("GraphQL errors:",
        body.errors.map((e) => e.message).join("; "));
    process.exitCode = 1;
    return;
  }

  const data = body.data || {};

  // A missing type and a type with no MODIFIED_AT_* value are NOT the same
  // answer, and the whole point of this script is to replace a guess with a
  // fact. Reporting "no delta sort" because introspection was disabled, or
  // because the enum is spelled differently, would hand back a confident
  // wrong answer — exactly the failure this was written to avoid.
  if (!data.sortEnum) {
    console.error(
        "\nCustomerSort not found. Either Wave has introspection disabled on " +
        "this endpoint, or the enum is named something else — INCONCLUSIVE, " +
        "not a 'no'. Check the Wave API Explorer by hand before deciding.");
    process.exitCode = 1;
    return;
  }

  const sortValues = (data.sortEnum.enumValues || []).map((v) => v.name);
  console.log("\nCustomerSort values:");
  for (const v of sortValues) console.log(`  ${v}`);

  const modified = sortValues.filter((v) => v.startsWith("MODIFIED_AT"));
  console.log(modified.length ?
    `\n=> Delta import IS possible: ${modified.join(", ")}` :
    "\n=> CustomerSort exists and has no MODIFIED_AT_* value, so a delta " +
      "import needs a different angle (see docs/CLOUD_FUNCTIONS.md).");

  const fields = (data.customersField || {}).fields;
  const customers = Array.isArray(fields) ?
    fields.find((f) => f.name === "customers") : null;
  if (!customers) {
    console.log("\n`business.customers` arguments: could not read them (the " +
      "Business type or its customers field was not returned).");
    return;
  }
  console.log("\n`business.customers` arguments:");
  for (const a of (customers.args || [])) {
    const t = a.type || {};
    console.log(`  ${a.name}: ${t.name || (t.ofType || {}).name || t.kind}`);
  }
  console.log("");
}

main().catch((e) => {
  console.error("Introspection failed:", e && e.message ? e.message : e);
  process.exitCode = 1;
});

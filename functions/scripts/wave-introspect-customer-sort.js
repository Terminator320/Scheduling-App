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

// Cheapest authenticated query Wave offers. Run FIRST so a bad token and a
// blocked introspection can't be confused — they produce the same HTTP status,
// and guessing between them is how you end up "fixing" the wrong one.
const PROBE_QUERY = "{ user { id } }";

// NOTE: Wave rejects inline String arguments outright —
// `GRAPHQL_VALIDATION_FAILED: Inline argument of type String is not allowed.
// Provide data using GraphQL variables.` So `__type(name: "CustomerSort")` is
// a 400, and the two type names have to travel as variables. (Inline Boolean
// is accepted — `includeDeprecated: true` below is not flagged.) Every query
// in wave/customers.js already parameterises its strings, which is why this
// only ever bit the one query written by hand outside that module.
const QUERY = `
query IntrospectCustomerSort($sortName: String!, $businessType: String!) {
  sortEnum: __type(name: $sortName) {
    enumValues { name }
  }
  customersField: __type(name: $businessType) {
    fields(includeDeprecated: true) {
      name
      args { name type { name kind ofType { name kind } } }
    }
  }
}`;

const QUERY_VARS = {sortName: "CustomerSort", businessType: "Business"};

// Opt-in body dump. Off by default because a Wave error body can quote the
// request; safe to pass here because this script sends no variables and never
// leaves a dev machine (scripts/** is deploy-ignored).
const VERBOSE = process.argv.includes("--verbose");

/**
 * POSTs a GraphQL query to Wave.
 * @param {string} token Wave full-access token.
 * @param {string} query GraphQL document.
 * @param {Object=} variables Query variables — Wave REQUIRES these for any
 *   String argument (see the note on QUERY).
 * @return {!Promise<{ok: boolean, status: number, body: *}>}
 */
async function post(token, query, variables) {
  const res = await fetch(ENDPOINT, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Authorization": `Bearer ${token}`,
    },
    body: JSON.stringify(variables ? {query, variables} : {query}),
    signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
  });
  const text = await res.text();
  let body = null;
  try {
    body = JSON.parse(text);
  } catch (_) {
    body = text;
  }
  return {ok: res.ok, status: res.status, body, raw: text};
}

/**
 * Prints a failure, with the response body only under --verbose.
 * @param {string} label What was being attempted.
 * @param {{status: number, raw: string}} res The failed response.
 * @return {void}
 */
function reportFailure(label, res) {
  console.error(`\n${label}: Wave returned HTTP ${res.status}`);
  if (VERBOSE) {
    console.error("--- response body (--verbose) ---");
    console.error(res.raw.slice(0, 2000));
  } else {
    console.error("Re-run with --verbose to see Wave's response body.");
  }
}

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
  console.log(`Token length: ${token.length} chars (value not printed).`);

  // --- Step 1: is the token good at all? --------------------------------
  const probe = await post(token, PROBE_QUERY);
  if (!probe.ok || (probe.body && probe.body.errors)) {
    reportFailure("Auth probe failed", probe);
    if (probe.body && probe.body.errors) {
      console.error(probe.body.errors.map((e) => e.message).join("; "));
    }
    console.error(
        "\n=> The TOKEN is the problem, not introspection. Check that the " +
        "value captured from Secret Manager is the whole token (a Wave " +
        "full-access token is much longer than 30 characters).");
    process.exitCode = 1;
    return;
  }
  console.log("Auth probe OK — the token works.\n");

  // --- Step 2: introspection -------------------------------------------
  const res = await post(token, QUERY, QUERY_VARS);
  if (!res.ok) {
    reportFailure("Introspection", res);
    // Don't guess at the cause — an earlier version of this message asserted
    // "Wave blocks introspection" for a 400 that was actually a malformed
    // query of our own (inline String arguments), which is the same
    // confident-wrong-answer failure this script exists to avoid.
    const codes = ((res.body || {}).errors || [])
        .map((e) => (e.extensions || {}).code).filter(Boolean);
    console.error(codes.includes("GRAPHQL_VALIDATION_FAILED") ?
      "\n=> Wave rejected the QUERY, not the request. This is a bug in this " +
        "script, not an answer about Wave's schema — fix the query above." :
      "\n=> The token works but this call did not. INCONCLUSIVE, not a " +
        "'no': check the Wave API Explorer before deciding a delta import " +
        "is off the table.");
    process.exitCode = 1;
    return;
  }

  const body = res.body || {};
  if (body.errors) {
    console.error("GraphQL errors:",
        body.errors.map((e) => e.message).join("; "));
    console.error(
        "\n=> INCONCLUSIVE — introspection may be disabled, or the type " +
        "names differ. Do not read this as 'no delta sort'.");
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

"use strict";

/**
 * The two predicates behind the stale-link recovery (prod 2026-08-15).
 *
 * A `waveCustomerId` pointing at a customer deleted in Wave is a STORED bad
 * value: every retry re-sends it, so the outbox job dead-letters forever and
 * "Retry failed" is guaranteed to fail. `upsertCustomer` recovers by dropping
 * the link and re-creating, which means these two predicates are the gate on
 * REWRITING a client's Wave identity.
 *
 * That cuts both ways and is why both directions are asserted below: too loose
 * and an ordinary transport hiccup unlinks a correctly-linked customer and
 * creates a duplicate in Wave; too tight and the job never drains. Wave can
 * report the same fact in either of two shapes, so there is one predicate per
 * shape and neither may be tightened without the other.
 */

const {
  isStaleCustomerLink,
  hasNotFoundInputError,
} = require("../wave/customers");
const {WaveApiError} = require("../wave/client");

/**
 * A top-level GraphQL error carrying an extensions code.
 * @param {string} code The `extensions.code` value.
 * @return {!WaveApiError}
 */
function graphqlErrorWithCode(code) {
  return new WaveApiError("graphql", "Wave rejected the request", [
    {message: "not found", path: ["customerPatch"], extensions: {code}},
  ]);
}

describe("isStaleCustomerLink", () => {
  test("true for a graphql WaveApiError carrying NOT_FOUND", () => {
    // The exact prod shape: `codes=[NOT_FOUND] fields=[customerPatch]`.
    expect(isStaleCustomerLink(graphqlErrorWithCode("NOT_FOUND"))).toBe(true);
  });

  test("true when NOT_FOUND is one detail among several", () => {
    const err = new WaveApiError("graphql", "mixed", [
      {message: "a", extensions: {code: "INTERNAL_SERVER_ERROR"}},
      {message: "b", extensions: {code: "NOT_FOUND"}},
    ]);
    expect(isStaleCustomerLink(err)).toBe(true);
  });

  test("false for any other extensions code", () => {
    // Unlinking is destructive to the client's Wave identity — only the one
    // code that can ONLY mean "the customer is gone" may trigger it.
    for (const code of ["INTERNAL_SERVER_ERROR", "UNAUTHENTICATED",
      "BAD_USER_INPUT", "NOT_FOUND_SOMETHING", ""]) {
      expect(isStaleCustomerLink(graphqlErrorWithCode(code))).toBe(false);
    }
  });

  test("false for a non-graphql WaveApiError kind", () => {
    // A transport/rate-limit failure is RETRYABLE. Unlinking on one would
    // orphan a correctly-linked customer and create a duplicate in Wave on
    // the next push.
    for (const kind of ["network", "http", "rate_limit", "auth", "timeout"]) {
      const err = new WaveApiError(kind, "boom", [
        {extensions: {code: "NOT_FOUND"}},
      ]);
      expect(isStaleCustomerLink(err)).toBe(false);
    }
  });

  test("false for anything that is not a WaveApiError", () => {
    // Deliberately an instanceof check, not duck typing: a plain object with
    // the right fields is not evidence Wave said the customer is gone.
    expect(isStaleCustomerLink(null)).toBe(false);
    expect(isStaleCustomerLink(undefined)).toBe(false);
    expect(isStaleCustomerLink(new Error("nope"))).toBe(false);
    expect(isStaleCustomerLink({
      kind: "graphql",
      details: [{extensions: {code: "NOT_FOUND"}}],
    })).toBe(false);
  });

  test("false when details are missing or malformed", () => {
    expect(isStaleCustomerLink(new WaveApiError("graphql", "x"))).toBe(false);
    expect(isStaleCustomerLink(new WaveApiError("graphql", "x", "nope")))
        .toBe(false);
    expect(isStaleCustomerLink(new WaveApiError("graphql", "x", [null])))
        .toBe(false);
    expect(isStaleCustomerLink(new WaveApiError("graphql", "x", [{}])))
        .toBe(false);
  });

  test("never matches on Wave's message text", () => {
    // The predicate is structural on purpose. A text match would unlink a
    // client on the strength of Wave rewording an unrelated error.
    const err = new WaveApiError(
        "graphql", "NOT_FOUND: customer not found", [
          {message: "NOT_FOUND", extensions: {code: "INTERNAL_SERVER_ERROR"}},
        ]);
    expect(isStaleCustomerLink(err)).toBe(false);
  });
});

describe("hasNotFoundInputError", () => {
  test("true for a NOT_FOUND input error", () => {
    // The OTHER shape Wave can report the same fact in: a
    // `didSucceed: false` payload rather than a thrown top-level error.
    // Missing this one leaves the job dead-lettering forever just the same.
    expect(hasNotFoundInputError([{code: "NOT_FOUND", message: "gone"}]))
        .toBe(true);
  });

  test("true when NOT_FOUND is one entry among several", () => {
    expect(hasNotFoundInputError([
      {code: "TOO_LONG"},
      {code: "NOT_FOUND"},
    ])).toBe(true);
  });

  test("false for the other mapped codes", () => {
    for (const code of ["GENERIC_ERROR", "MISSING_REQUIRED", "TOO_LONG",
      "TOO_SHORT", "INVALID_EMAIL", "INVALID_PHONE"]) {
      expect(hasNotFoundInputError([{code}])).toBe(false);
    }
  });

  test("false for an empty, absent or malformed array", () => {
    expect(hasNotFoundInputError([])).toBe(false);
    expect(hasNotFoundInputError(null)).toBe(false);
    expect(hasNotFoundInputError(undefined)).toBe(false);
    expect(hasNotFoundInputError("NOT_FOUND")).toBe(false);
    expect(hasNotFoundInputError([null, {}, {message: "NOT_FOUND"}]))
        .toBe(false);
  });

  test("matches on code only, never on the message", () => {
    expect(hasNotFoundInputError([
      {code: "GENERIC_ERROR", message: "NOT_FOUND"},
    ])).toBe(false);
  });
});

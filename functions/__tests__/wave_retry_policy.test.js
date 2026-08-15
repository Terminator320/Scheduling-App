"use strict";

/**
 * Direct tests for the Wave outbox retry taxonomy.
 *
 * These decisions are what stand between a transient Wave hiccup and a client
 * edit dead-lettered forever — a `dead` job never retries, and it surfaces only
 * as an error badge on the client doc plus `pushedFailed` if an admin happens
 * to press Sync. Until `retry_policy.js` was split out they were reachable only
 * through `wave_worker.test.js`'s Firestore-mock harness, which exercises them
 * incidentally, a couple of paths at a time. This file drives them directly.
 */

const {
  DEFAULT_MAX_ATTEMPTS,
  RATE_LIMITED_MAX_ATTEMPTS,
  BASE_BACKOFF_MS,
  MAX_BACKOFF_MS,
  defaultBackoffMs,
  isTransientGraphqlError,
  isRetryable,
  attemptBudgetFor,
  sanitizeError,
} = require("../wave/retry_policy");
const {WaveApiError} = require("../wave/client");
const {WaveValidationError} = require("../wave/customers");

/**
 * A `graphql`-kind WaveApiError carrying the given error array.
 * @param {string} message Top-level message.
 * @param {Array<Object>=} details Wave's `errors` array.
 * @return {!WaveApiError}
 */
function graphqlError(message, details) {
  return new WaveApiError("graphql", message, details);
}

describe("budget constants", () => {
  it("gives a rate-limited job a budget that outlasts a bulk backfill", () => {
    // A backfill enqueues a few hundred jobs, each pushed by its own trigger
    // invocation; 5 attempts against Wave's 60/min ceiling would dead-letter
    // perfectly valid edits.
    expect(RATE_LIMITED_MAX_ATTEMPTS).toBeGreaterThan(DEFAULT_MAX_ATTEMPTS);
  });

  it("keeps the rate-limited budget bounded rather than infinite", () => {
    expect(Number.isFinite(RATE_LIMITED_MAX_ATTEMPTS)).toBe(true);
    // At the MAX_BACKOFF_MS ceiling this is on the order of half a day of
    // retrying before we admit something is structurally wrong.
    expect(RATE_LIMITED_MAX_ATTEMPTS * MAX_BACKOFF_MS)
        .toBeLessThanOrEqual(24 * 60 * 60 * 1000);
  });
});

describe("defaultBackoffMs", () => {
  afterEach(() => {
    if (Math.random.mockRestore) Math.random.mockRestore();
  });

  it("starts at the base delay, jittered down by at most 25%", () => {
    jest.spyOn(Math, "random").mockReturnValue(0);
    expect(defaultBackoffMs(0)).toBe(Math.floor(BASE_BACKOFF_MS * 0.75));
    Math.random.mockReturnValue(0.999999);
    expect(defaultBackoffMs(0)).toBeLessThanOrEqual(BASE_BACKOFF_MS);
    expect(defaultBackoffMs(0)).toBeGreaterThan(BASE_BACKOFF_MS * 0.99);
  });

  it("doubles per attempt", () => {
    jest.spyOn(Math, "random").mockReturnValue(0);
    expect(defaultBackoffMs(1)).toBe(Math.floor(BASE_BACKOFF_MS * 2 * 0.75));
    expect(defaultBackoffMs(2)).toBe(Math.floor(BASE_BACKOFF_MS * 4 * 0.75));
    expect(defaultBackoffMs(3)).toBe(Math.floor(BASE_BACKOFF_MS * 8 * 0.75));
  });

  it("caps at MAX_BACKOFF_MS, so a long retry chain cannot run away", () => {
    jest.spyOn(Math, "random").mockReturnValue(0);
    // 2^20 * 60s is ~2 years uncapped; the cap is what keeps
    // RATE_LIMITED_MAX_ATTEMPTS to about half a day.
    expect(defaultBackoffMs(20)).toBe(Math.floor(MAX_BACKOFF_MS * 0.75));
    expect(defaultBackoffMs(200)).toBe(Math.floor(MAX_BACKOFF_MS * 0.75));
  });

  it("never returns a negative or fractional delay", () => {
    for (let attempts = 0; attempts < 12; attempts++) {
      const delay = defaultBackoffMs(attempts);
      expect(Number.isInteger(delay)).toBe(true);
      expect(delay).toBeGreaterThan(0);
      expect(delay).toBeLessThanOrEqual(MAX_BACKOFF_MS);
    }
  });
});

describe("isTransientGraphqlError", () => {
  // Wave reports genuinely transient server-side failures as GraphQL errors on
  // an HTTP 200, so this heuristic is the only thing separating "Wave blipped"
  // from "this payload will never be accepted".
  const transientMessages = [
    "Internal server error",
    "Request TIMEOUT while contacting upstream",
    "the request timed out",
    "Service Unavailable",
    "temporarily unable to process",
    "Server overloaded, back off",
    "service error",
    "Please try again later",
  ];

  it.each(transientMessages)("treats %p as transient", (message) => {
    expect(isTransientGraphqlError(graphqlError(message))).toBe(true);
  });

  it("matches case-insensitively", () => {
    expect(isTransientGraphqlError(graphqlError("INTERNAL"))).toBe(true);
    expect(isTransientGraphqlError(graphqlError("Temporarily down")))
        .toBe(true);
  });

  it("leaves a genuine validation/query error permanent", () => {
    expect(isTransientGraphqlError(
        graphqlError("Cannot query field \"nope\" on type Customer")))
        .toBe(false);
    expect(isTransientGraphqlError(graphqlError("Not authorized")))
        .toBe(false);
    expect(isTransientGraphqlError(graphqlError(""))).toBe(false);
  });

  it("reads the nested details array, not just the top-level message", () => {
    const err = graphqlError("GraphQL error", [
      {message: "Something went wrong upstream: unavailable"},
    ]);
    expect(isTransientGraphqlError(err)).toBe(true);
  });

  it("reads extensions.code as well as the nested message", () => {
    const err = graphqlError("GraphQL error", [
      {message: "no", extensions: {code: "INTERNAL_SERVER_ERROR"}},
    ]);
    expect(isTransientGraphqlError(err)).toBe(true);
  });

  it("survives malformed details without throwing", () => {
    // A null entry, a non-array details, and a missing extensions object are
    // all shapes Wave has no contract against — a throw here would escape into
    // the dispatch path and be classified as an unexpected (retryable) error,
    // silently laundering a permanent failure into a retry loop.
    expect(isTransientGraphqlError(graphqlError("nope", null))).toBe(false);
    expect(isTransientGraphqlError(graphqlError("nope", [null, undefined])))
        .toBe(false);
    expect(isTransientGraphqlError(graphqlError("nope", [{}]))).toBe(false);
    expect(isTransientGraphqlError(
        graphqlError("nope", [{extensions: {code: 42}}]))).toBe(false);
  });
});

describe("isRetryable", () => {
  it("never retries a validation error — the payload cannot succeed", () => {
    expect(isRetryable(new WaveValidationError([
      {code: "REQUIRED", message: "name is required", path: ["name"]},
    ]))).toBe(false);
  });

  it("retries rateLimited and network failures", () => {
    expect(isRetryable(new WaveApiError("rateLimited", "429"))).toBe(true);
    expect(isRetryable(new WaveApiError("network", "ECONNRESET"))).toBe(true);
  });

  it("retries a graphql error only when it looks transient", () => {
    expect(isRetryable(graphqlError("Internal server error"))).toBe(true);
    expect(isRetryable(graphqlError("Cannot query field"))).toBe(false);
  });

  it("never retries auth or unknown — neither self-heals", () => {
    expect(isRetryable(new WaveApiError("auth", "401"))).toBe(false);
    expect(isRetryable(new WaveApiError("unknown", "???"))).toBe(false);
  });

  it("retries an unexpected/infra error, bounded by maxAttempts", () => {
    expect(isRetryable(new TypeError("x is not a function"))).toBe(true);
    expect(isRetryable(new Error("boom"))).toBe(true);
    expect(isRetryable(undefined)).toBe(true);
    expect(isRetryable("a string throw")).toBe(true);
  });
});

describe("attemptBudgetFor", () => {
  it("raises the budget for a rate-limit, which is not the job's fault", () => {
    expect(attemptBudgetFor(
        new WaveApiError("rateLimited", "429"), DEFAULT_MAX_ATTEMPTS))
        .toBe(RATE_LIMITED_MAX_ATTEMPTS);
  });

  it("judges every other failure on the ordinary budget", () => {
    // The honest reading: a job rate-limited four times and then hitting a
    // real error has four failures, one of which is its own fault.
    expect(attemptBudgetFor(new WaveApiError("network", "reset"), 5)).toBe(5);
    expect(attemptBudgetFor(graphqlError("Internal"), 5)).toBe(5);
    expect(attemptBudgetFor(new Error("boom"), 5)).toBe(5);
  });

  it("never LOWERS a caller's raised budget", () => {
    const raised = RATE_LIMITED_MAX_ATTEMPTS + 10;
    expect(attemptBudgetFor(new WaveApiError("rateLimited", "429"), raised))
        .toBe(raised);
  });
});

describe("sanitizeError", () => {
  // `lastError` lands on the job doc AND on the client doc's wave.syncError,
  // which the admin UI renders — so it must never carry Wave's raw message or
  // any customer data.
  it("reduces a validation error to a fixed, data-free sentence", () => {
    const err = new WaveValidationError([
      {code: "INVALID", message: "email jane@example.com is malformed",
        path: ["email"]},
    ]);
    const out = sanitizeError(err);
    expect(out).toBe("WaveValidationError: Wave rejected the customer data.");
    expect(out).not.toContain("jane@example.com");
  });

  it("reduces a WaveApiError to its class and kind only", () => {
    const err = new WaveApiError(
        "graphql", "customer (514) 555-1234 rejected", [{message: "nope"}]);
    const out = sanitizeError(err);
    expect(out).toBe("WaveApiError(graphql)");
    expect(out).not.toContain("555-1234");
  });

  it("reduces anything else to its class name", () => {
    expect(sanitizeError(new TypeError("obj.foo of undefined")))
        .toBe("TypeError: unexpected error");
    expect(sanitizeError(new Error("secret token abc123")))
        .toBe("Error: unexpected error");
  });

  it("handles a non-Error throw without leaking it", () => {
    expect(sanitizeError(null)).toBe("Error: unexpected error");
    expect(sanitizeError(undefined)).toBe("Error: unexpected error");
    expect(sanitizeError("raw string with (514) 555-1234"))
        .toBe("Error: unexpected error");
    expect(sanitizeError({name: "CustomThing", secret: "x"}))
        .toBe("CustomThing: unexpected error");
  });
});

"use strict";

/**
 * Pins that an upstream Places/Geocoding request cannot hang.
 *
 * `fetch()` has no default timeout in Node, so a slow Geocoding response held
 * the function until the platform deadline. The CLIENT gives up at 10 s
 * (`_callableTimeout`, `google_places_repository.dart`) and surfaces
 * `deadline-exceeded` — but the function kept running, so every abandoned
 * lookup still spent a billed upstream call and a durable rate-limit slot for
 * an answer nobody was waiting for any more. Production showed ten of these
 * failing together, once per staff row on the live-map roster.
 */
jest.mock("../security", () => {
  const actual = jest.requireActual("../security");
  const mock = {
    ...actual,
    assertAdmin: jest.fn().mockResolvedValue(undefined),
    enforceDurableRateLimit: jest.fn().mockResolvedValue({
      refund: jest.fn().mockResolvedValue(undefined),
    }),
  };
  // The callables open with `assertAdminCall`, which COMPOSES the auth check,
  // `assertAdmin` and `assertPayloadShape`. It holds a module-internal
  // reference to the real `assertAdmin`, so stubbing the export alone would
  // intercept nothing and every gate assertion below would pass vacuously —
  // the same "mocked and never actually reached" shape that let three of these
  // gates be deleted with a green suite. Re-composing it here against the MOCK
  // keeps `security.assertAdmin` the thing the tests observe. The composition
  // itself, order included, is proved against the real one in
  // `assert_admin.test.js`.
  mock.assertAdminCall = jest.fn(async (req, allowedKeys) => {
    if (!req.auth || !req.auth.uid) {
      throw new (require("firebase-functions/v2/https").HttpsError)(
          "unauthenticated", "auth-required");
    }
    await mock.assertAdmin(req.auth.uid);
    actual.assertPayloadShape(req.data, allowedKeys);
    return req.auth.uid;
  });
  return mock;
});

const errors = [];
jest.mock("firebase-functions/logger", () => ({
  warn: () => {},
  error: (msg, meta) => errors.push([msg, meta]),
  info: () => {},
  debug: () => {},
}));

const {
  placesReverseGeocode,
  UPSTREAM_TIMEOUT_MS,
} = require("../places");

/**
 * A fetch that never settles until its abort signal fires.
 * @return {!jest.Mock} stub standing in for global.fetch.
 */
function hangingFetch() {
  return jest.fn((url, options) => new Promise((resolve, reject) => {
    const signal = options && options.signal;
    if (!signal) return; // no signal wired up: hang forever, failing the test
    signal.addEventListener("abort", () => {
      const err = new Error("This operation was aborted");
      err.name = "AbortError";
      reject(err);
    });
  }));
}

describe("an upstream request that hangs", () => {
  beforeEach(() => {
    errors.length = 0;
    jest.useFakeTimers();
  });

  afterEach(() => {
    jest.useRealTimers();
  });

  test("is aborted rather than held to the platform deadline", async () => {
    global.fetch = hangingFetch();

    const call = placesReverseGeocode.run({
      auth: {uid: "admin-uid"},
      data: {lat: 45.5, lng: -73.6, locale: "en"},
    });
    // Surface the rejection to the microtask queue before advancing, so the
    // assertion below sees a settled promise rather than an unhandled one.
    const settled = expect(call).rejects.toThrow();

    await jest.advanceTimersByTimeAsync(UPSTREAM_TIMEOUT_MS + 1);
    await settled;

    expect(global.fetch).toHaveBeenCalledTimes(1);
    const [, options] = global.fetch.mock.calls[0];
    expect(options.signal).toBeDefined();
    expect(options.signal.aborted).toBe(true);
  });

  test("gives up BEFORE the client does, so the work is not orphaned", () => {
    // The client's own callable timeout is 10 s. A server budget at or above
    // that means the function is still burning a billed upstream call and a
    // rate-limit slot for a caller that has already given up.
    expect(UPSTREAM_TIMEOUT_MS).toBeLessThan(10_000);
  });

  test("logs the timeout distinctly from a transport error", async () => {
    global.fetch = hangingFetch();

    const call = placesReverseGeocode.run({
      auth: {uid: "admin-uid"},
      data: {lat: 45.5, lng: -73.6, locale: "en"},
    });
    const settled = expect(call).rejects.toThrow();
    await jest.advanceTimersByTimeAsync(UPSTREAM_TIMEOUT_MS + 1);
    await settled;

    const ours = errors.filter(([msg]) => msg.includes("placesReverseGeocode"));
    expect(ours).toHaveLength(1);
    const [, meta] = ours[0];
    // `timedOut` is what separates "Google is slow" from "the network broke"
    // in Cloud Logging; without it both read as a transport error.
    expect(meta.timedOut).toBe(true);
    // Never the coordinates — staff-location PII.
    const logged = JSON.stringify(errors);
    expect(logged).not.toContain("45.5");
    expect(logged).not.toContain("73.6");
  });
});

// assertAdmin and enforceDurableRateLimit are mocked here since they need live
// Firestore. Everything else stays real so we lock in the actual guard order
// for these billable endpoints.
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

const security = require("../security");
const {
  placesAutocomplete,
  placesGetDetails,
  placesReverseGeocode,
} = require("../places");

const ADMIN = {uid: "admin-uid"};

describe("placesAutocomplete admin gate + validation", () => {
  beforeEach(() => {
    global.fetch = jest.fn();
    security.assertAdmin.mockClear();
    security.assertAdmin.mockResolvedValue(undefined);
  });

  test("rejects an unauthenticated caller without fetching", async () => {
    await expect(
        placesAutocomplete.run({data: {input: "123 Main"}, auth: null}),
    ).rejects.toThrow(/auth-required/);
    expect(security.assertAdmin).not.toHaveBeenCalled();
    expect(global.fetch).not.toHaveBeenCalled();
  });

  test("blocks a non-admin before any billable fetch", async () => {
    security.assertAdmin.mockRejectedValueOnce(new Error("admin-required"));
    await expect(
        placesAutocomplete.run({data: {input: "123 Main"}, auth: ADMIN}),
    ).rejects.toThrow(/admin-required/);
    expect(security.assertAdmin).toHaveBeenCalledWith(ADMIN.uid);
    expect(global.fetch).not.toHaveBeenCalled();
  });

  test("rejects a payload with an unexpected key", async () => {
    await expect(
        placesAutocomplete.run({
          data: {input: "123 Main", evil: 1},
          auth: ADMIN,
        }),
    ).rejects.toThrow();
    expect(global.fetch).not.toHaveBeenCalled();
  });
});

describe("placesGetDetails admin gate + validation", () => {
  beforeEach(() => {
    global.fetch = jest.fn();
    security.assertAdmin.mockClear();
    security.assertAdmin.mockResolvedValue(undefined);
  });

  test("rejects an unauthenticated caller without fetching", async () => {
    await expect(
        placesGetDetails.run({data: {placeId: "abc123"}, auth: null}),
    ).rejects.toThrow(/auth-required/);
    expect(security.assertAdmin).not.toHaveBeenCalled();
    expect(global.fetch).not.toHaveBeenCalled();
  });

  test("blocks a non-admin before any billable fetch", async () => {
    security.assertAdmin.mockRejectedValueOnce(new Error("admin-required"));
    await expect(
        placesGetDetails.run({data: {placeId: "abc123"}, auth: ADMIN}),
    ).rejects.toThrow(/admin-required/);
    expect(security.assertAdmin).toHaveBeenCalledWith(ADMIN.uid);
    expect(global.fetch).not.toHaveBeenCalled();
  });

  test("rejects a placeId with illegal characters", async () => {
    await expect(
        placesGetDetails.run({
          data: {placeId: "bad/../id"},
          auth: ADMIN,
        }),
    ).rejects.toThrow(/invalid-placeId/);
    expect(global.fetch).not.toHaveBeenCalled();
  });
});

// This block had no counterpart until 2026-09-01, and its absence was
// MUTATION-PROVEN: deleting `await assertAdmin(req.auth.uid)` from
// placesReverseGeocode left the whole suite green. It is the third billable
// Places proxy and the one the live-location map calls, so an open gate means
// any signed-in employee can bill reverse geocodes against the project key.
describe("placesReverseGeocode admin gate + validation", () => {
  const COORDS = {lat: 45.5, lng: -73.6, locale: "en"};

  beforeEach(() => {
    global.fetch = jest.fn();
    security.assertAdmin.mockClear();
    security.assertAdmin.mockResolvedValue(undefined);
    security.enforceDurableRateLimit.mockClear();
  });

  test("rejects an unauthenticated caller without fetching", async () => {
    await expect(
        placesReverseGeocode.run({data: COORDS, auth: null}),
    ).rejects.toThrow(/auth-required/);
    expect(security.assertAdmin).not.toHaveBeenCalled();
    expect(global.fetch).not.toHaveBeenCalled();
  });

  test("blocks a non-admin before any billable fetch", async () => {
    security.assertAdmin.mockRejectedValueOnce(new Error("admin-required"));
    await expect(
        placesReverseGeocode.run({data: COORDS, auth: ADMIN}),
    ).rejects.toThrow(/admin-required/);
    expect(security.assertAdmin).toHaveBeenCalledWith(ADMIN.uid);
    expect(global.fetch).not.toHaveBeenCalled();
  });

  test("a non-admin burns NO rate-limit slot", async () => {
    // Guard order: assertAdmin sits ABOVE enforceDurableRateLimit, so a
    // refused caller cannot exhaust a legitimate admin's window.
    security.assertAdmin.mockRejectedValueOnce(new Error("admin-required"));
    await expect(
        placesReverseGeocode.run({data: COORDS, auth: ADMIN}),
    ).rejects.toThrow(/admin-required/);
    expect(security.enforceDurableRateLimit).not.toHaveBeenCalled();
  });

  test("rejects a payload with an unexpected key", async () => {
    await expect(
        placesReverseGeocode.run({data: {...COORDS, evil: 1}, auth: ADMIN}),
    ).rejects.toThrow();
    expect(global.fetch).not.toHaveBeenCalled();
  });

  test("rejects an out-of-range latitude", async () => {
    await expect(
        placesReverseGeocode.run({
          data: {...COORDS, lat: 91},
          auth: ADMIN,
        }),
    ).rejects.toThrow(/lat/);
    expect(global.fetch).not.toHaveBeenCalled();
  });

  test("rejects a locale outside the allowlist", async () => {
    await expect(
        placesReverseGeocode.run({
          data: {...COORDS, locale: "de"},
          auth: ADMIN,
        }),
    ).rejects.toThrow(/invalid-locale/);
    expect(global.fetch).not.toHaveBeenCalled();
  });
});

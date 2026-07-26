// assertAdmin and enforceDurableRateLimit are mocked (need live Firestore); the rest
// stay real to lock in the actual guard order for these billable endpoints.
jest.mock("../security", () => {
  const actual = jest.requireActual("../security");
  return {
    ...actual,
    assertAdmin: jest.fn().mockResolvedValue(undefined),
    enforceDurableRateLimit: jest.fn().mockResolvedValue({
      refund: jest.fn().mockResolvedValue(undefined),
    }),
  };
});

const security = require("../security");
const {placesAutocomplete, placesGetDetails} = require("../places");

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

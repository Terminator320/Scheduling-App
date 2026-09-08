"use strict";

/**
 * Pins that a non-200 from Places/Geocoding never puts the request body — and
 * therefore never puts the client street address an admin was mid-typing — into
 * Cloud Logging.
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
  // `assertAdmin` and `assertPayloadShape`.
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

const warnings = [];
jest.mock("firebase-functions/logger", () => ({
  warn: (msg, meta) => warnings.push([msg, meta]),
  error: () => {},
  info: () => {},
  debug: () => {},
}));

const {placesAutocomplete, upstreamErrorCode} = require("../places");

// The shape Places API (New) actually returns on a rejected input — the message
// quotes the offending field back, which is the whole problem.
const REJECTION_BODY = JSON.stringify({
  error: {
    code: 400,
    message: "Invalid value at 'input' (1425 Rue Sainte-Catherine O)",
    status: "INVALID_ARGUMENT",
  },
});

describe("upstreamErrorCode", () => {
  test("keeps the enum status", () => {
    expect(upstreamErrorCode(REJECTION_BODY)).toBe("INVALID_ARGUMENT");
  });

  test("falls back to the numeric code when there is no status", () => {
    expect(upstreamErrorCode(JSON.stringify({error: {code: 429}})))
        .toBe("429");
  });

  test("reads the Geocoding API's top-level status", () => {
    expect(upstreamErrorCode(JSON.stringify({status: "REQUEST_DENIED"})))
        .toBe("REQUEST_DENIED");
  });

  test("drops anything that is not enum-shaped", () => {
    // The guard that stops prose reaching the log if an upstream ever puts a
    // message where the code belongs.
    expect(upstreamErrorCode(JSON.stringify({
      error: {status: "Invalid value at 'input' (1425 Rue Sainte-Catherine)"},
    }))).toBe("");
  });

  test("a non-JSON body yields nothing rather than throwing", () => {
    expect(upstreamErrorCode("<html>502 Bad Gateway</html>")).toBe("");
    expect(upstreamErrorCode("")).toBe("");
  });
});

describe("a rejected autocomplete", () => {
  beforeEach(() => {
    warnings.length = 0;
  });

  test("logs the code and never the body", async () => {
    global.fetch = jest.fn().mockResolvedValue({
      ok: false,
      status: 400,
      text: async () => REJECTION_BODY,
    });

    await expect(placesAutocomplete.run({
      auth: {uid: "admin-uid"},
      data: {input: "1425 Rue Sainte-Catherine O"},
    })).rejects.toThrow();

    // Filtered: the params layer also warns about the unbound secret here.
    const ours = warnings.filter(([msg]) => msg.startsWith("placesAuto"));
    expect(ours).toEqual([
      ["placesAutocomplete: upstream non-200",
        {status: 400, code: "INVALID_ARGUMENT"}],
    ]);
    const logged = JSON.stringify(warnings);
    expect(logged).not.toContain("Sainte-Catherine");
    expect(logged).not.toContain("Invalid value");
  });
});

// placesReverseGeocode is safe to require directly since it has no eager
// bucket resolution. We mock assertAdmin/enforceDurableRateLimit because they
// need live Firestore, but leave the real validation helpers in place.
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

const {placesReverseGeocode} = require("../places");

const AUTH = {uid: "admin-uid"};

/**
 * Builds a fetch-compatible OK response stub around a Geocoding API body.
 * @param {object} body decoded JSON body to resolve.
 * @return {{ok: boolean, status: number, json: function(): !Promise<object>}}
 */
function okResponse(body) {
  return {
    ok: true,
    status: 200,
    json: async () => body,
  };
}

/**
 * Invokes the placesReverseGeocode handler directly with an admin auth ctx.
 * @param {object} data callable request payload.
 * @return {!Promise<*>}
 */
function run(data) {
  return placesReverseGeocode.run({data, auth: AUTH});
}

describe("placesReverseGeocode input validation", () => {
  beforeEach(() => {
    global.fetch = jest.fn();
  });

  test("rejects a missing lat", async () => {
    await expect(run({lng: -73.5, locale: "en"}))
        .rejects.toThrow(/invalid-lat/);
  });

  test("rejects lat above 90", async () => {
    await expect(run({lat: 91, lng: -73.5, locale: "en"}))
        .rejects.toThrow(/invalid-lat/);
  });

  test("rejects lng below -180", async () => {
    await expect(run({lat: 45.5, lng: -181, locale: "en"}))
        .rejects.toThrow(/invalid-lng/);
  });

  test("rejects lat sent as a string", async () => {
    await expect(run({lat: "45.5", lng: -73.5, locale: "en"}))
        .rejects.toThrow(/invalid-lat/);
  });

  test("rejects NaN", async () => {
    await expect(run({lat: NaN, lng: -73.5, locale: "en"}))
        .rejects.toThrow(/invalid-lat/);
  });

  test("rejects an unsupported locale", async () => {
    await expect(run({lat: 45.5, lng: -73.5, locale: "de"}))
        .rejects.toThrow(/invalid-locale/);
  });

  test("a rejected request never reaches the upstream API", async () => {
    await expect(run({lat: 91, lng: -73.5, locale: "en"}))
        .rejects.toThrow(/invalid-lat/);

    expect(global.fetch).not.toHaveBeenCalled();
  });
});

describe("placesReverseGeocode coordinate rounding", () => {
  beforeEach(() => {
    global.fetch = jest.fn().mockResolvedValue(
        okResponse({status: "OK", results: [
          {formatted_address: "123 Main St, Montréal, QC"},
        ]}),
    );
  });

  test("rounds lat/lng to 5 decimals before calling upstream", async () => {
    await run({lat: 45.501234567, lng: -73.987654321, locale: "en"});

    expect(global.fetch).toHaveBeenCalledTimes(1);
    const calledUrl = new URL(global.fetch.mock.calls[0][0]);
    expect(calledUrl.searchParams.get("latlng")).toBe("45.50123,-73.98765");
    expect(calledUrl.searchParams.get("language")).toBe("en");
  });
});

describe("placesReverseGeocode formatted-address extraction", () => {
  test("returns the top result's formatted_address on OK", async () => {
    global.fetch = jest.fn().mockResolvedValue(
        okResponse({status: "OK", results: [
          {formatted_address: "1234 Rue Saint-Denis, Montréal, QC"},
          {formatted_address: "should be ignored"},
        ]}),
    );

    const result = await run({lat: 45.5, lng: -73.5, locale: "fr"});

    expect(result).toEqual({address: "1234 Rue Saint-Denis, Montréal, QC"});
  });

  test("returns a null address on ZERO_RESULTS", async () => {
    global.fetch = jest.fn().mockResolvedValue(
        okResponse({status: "ZERO_RESULTS", results: []}),
    );

    const result = await run({lat: 45.5, lng: -73.5, locale: "en"});

    expect(result).toEqual({address: null});
  });

  test("throws internal on a non-OK non-ZERO_RESULTS status", async () => {
    global.fetch = jest.fn().mockResolvedValue(
        okResponse({status: "REQUEST_DENIED", results: []}),
    );

    await expect(run({lat: 45.5, lng: -73.5, locale: "en"}))
        .rejects.toThrow(/places-upstream/);
  });

  test("throws internal on an HTTP-level upstream failure", async () => {
    global.fetch = jest.fn().mockResolvedValue({
      ok: false,
      status: 500,
      json: async () => ({}),
    });

    await expect(run({lat: 45.5, lng: -73.5, locale: "en"}))
        .rejects.toThrow(/places-upstream/);
  });
});

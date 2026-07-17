const {requireNumberInRange} = require("../security");

describe("requireNumberInRange", () => {
  test("returns the value when it is a finite number in range", () => {
    expect(requireNumberInRange(45.5, "lat", -90, 90)).toBe(45.5);
  });

  test("accepts the inclusive boundary values", () => {
    expect(requireNumberInRange(-90, "lat", -90, 90)).toBe(-90);
    expect(requireNumberInRange(90, "lat", -90, 90)).toBe(90);
  });

  test("rejects a value above max", () => {
    expect(() => requireNumberInRange(91, "lat", -90, 90))
        .toThrow(/invalid-lat/);
  });

  test("rejects a value below min", () => {
    expect(() => requireNumberInRange(-181, "lng", -180, 180))
        .toThrow(/invalid-lng/);
  });

  test("rejects a non-number value", () => {
    expect(() => requireNumberInRange("45.5", "lat", -90, 90))
        .toThrow(/invalid-lat/);
  });

  test("rejects NaN", () => {
    expect(() => requireNumberInRange(NaN, "lat", -90, 90))
        .toThrow(/invalid-lat/);
  });

  test("rejects Infinity", () => {
    expect(() => requireNumberInRange(Infinity, "lat", -90, 90))
        .toThrow(/invalid-lat/);
  });

  test("rejects a missing value", () => {
    expect(() => requireNumberInRange(undefined, "lat", -90, 90))
        .toThrow(/invalid-lat/);
  });
});

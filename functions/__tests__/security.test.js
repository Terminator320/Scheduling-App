const {
  hasControlChar,
  assertPayloadShape,
  requireString,
  readSessionToken,
  requireNumberInRange,
} = require("../security");

// Build control characters explicitly to avoid source-encoding ambiguity.
const NUL = String.fromCharCode(0x00);
const DEL = String.fromCharCode(0x7F);

describe("hasControlChar", () => {
  test("false for clean printable text", () => {
    expect(hasControlChar("Montréal H1H 1H1")).toBe(false);
  });

  test("true for a C0 control character", () => {
    expect(hasControlChar(`a${NUL}b`)).toBe(true);
  });

  test("true for DEL (0x7F)", () => {
    expect(hasControlChar(`a${DEL}b`)).toBe(true);
  });
});

describe("assertPayloadShape", () => {
  const allowed = new Set(["input", "sessionToken"]);

  test("accepts null / undefined as an empty payload", () => {
    expect(() => assertPayloadShape(null, allowed)).not.toThrow();
    expect(() => assertPayloadShape(undefined, allowed)).not.toThrow();
  });

  test("accepts an object with only allowed keys", () => {
    expect(() => assertPayloadShape({input: "x"}, allowed)).not.toThrow();
  });

  test("rejects an array", () => {
    expect(() => assertPayloadShape([], allowed)).toThrow("malformed-payload");
  });

  test("rejects a non-object primitive", () => {
    expect(() => assertPayloadShape("x", allowed)).toThrow("malformed-payload");
  });

  test("rejects an unexpected key (mass-assignment defence)", () => {
    expect(() => assertPayloadShape({role: "admin"}, allowed)).toThrow(
        "unexpected-field",
    );
  });

  test("rejects a payload larger than the cap", () => {
    const big = {input: "a".repeat(5 * 1024)};
    expect(() => assertPayloadShape(big, allowed)).toThrow("payload-too-large");
  });
});

describe("requireString", () => {
  test("returns the trimmed value", () => {
    expect(requireString({input: "  hi  "}, "input", 10)).toBe("hi");
  });

  test("throws when missing", () => {
    expect(() => requireString({}, "input", 10)).toThrow("invalid-input");
  });

  test("throws when blank after trim", () => {
    expect(() => requireString({input: "   "}, "input", 10)).toThrow(
        "invalid-input",
    );
  });

  test("throws when over maxLen", () => {
    expect(() => requireString({input: "abcdef"}, "input", 3)).toThrow(
        "invalid-input",
    );
  });

  test("throws when it contains a control character", () => {
    expect(() => requireString({input: `a${NUL}`}, "input", 10)).toThrow(
        "invalid-input",
    );
  });
});

describe("readSessionToken", () => {
  test("returns empty string when absent", () => {
    expect(readSessionToken({})).toBe("");
    expect(readSessionToken({sessionToken: null})).toBe("");
  });

  test("returns a valid token unchanged", () => {
    expect(readSessionToken({sessionToken: "abc-123"})).toBe("abc-123");
  });

  test("throws when too long", () => {
    expect(() => readSessionToken({sessionToken: "a".repeat(65)})).toThrow(
        "invalid-sessionToken",
    );
  });

  test("throws when wrong type", () => {
    expect(() => readSessionToken({sessionToken: 42})).toThrow(
        "invalid-sessionToken",
    );
  });

  test("throws when it contains a control character", () => {
    expect(() => readSessionToken({sessionToken: `a${NUL}`})).toThrow(
        "invalid-sessionToken",
    );
  });
});

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

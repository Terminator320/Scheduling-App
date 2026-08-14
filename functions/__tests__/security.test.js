// `assertFreshReauth` logs its rejection through the functions logger, which
// would otherwise write to the suite's stdout on every negative case.
jest.mock("firebase-functions/logger", () => ({
  info: jest.fn(),
  warn: jest.fn(),
  debug: jest.fn(),
  error: jest.fn(),
}));

const {
  hasControlChar,
  assertPayloadShape,
  requireString,
  optionalString,
  readSessionToken,
  requireNumberInRange,
  assertFreshReauth,
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

describe("optionalString", () => {
  // Guards the not-required fields on the employee-account callables
  // (phone, jobTitle, firstName/lastName, colorValue...). It is the ONE place
  // "absent is fine, but what IS there is still validated" is expressed —
  // `invites.js` and `employee_accounts.js` each carried a private copy.

  test("an absent field reads as empty, it does not throw", () => {
    // The whole reason it exists: `requireString` would reject an omitted
    // optional field and fail the entire create.
    expect(optionalString({}, "phone", 24)).toBe("");
    expect(optionalString({phone: undefined}, "phone", 24)).toBe("");
    expect(optionalString({phone: null}, "phone", 24)).toBe("");
  });

  test("a missing payload object reads as empty too", () => {
    // Callables reach it with `req.data` straight through, which can be
    // undefined when the client sends no payload at all.
    expect(optionalString(undefined, "phone", 24)).toBe("");
    expect(optionalString(null, "phone", 24)).toBe("");
  });

  test("a non-string value is dropped, not rejected", () => {
    // Deliberate asymmetry with the caps below: only a STRING is inspected,
    // so anything else degrades to absent rather than failing the call.
    expect(optionalString({phone: 5145551234}, "phone", 24)).toBe("");
    expect(optionalString({phone: {}}, "phone", 24)).toBe("");
    expect(optionalString({phone: ["x"]}, "phone", 24)).toBe("");
  });

  test("the returned value is trimmed", () => {
    // What is stored is the trimmed form, so every cap below has to be
    // measured against it and not against the raw text.
    expect(optionalString({phone: "  (514) 555-1234  "}, "phone", 24))
        .toBe("(514) 555-1234");
  });

  test("whitespace-only is empty, where requireString would reject it", () => {
    // The one behavioural difference from its sibling — pin it so a
    // "simplification" that routes optional fields through requireString
    // fails here rather than in production.
    expect(optionalString({phone: "   "}, "phone", 24)).toBe("");
    expect(() => requireString({phone: "   "}, "phone", 24))
        .toThrow("invalid-phone");
  });

  test("the length cap still applies, and is measured after trimming", () => {
    // A rules cap sits behind this; letting an over-long value through
    // reaches the user as an opaque permission-denied on an ordinary save.
    expect(optionalString({phone: "abc"}, "phone", 3)).toBe("abc");
    expect(() => optionalString({phone: "abcd"}, "phone", 3))
        .toThrow("invalid-phone");
    // Trimmed to 3, so it passes despite being 7 raw characters.
    expect(optionalString({phone: "  abc  "}, "phone", 3)).toBe("abc");
  });

  test("a control character is rejected, not silently dropped", () => {
    // Log-injection defence: these values are logged and written to
    // Firestore, so "optional" must never mean "unvalidated".
    expect(() => optionalString({phone: `a${NUL}b`}, "phone", 24))
        .toThrow("invalid-phone");
    expect(() => optionalString({phone: `a${DEL}b`}, "phone", 24))
        .toThrow("invalid-phone");
  });

  test("the thrown code names the field it rejected", () => {
    // Callers map this string onto a field-level message; a generic code
    // would leave the user unable to tell which input to fix.
    expect(() => optionalString({jobTitle: `x${NUL}`}, "jobTitle", 24))
        .toThrow("invalid-jobTitle");
  });
});

describe("assertFreshReauth", () => {
  // The throwing wrapper around the (separately tested) `isReauthStale`.
  // It guards `changeEmployeeEmail` — rewriting a sign-in identity — so an
  // unattended unlocked phone must not be able to do it on a stale token.
  // Both call sites use a 5-minute window.
  const MAX_AGE = 5 * 60;
  const NOW_SEC = 1800000000;

  beforeEach(() => {
    jest.spyOn(Date, "now").mockReturnValue(NOW_SEC * 1000);
  });

  afterEach(() => {
    jest.restoreAllMocks();
  });

  const authAt = (authTime) => ({uid: "u1", token: {auth_time: authTime}});

  test("a caller who re-authenticated just now passes", () => {
    expect(() => assertFreshReauth(authAt(NOW_SEC), "route", MAX_AGE))
        .not.toThrow();
  });

  test("the window boundary is inclusive", () => {
    // `>` not `>=`: a re-auth exactly at the limit must still be honoured, or
    // a slow user hitting Save at 5:00 is bounced with nothing to fix.
    expect(() => assertFreshReauth(authAt(NOW_SEC - MAX_AGE), "r", MAX_AGE))
        .not.toThrow();
    expect(() => assertFreshReauth(authAt(NOW_SEC - MAX_AGE - 1), "r", MAX_AGE))
        .toThrow("stale-auth");
  });

  test("a stale re-auth throws unauthenticated/stale-auth", () => {
    // The CODE and the MESSAGE are both contract: the Flutter client branches
    // on them to re-prompt for the password instead of showing a generic
    // failure.
    let caught = null;
    try {
      assertFreshReauth(authAt(NOW_SEC - 10 * 60), "changeEmployeeEmail",
          MAX_AGE);
    } catch (err) {
      caught = err;
    }
    expect(caught).not.toBeNull();
    expect(caught.code).toBe("unauthenticated");
    expect(caught.message).toBe("stale-auth");
  });

  test("a token with no auth_time FAILS CLOSED", () => {
    // A caller presenting no claim must not read as "recently
    // re-authenticated" — this is the branch a direct (non-app) call takes.
    expect(() => assertFreshReauth({uid: "u1", token: {}}, "r", MAX_AGE))
        .toThrow("stale-auth");
  });

  test("a non-numeric auth_time FAILS CLOSED", () => {
    // A string would make `nowSec - authTime` NaN, and `NaN > max` is false —
    // i.e. it would read as fresh if the type check were dropped.
    expect(() => assertFreshReauth(authAt("1800000000"), "r", MAX_AGE))
        .toThrow("stale-auth");
    expect(() => assertFreshReauth(authAt(null), "r", MAX_AGE))
        .toThrow("stale-auth");
  });

  test("a missing auth or token object throws rather than crashing", () => {
    // It runs below the auth guard, but its own log line reads `auth.uid`, so
    // it must survive being handed nothing.
    expect(() => assertFreshReauth(undefined, "r", MAX_AGE))
        .toThrow("stale-auth");
    expect(() => assertFreshReauth({uid: "u1"}, "r", MAX_AGE))
        .toThrow("stale-auth");
  });

  test("a future auth_time is treated as fresh, not as an error", () => {
    // Clock skew between the token issuer and this instance is normal; a
    // negative age must not be read as stale.
    expect(() => assertFreshReauth(authAt(NOW_SEC + 30), "r", MAX_AGE))
        .not.toThrow();
  });
});

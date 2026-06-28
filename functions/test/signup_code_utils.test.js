const {
  generateSignupCode,
  hashSignupCode,
  validateRedemption,
} = require("../signup_code_utils");

describe("generateSignupCode", () => {
  test("formats as three dash-separated groups of four", () => {
    expect(generateSignupCode())
        .toMatch(/^[0-9A-Z]{4}-[0-9A-Z]{4}-[0-9A-Z]{4}$/);
  });
  test("uses no ambiguous characters (I, L, O, U)", () => {
    for (let i = 0; i < 200; i++) {
      expect(generateSignupCode()).not.toMatch(/[ILOU]/);
    }
  });
  test("is effectively unique across calls", () => {
    const seen = new Set();
    for (let i = 0; i < 1000; i++) seen.add(generateSignupCode());
    expect(seen.size).toBe(1000);
  });
});

describe("hashSignupCode", () => {
  test("is stable and ignores dashes and case", () => {
    const a = hashSignupCode("K7Q2-9MZ4-XR8T");
    const b = hashSignupCode("k7q29mz4xr8t");
    expect(a).toBe(b);
    expect(a).toMatch(/^[0-9a-f]{64}$/);
  });
  test("differs for different codes", () => {
    expect(hashSignupCode("AAAA-AAAA-AAAA"))
        .not.toBe(hashSignupCode("AAAA-AAAA-AAAB"));
  });
});

describe("validateRedemption", () => {
  const future = {toMillis: () => 2_000_000};
  const past = {toMillis: () => 1_000};
  const invite = {
    status: "invited", uid: "", email: "a@b.com",
    role: "employee", name: "A",
  };
  const code = {inviteDocId: "x", email: "a@b.com", expiresAt: future};

  test("ok for a valid, unexpired, matching-email invite", () => {
    expect(validateRedemption({
      codeData: code, inviteData: invite,
      tokenEmail: "a@b.com", nowMs: 1_500_000,
    })).toEqual({ok: true});
  });
  test("invalid when the code doc is missing", () => {
    expect(validateRedemption({
      codeData: null, inviteData: invite,
      tokenEmail: "a@b.com", nowMs: 1_500_000,
    })).toEqual({ok: false, reason: "invalid"});
  });
  test("invalid when the invite is already claimed", () => {
    expect(validateRedemption({
      codeData: code,
      inviteData: {...invite, uid: "u1", status: "active"},
      tokenEmail: "a@b.com", nowMs: 1_500_000,
    })).toEqual({ok: false, reason: "invalid"});
  });
  test("email-mismatch when the token email does not match the invite", () => {
    expect(validateRedemption({
      codeData: code, inviteData: invite,
      tokenEmail: "other@b.com", nowMs: 1_500_000,
    })).toEqual({ok: false, reason: "email-mismatch"});
  });
  test("invalid (not email-mismatch) when there is no token email", () => {
    expect(validateRedemption({
      codeData: code, inviteData: invite,
      tokenEmail: "", nowMs: 1_500_000,
    })).toEqual({ok: false, reason: "invalid"});
  });
  test("expired when past expiresAt", () => {
    expect(validateRedemption({
      codeData: {...code, expiresAt: past}, inviteData: invite,
      tokenEmail: "a@b.com", nowMs: 1_500_000,
    })).toEqual({ok: false, reason: "expired"});
  });
});

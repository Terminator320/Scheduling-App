const crypto = require("crypto");

// 14-day code lifetime.
const INVITE_CODE_TTL_MS = 14 * 24 * 60 * 60 * 1000;

// Crockford base32 (no I, L, O, U) — 32 chars, so byte % 32 is unbiased
// (256 is a multiple of 32) and the result is human-typable.
const ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";

/**
 * 12 random base32 chars grouped XXXX-XXXX-XXXX (~60 bits of entropy).
 * @return {string}
 */
function generateSignupCode() {
  const bytes = crypto.randomBytes(12);
  let out = "";
  for (let i = 0; i < 12; i++) out += ALPHABET[bytes[i] % 32];
  return `${out.slice(0, 4)}-${out.slice(4, 8)}-${out.slice(8, 12)}`;
}

/**
 * sha256 hex of the code, normalized (dashes stripped, uppercased) so the
 * stored hash is independent of how the user types the code.
 * @param {string} code raw code.
 * @return {string}
 */
function hashSignupCode(code) {
  const normalized = String(code).replace(/-/g, "").toUpperCase();
  return crypto.createHash("sha256").update(normalized).digest("hex");
}

/**
 * Pure redemption decision. Returns {ok:true} or {ok:false, reason}.
 * @param {Object} args codeData, inviteData, tokenEmail, nowMs.
 * @return {Object} {ok: boolean, reason?: string}
 */
function validateRedemption({codeData, inviteData, tokenEmail, nowMs}) {
  if (!codeData || !inviteData) return {ok: false, reason: "invalid"};
  if (inviteData.status !== "invited" || (inviteData.uid || "") !== "") {
    return {ok: false, reason: "invalid"};
  }
  const inviteEmail = String(inviteData.email || "").trim().toLowerCase();
  const claimEmail = String(tokenEmail || "").trim().toLowerCase();
  if (!claimEmail) return {ok: false, reason: "invalid"};
  // We surface this distinctly (not as "invalid code") so the UI can tell
  // the user to use the exact invited email. It's only reached once we
  // already have an otherwise-valid code.
  if (inviteEmail !== claimEmail) {
    return {ok: false, reason: "email-mismatch"};
  }
  const expiresAtMs = codeData.expiresAt &&
    typeof codeData.expiresAt.toMillis === "function" ?
    codeData.expiresAt.toMillis() : 0;
  if (expiresAtMs <= nowMs) return {ok: false, reason: "expired"};
  return {ok: true};
}

module.exports = {
  INVITE_CODE_TTL_MS,
  generateSignupCode,
  hashSignupCode,
  validateRedemption,
};

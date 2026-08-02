/// Length of a signup code once normalized. `generateSignupCode`
/// (`functions/signup_code_utils.js`) emits 12 Crockford base32 characters,
/// grouped for reading as `XXXX-XXXX-XXXX`.
const int kSignupCodeLength = 12;

/// Uppercases and strips separators — the one client mirror of the
/// normalization the server applies before hashing (`hashSignupCode` strips
/// dashes and uppercases).
///
/// Stripping every non-alphanumeric rather than dashes alone is a deliberate
/// superset, not a divergence: the string we send is already canonical, so the
/// server's own pass over it is a no-op, and a code pasted with stray spaces
/// still redeems. No Crockford aliasing (I→1, O→0) — the server does none, and
/// a half-shared convention is worse than none.
String normalizeSignupCode(String raw) =>
    raw.toUpperCase().replaceAll(RegExp('[^0-9A-Z]'), '');

/// True once [raw] normalizes to a full-length code — the code screen's
/// Continue gate. Validity is still judged server-side.
bool isCompleteSignupCode(String raw) =>
    normalizeSignupCode(raw).length == kSignupCodeLength;

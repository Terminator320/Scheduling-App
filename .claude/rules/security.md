---
alwaysApply: true
---

# Security

- Validate all user input at the system boundary. Never trust data from UI directly.
- On Cloud Function callables, reject oversized/malformed payloads with `assertPayloadShape` (non-object, >4 KB, or unexpected keys) and validate string fields via `requireString`/`readSessionToken` (trim, length cap, control-char reject) before use.
- Never read `isAdmin` or user role from SharedPreferences — always re-read from Firestore.
- Authentication tokens are managed by FirebaseAuth. Don't cache or store them manually.
- Never log secrets, API keys, tokens, passwords, or PII.
- A `TextField` that receives a credential must set
  `enableIMEPersonalizedLearning: false` **explicitly**, and never lean on
  `obscureText` to imply it. `keyboardType: visiblePassword` does not imply it
  either; a field rendering its characters lets a third-party keyboard retain
  and cloud-sync what was typed. **`obscureText` is not a safe proxy, because
  every password field here has a Show/Hide toggle** — the instant it is
  tapped the field is plain text at the `true` default. That is exactly how
  `AuthPasswordField` (both P4c setup fields ride it) and both
  `DeleteAccountReauthDialog` variants shipped without it. Set the flag
  unconditionally, beside `obscureText`, and pass
  `kCredentialImePersonalizedLearning`
  (`lib/core/security/credential_input.dart`) rather than a bare `false` — the
  four sites each carried their own restatement of this paragraph, and the
  named constant is what makes "every credential field" greppable.
- All Firestore writes go through service classes. Never call `FirebaseFirestore.instance` from UI.
- Firestore security rules (`firestore.rules`) are the last line of defense — keep them restrictive.
- Rate-limit auth-sensitive Cloud Function callables. `deleteAccount/completeEmployeeSetup` use the Firestore-backed `enforceDurableRateLimit` (5 attempts/15 min; counters in `rateLimits/*`, which clients cannot read or write). Firebase Auth already rate-limits sign-in attempts; don't bypass that either. The admin-only `createEmployeeAccount` and `deleteEmployeeAccount` are also durably rate-limited (20/hour per admin uid) — defense-in-depth so a compromised admin session can't mass-create real Firebase Auth accounts or mass-delete pending ones; keep new admin write-callables similarly capped. **Guard order:** auth → `assertAdmin` → `assertPayloadShape`/`requireString` → `enforceDurableRateLimit` → work. Validate the payload BEFORE consuming a rate-limit slot so a burst of malformed submissions can't exhaust a legitimate caller's window; keep the identity guards (`assertAdmin`) above the limiter so non-privileged callers still can't burn slots. `completeEmployeeSetup`'s `email_verified` check is an identity guard too and sits in the same slot.
- **A guard must FAIL CLOSED on missing input.** `if (req.auth.token && req.auth.token.email_verified !== true) throw` reads as a check but lets a caller through by not presenting a token at all — write `if (!req.auth.token || ...)`. That the platform always populates the field today makes it unreachable, not correct: the guard is the thing the written risk assessment leans on, so it has to hold on its own terms. A test that passes `token: {}` will not catch this — it only catches the absent-token case if it omits the key.
- Image uploads: validate magic bytes (JPEG `FF D8 FF`, PNG `89 50 4E`) — extension alone is not sufficient.
- A client-written TTL field must be **bounded in the rules**, not just type-checked — `expiresAt is timestamp` alone lets a client park a row past every server-side reaper. `liveActivityTokens` caps it at `request.time + 31 d`; that ceiling has to stay just above the longest TTL the app legitimately writes (`liveActivityPushToStartTtl`, 30 d) — raise both together, and never derive the bound from a server-side constant without checking what the client actually writes.
- App Check (`firebase_app_check`) must stay activated in `main()`. Do not remove.
- Cloud Function **callables** set `enforceAppCheck: true` (`places.js`, `account.js`, `clients.js`, `employee_accounts.js`, `wave/callables.js` — `invites.js` was deleted 2026-08-08 with the `#compat-1.37.1` shim). The temporary pre-ship `enforceAppCheck: false` carve-out — for Firebase App Distribution sideload testers whose builds can't mint verified tokens — was retired in 1.25.1; a new callable must enforce App Check, not default it off. Enforcement activates on `firebase deploy --only functions`.
- Never commit or read `dev/.env` or `google-services.json` — they are gitignored for a reason.

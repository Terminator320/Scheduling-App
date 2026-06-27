# Invited-employee signup redesign — one-time signup codes

**Date:** 2026-06-27
**Status:** Approved design, ready for implementation plan
**Supersedes:** `docs/AUDIT_FOLLOWUPS.md` §4 (the deferred "redesign signup" item)

---

## 1. Problem

Commit `612a1cc` hardened `resolveMyInvite` (`functions/account.js`) to return
`{found:false}` for any caller whose token isn't `email_verified`, closing an
invite-metadata leak. But `createEmployeeAccount`
(`lib/features/auth/services/auth_service.dart`) calls
`findInvitedEmployeeForCurrentUser()` → `resolveMyInvite` **before** the email is
verified, to decide whether to send the verification email or roll the account
back. Deploying the functions as-is therefore breaks **all** invited-employee
signup (`AuthFailureNotAuthorized`). Both sites carry a `FIXME(pre-deploy)`
marker; the `functions` target must not deploy until this lands.

The root cause is structural: invite-only **creation** needs a pre-verification
"does an invite exist for this email?" check, which is exactly the
email-existence oracle the security fix closed. The two can't coexist.

## 2. Solution overview

Replace the email-existence check with a **one-time signup code** — a secret the
admin generates per invite and shares with the employee out-of-band. The code,
not an email guess, authorizes signup, so there is no oracle to leak. Redeeming
a valid code **activates the account immediately** (no email-verification step),
which removes `resolveMyInvite` from the flow entirely and resolves the deploy
blocker.

### Locked decisions

| # | Decision | Choice |
|---|---|---|
| 1 | Creation gate | One-time signup code (not open creation) |
| 2 | Code delivery | Admin shares it out-of-band (no email infrastructure) |
| 3 | Activation | Redeeming the code activates immediately (no email verification) |
| 4 | Code generation/storage | **Approach A** — server-side callable; hash in a client-locked collection |
| 5 | Code policy | 14-day expiry; signup email must match the invite email |
| 6 | Legacy `resolveMyInvite` | Delete it and its dependents (clean cutover) |

## 3. Architecture

### 3.1 Data model

- **New collection `signupCodes/{codeHash}`** — doc id is `sha256(code)`.
  Fields: `{ inviteDocId: string, email: string, expiresAt: timestamp,
  createdAt: timestamp }`. **Firestore rules deny all client read/write**
  (Cloud-Functions-only, mirroring `rateLimits/*`). The plaintext code is never
  stored anywhere.
- **`users` invite doc** — unchanged shape: `status:'invited'`, `uid:''`,
  `role:'employee'`, plus `name`/`email`/`phone`/`colorValue`/`createdAt`. No
  secret is stored on it.

### 3.2 Cloud Functions (in `functions/`, re-exported from `index.js`)

New module `functions/invites.js` (keeps `account.js` focused), using the shared
guards in `security.js` (`assertAdmin`, `assertPayloadShape`, `requireString`,
`enforceDurableRateLimit`).

**`createEmployeeInvite`** — `onCall`, `assertAdmin` + App Check. No strict
durable rate limit (admins are trusted and may batch-invite; `assertAdmin` +
App Check already bound the surface).
- Input: `{ name, email, phone, colorValue }` (validated via `requireString` /
  shape guard; email normalized `.trim().toLowerCase()`).
- Rejects a duplicate email (existing `users` doc with that email).
- Generates a code (§3.4), computes `sha256(code)`.
- In **one transaction**: creates the `users` invite doc (`status:'invited'`,
  `uid:''`, `createdAt`/`updatedAt` server timestamps) and the
  `signupCodes/{hash}` doc (`inviteDocId`, normalized `email`, `expiresAt =
  now + 14d`, `createdAt`).
- Returns `{ code }` (plaintext, shown once to the admin). The code is never
  returned again.

**`regenerateSignupCode`** — `onCall`, `assertAdmin` + App Check.
- Input: `{ inviteDocId }`. Only valid while the invite is still `invited`
  (unclaimed). Generates a fresh code, writes a new `signupCodes` doc, and
  **deletes the previous code doc** for that invite (look it up by
  `inviteDocId`, or store `inviteDocId → codeHash` to find it). Returns
  `{ code }`.

**`redeemSignupCode`** — `onCall`, auth required + App Check +
`enforceDurableRateLimit` (5 / 15 min, keyed by uid).
- Input: `{ code }`. `assertPayloadShape` + `requireString`.
- Requires `req.auth.token.email` (verified-claim NOT required — that's the
  point). Compute `sha256(code)`, `get signupCodes/{hash}`.
- Validate, **all server-side**: doc exists; `expiresAt` in the future; the
  referenced `users` invite doc still `status:'invited'` and `uid:''`; the
  invite `email` equals the caller's token email (normalized).
- On success, **one transaction**: set invite `uid = req.auth.uid`,
  `status:'active'`, `updatedAt`; delete the `signupCodes/{hash}` doc (one-time).
- Returns `{ role, name }` on success. On any validation failure throws a
  precise `HttpsError` whose `code`/message the client maps to a typed failure
  (§3.6), and logs the precise reason server-side.

All three follow the existing `enforceAppCheck:false` + `TODO(pre-ship)` pattern
until the app ships through the stores (same as `resolveMyInvite`/`deleteAccount`
today).

### 3.3 Firestore rules

- `match /signupCodes/{id}` → `allow read, write: if false;` (Cloud-Functions
  only, like `rateLimits`).
- **Remove** the `users` self-activation update clause (the one requiring
  `request.auth.token.email_verified == true`). Activation is now exclusively
  server-side via `redeemSignupCode` (Admin SDK), so clients never self-activate.
  Re-verify no other client path depends on that clause before removing.

### 3.4 Code format, expiry, rate limiting

- **Format:** 12 chars from an unambiguous base32 alphabet (no `0/O/1/I`),
  grouped for readability, e.g. `K7Q2-9MZ4-XR8T` (≈60 bits). Generated with a
  CSPRNG server-side.
- **Expiry:** 14 days (`expiresAt`). Expired codes are rejected; admin
  regenerates.
- **One-time:** the `signupCodes` doc is deleted on successful redemption, and
  the invite becomes `active`/claimed, so a code can't be reused.
- **Rate limit:** `redeemSignupCode` uses `enforceDurableRateLimit` to throttle
  guessing; combined with 60-bit entropy + one-time + expiry, brute force is
  impractical.

### 3.5 Admin invite UI (`employee_form_sheet.dart` + employees feature)

- The invite/create path calls `createEmployeeInvite` (via a new repository
  method / provider) instead of the client-side `repo.addEmployee`. `addEmployee`
  (direct `users.add`) is removed or repurposed to wrap the callable.
- On success, show the returned code in a **copy-to-clipboard dialog**: "Share
  this code with {name}. They'll need it plus their email to sign in." Code shown
  once.
- Pending invites (status `invited`) gain a **Regenerate code** action
  (calls `regenerateSignupCode`, shows the new code dialog).
- Firebase callable responses are cast loosely:
  `(res.data as Map?)?.cast<String,dynamic>()` (CLAUDE.md Android invariant).

### 3.6 Employee signup UI (`create_account_screen.dart` + `auth_service.dart`)

New `auth_service` method (replaces `createEmployeeAccount`), e.g.
`signUpWithCode({email, password, code})`:
1. `register(email, password)` (or adopt an existing account on
   `email-already-in-use` via `signIn`, preserving the current adopt logic).
2. Call the `redeemSignupCode` callable with `code`.
3. **Success** → the account is now active and the user is signed in. Commit
   autofill (`TextInput.finishAutofillContext()`), return success.
4. **Failure** → roll back the freshly-created Auth user (`_rollbackOrFailLoud`)
   or `_signOutQuietly` for an adopted account; throw the typed failure.

Screen changes:
- Add a **Signup code** field (with the standard `LabeledTextField`, a length
  cap in `TextLimits`, and validation). Admin instructs the employee which email
  to use.
- On success, route into the app (the user is an active signed-in employee — the
  normal post-sign-in routing applies); **remove** the "check your email / resend
  verification" state and the `_resendVerification` path.

Typed failures (`lib/features/auth/domain/auth_failure.dart`), surfaced via
`AuthErrorMapper`:
- `AuthFailureInvalidSignupCode` — covers not-found **and** email-mismatch
  (deliberately indistinguishable to avoid leaking that a code is valid for a
  different email). Message: "That code isn't valid. Ask your admin for a new
  one."
- `AuthFailureSignupCodeExpired` — "That code has expired. Ask your admin for a
  new one."
- (Already-used collapses into invalid, since the doc is gone after redemption.)
- Existing `AuthFailureAccountCreationIncomplete` (rollback delete failed) stays.

### 3.7 Login simplification (`login_screen.dart`)

- Remove the `userDoc == null → tryActivateInvitedEmployee → re-check` branch and
  both email-verification sub-branches. After the redesign, a signed-in user
  either has an active `users` doc (proceed) or doesn't (genuine "no profile" →
  sign out). Routine sign-in keeps `_retryOnAuthPropagation` around
  `findUserByUid`.

## 4. What gets deleted

- `resolveMyInvite` (`functions/account.js`) + its `index.js` re-export.
- `EmployeesRepository.findInvitedEmployeeForCurrentUser` + impl + the
  `InvitedEmployeeMatch` type if unused elsewhere.
- `AuthService.createEmployeeAccount` (replaced) and
  `AuthService.tryActivateInvitedEmployee`.
- The `FIXME(pre-deploy)` markers in `account.js` and `auth_service.dart`.
- The `users` self-activation Firestore rule clause.
- Now-orphaned l10n keys for the verification/resend UI (prune in lockstep across
  both ARBs, then `flutter gen-l10n`).

## 5. Migration

Existing `status:'invited'` `users` docs (created the old way) have no
`signupCodes` entry. They can't be redeemed until a code exists. Since a pending
invite has no account yet, the admin simply uses **Regenerate code** on each to
issue one. No data backfill is required; document this in the release notes /
CLAUDE.md. (Optional convenience: a one-off script that mints a code per existing
pending invite — out of scope unless the pending-invite count is large.)

## 6. Security considerations

- The code hash lives only in `signupCodes`, denied to all clients — no
  matching-email read path exposes it (the weakness of the rejected Approach B).
- `redeemSignupCode` requires App Check (post-ship) + auth + rate limiting; the
  email-match check binds a code to its intended person.
- Activation is server-side only (Admin SDK); the client self-activation rule is
  removed, shrinking the trust surface.
- No secret is ever logged; the plaintext code is returned exactly once at
  generation and never persisted (`.claude/rules/security.md`).

## 7. Testing

- **Functions unit** (`functions/test`): `redeemSignupCode` — valid →
  active+claimed+code-deleted; expired; wrong code; email mismatch; already-claimed
  invite. `createEmployeeInvite` — creates both docs + returns a code; duplicate
  email rejected. `regenerateSignupCode` — replaces the prior code.
- **Rules tests:** `signupCodes` denied to clients; users self-activation no
  longer possible.
- **Dart unit** (`auth_service_test`): `signUpWithCode` success (active, signed
  in); redemption-failure rollback deletes the Auth user; adopt path on
  `email-already-in-use`. Update/replace the existing `createEmployeeAccount` /
  `tryActivateInvitedEmployee` tests.
- **Widget:** create-account code field validation + typed-failure banners;
  admin invite code dialog (copy + regenerate). Scale-sweep the create-account
  screen (`auth_screens_scale_sweep_test` pattern).

## 8. Affected files (non-exhaustive)

- `functions/invites.js` (new), `functions/index.js`, `functions/account.js`
  (delete `resolveMyInvite`), `functions/security.js` (reuse).
- `firestore.rules` (signupCodes lockdown; remove self-activation clause).
- `lib/features/auth/services/auth_service.dart`,
  `lib/features/auth/screens/create_account_screen.dart`,
  `lib/features/auth/screens/login_screen.dart`,
  `lib/features/auth/domain/auth_failure.dart`,
  `lib/features/auth/services/auth_error_mapper.dart`.
- `lib/features/employees/data/firebase_employees_repository.dart`,
  `lib/features/employees/domain/employees_repository.dart`,
  `lib/features/employees/widgets/sheets/employee_form_sheet.dart`,
  employees screen (regenerate action).
- `lib/core/validators/text_limits.dart` (code length cap),
  `lib/l10n/app_en.arb` + `app_fr.arb` (new keys, prune verification keys).
- Tests under `test/features/auth`, `test/features/employees`, `functions/test`.

## 9. Out of scope / follow-ups

- Automatic emailing of the code (explicitly rejected — admin shares it).
- A one-off migration script for many pending invites (only if needed).
- Flipping App Check `enforceAppCheck` back to `true` (tracked pre-ship item).

# Simplified sign-in and account setup

**Date:** 2026-08-21
**Status:** SHIPPED. Implemented 2026-08-21 (release 1.48.0+77), backend
deployed the same day at `1c89892a` — plus `229b6e24` hours later, which
restored account creation that deploy had broken. Evidence in the code:
`AuthFailureStartingPasswordReused` in `lib/features/auth/domain/auth_failure.dart`,
the random starting password in `functions/employee_accounts.js`, and no
`email_verified` guard left on `completeEmployeeSetup`. **Backend rollback is
unsafe** — the app build that depends on it is on the App Store.
**Supersedes parts of:** `docs/plans/redesign-subdocs/2026-08-02-p4c-HANDOFF.md`
(the P4c invite/setup flow), and the `email_verified` guard added 2026-08-08.

## Goal

Shorten the path from "an admin created your account" to "you are working in
the app". The app is unlisted and only company employees install it, so the
onboarding ceremony built for a public audience is friction without a
corresponding threat.

Two things come out: the **email-verification step** on `AccountSetupScreen`,
and the **admin toggle** on the create-account sheet. One thing goes in: a
**random per-account starting password**, which is what pays for removing the
verification gate.

## Why the verification step existed, and what replaces it

Every employee account is minted on a shared constant, `Welcome123!`. Between
an admin creating the account and the employee first signing in, anyone who
knows that employee's email address can sign in as them. The `email_verified`
check on `completeEmployeeSetup` (added 2026-08-08) was the only thing stopping
that person from finishing setup and landing `active` — and, if the row was
created with `isAdmin: true`, landing admin, which reads the whole `/clients`
PII collection.

"Unlisted" does not help here. Unlisted limits App Store *discovery*; it gates
neither installation nor authentication.

So the guard cannot simply be deleted. It is replaced by two changes that
between them close the same hole more directly:

1. **The starting password becomes a random per-account secret.** Knowing
   someone's email address is then no longer sufficient to sign in as them.
2. **New accounts are always plain employees.** A pre-empted account can no
   longer be an admin account, so the worst case shrinks from "reads all client
   PII" to "occupies one employee seat".

### Residual risk (accepted)

Whoever holds *both* the email address and the generated password can still
activate the account before the intended employee does. That is a real secret
rather than a value printed in the source, so it is a genuine improvement on
today — but it is not zero. The mitigation is operational and belongs in the
onboarding instructions: **create the account at the moment you hand the
credentials over, not weeks ahead.**

## Scope

### 1. Server — `functions/employee_accounts.js`

- Replace the `DEFAULT_PASSWORD` constant with `generateStartingPassword()`:
  12 characters drawn with `crypto.randomBytes` from a deliberately
  unambiguous alphabet (no `0`/`O`, no `1`/`l`/`I`), because the admin reads it
  aloud. It must contain at least one uppercase, one lowercase and one digit so
  it satisfies the client-side policy below.
- Generate it **once per `createEmployeeAccount` call** and pass the same value
  to `provisionAuthAccount` (new account) and `resetProvisionedPassword`
  (re-provision). Return it in the response, as today.
  The roster's Reset button already routes through this same callable, so reset
  gets a fresh random password with no new plumbing.
- Remove the `email_verified` guard from `completeEmployeeSetup`
  (currently `functions/employee_accounts.js:641`). Everything else on that
  callable stays: the auth check, the matching-doc check, `status == 'invited'`,
  `enforceAppCheck: true`, and the 5-per-15-minute durable rate limit.
- Remove `isAdmin` from `createEmployeeAccount`: drop it from the
  `assertPayloadShape` key set and from `performCreateAccount`'s fields, and
  always write `role: "employee"`. Dropping it from the allowlist means an
  older client that still sends the key gets a clean `invalid-argument`
  rejection rather than silently creating an admin.

### 2. Client — `AccountSetupScreen` and `AuthService`

Delete:

- `lib/features/auth/widgets/account_setup/verify_email_panel.dart`
- `lib/features/auth/widgets/account_setup/signed_in_chip.dart`
- `AuthService.sendVerificationEmail`, `AuthService.refreshEmailVerified`,
  `AuthService.isEmailVerified`
- `AuthFailureEmailNotVerified` (and its `isExpected` and
  `toLocalizedMessageInContext` branches)
- The screen state that drove them: `_emailVerified`, `_isSendingVerification`,
  `_isCheckingVerification`, `_verificationSent`, `_verificationNotice`, plus
  `_sendVerificationEmail()` and `_checkVerification()`.
- `kDefaultStartingPassword`
  (`lib/features/employees/domain/policies/starting_password_policy.dart`, the
  whole file) and the `validation_passwordMustDifferFromStarting` check that
  compared against it. With a random password there is no constant left to
  accidentally re-choose, so the rule has nothing to guard.

  **REVISED same day (deviation 5).** That reasoning holds for *accidental*
  reuse only, and the deletion left a real hole: the employee is looking at
  the starting password while they fill this form, and retyping it is the
  easiest thing to do. It passes — every generated password satisfies
  `AuthValidators.newPassword` by construction, and `updatePassword` accepts
  a no-op — so setup would complete with the account `active` on a credential
  the admin still holds, contradicting the screen's own copy. The rule is
  therefore KEPT, in a form that needs no constant:
  `AuthService._refuseIfStillTheStartingPassword` reauthenticates with the
  typed value and refuses when that succeeds. The ARB key is restored;
  `starting_password_policy.dart` stays deleted.

Change:

- `LockedEmailPanel` loses its `isVerified` parameter — it now says only "you
  are signing in as this address".
- `_isTransitionBusy` collapses to `_isLoading || _isSigningOut`.
- `_finishSetup`'s gate becomes `if (!_consented) return;` and the CTA's
  `onPressed` becomes `_consented ? _finishSetup : null`.
- `PasswordRequirement.symbol` is removed from the enum in
  `lib/core/validators/password_requirements.dart`. The remaining policy is
  8+ characters with an uppercase, a lowercase and a digit. The checklist row
  and the strength meter follow the enum, so both update from that one edit.

Resulting screen: locked email → first name → last name → phone → new password
→ confirm password → consent → Finish. Roughly 622 lines down to ~380.

**`login_screen.dart` is not changed.** It is already email, password,
forgot-password and sign in; there is nothing there worth removing.

### 3. Create sheet — `invite_person_sheet.dart`

- Delete `_accessSection` and the `_isAdmin` field. Move the `WarningNote`
  (`employees_invitedNote`) it held to the end of the details section so the
  advisory survives.
- `_save` passes `role: 'employee'` unconditionally.
- Retire `TourStepId.personAccess`: remove it from `tour_step_id.dart`,
  `tour_definitions.dart`, `tour_step_text.dart`, its `tour_personAccessTitle`
  / `tour_personAccessDesc` ARB pairs, and the ordering assertion in
  `test/features/feature_tour/domain/tour_definitions_test.dart:147`.
  The tour's storage key is `TourForm.invitePerson`, not the step, so removing
  a step does not replay or orphan anyone's tour.
- The **edit sheet's** promote-to-admin toggle
  (`edit_person_sheet.dart`) is deliberately untouched. Making someone an admin
  means creating them normally, letting them set up, then flipping that toggle.

### 4. Roster row — `pending_invite_tile.dart`

The row currently falls back to `kDefaultStartingPassword` when it holds no
re-issued credentials. With a random password there is nothing to fall back to,
and the generated password is deliberately **not** persisted anywhere — a live
plaintext credential must not sit in Firestore where every admin session,
backup and export can read it.

So when `_cached` is null:

- the password line renders masked, with a short hint that Reset password
  issues a new one;
- the Copy pill copies the **email alone**.

Immediately after a create or a reset, `_cached` holds the server-echoed pair
and the row shows and copies both exactly as it does today — which is the
moment that actually matters. Expanding a row still rotates nothing.

### 5. Localization

Removed keys (both ARBs, in lockstep): `auth_emailVerified`,
`auth_sendVerificationEmail`, `auth_resendVerificationEmail`,
`auth_verificationEmailSent`, `auth_emailNotVerifiedYet`,
`validation_passwordMustDifferFromStarting`, `validation_passwordReqSymbol`,
`error_verifyYourEmailBeforeFinishing`, `tour_personAccessTitle` and
`tour_personAccessDesc`.

**`employees_sectionAccess`, `employees_adminAccess` and
`employees_adminAccessDescription` STAY** — the edit sheet's promote toggle
uses all three, and that toggle is deliberately kept. Only the invite sheet's
usage goes.

Added: one key for the masked-password hint on the roster row.

Every added key carries its `@key` block in `app_en.arb`; `flutter gen-l10n`
runs after.

### 6. Documentation

Three files currently assert guarantees that stop being true and must be
rewritten, not merely trimmed:

- `CLAUDE.md` — the invited-account bullets and the `users` read-rule note.
- `.claude/rules/employees.md` — the P4c bullet describes `Welcome123!`, the
  `email_verified` guard, the must-differ check and the hand-mirrored constant
  at length. All four change.
- `.claude/rules/security.md` — the `completeEmployeeSetup` guard-order bullet
  names `email_verified` as an identity guard in the guard chain.

`docs/CLOUD_FUNCTIONS.md` needs `createEmployeeAccount`'s payload updated
(`isAdmin` removed) and `completeEmployeeSetup`'s guard list corrected.

## Testing

Existing tests that must be updated rather than deleted:

- `test/features/auth/screens/account_setup_screen_test.dart` — the
  verification-gate cases go; the consent gate and the keyboard-submit case
  stay. The case at line 230 asserting `kDefaultStartingPassword` is rejected
  is removed with the rule.
- `test/features/auth/services/auth_service_test.dart` — the ordering test
  (`updatePassword` before `completeEmployeeSetup`, and `verifyNever` on a
  thrown `updatePassword`) is unaffected and **must keep passing**; that
  ordering is still the app-layer guarantee.
- `test/features/employees/data/firebase_employees_repository_test.dart` — the
  `createEmployeeAccount` payload assertions drop `isAdmin`.
- `test/features/employees/widgets/cards/pending_invite_tile_test.dart` — the
  literal-password assertion is replaced by a masked-state assertion plus a
  post-reset assertion that the server-echoed password renders.
- `functions/__tests__/employee_accounts.test.js` — the pinned `DEFAULT_PASSWORD`
  literal is replaced by assertions on `generateStartingPassword()`'s shape
  (length, character classes, no ambiguous characters, and that two calls
  differ). Add a case proving `createEmployeeAccount` writes
  `role: "employee"` even when a caller sends `isAdmin: true`.
- `test/features/feature_tour/domain/tour_definitions_test.dart` — the
  `personAccess` ordering assertion goes.

New coverage:

- `completeEmployeeSetup` activates an account whose token carries
  `email_verified: false` (the guard is gone) but still refuses when the doc is
  not `invited`.
- The create and reset paths receive the **same** generated password within one
  call, and different passwords across calls.

## Deployment

Backend deploys before the app build, per `docs/DEPLOYMENT.md` — both callable
payload shapes change.

One known window: after the backend ships and before the new app build does, an
admin on the **old** build who creates an account sees the correct password in
the new-account dialog (it renders the server echo), but that person's roster
row later shows `Welcome123!`, which is wrong. It self-heals when the build
ships. Worth knowing; not worth blocking on.

**SUPERSEDED (deviation 4, 2026-08-21):** this paragraph originally said
`createEmployeeAccount` would REJECT `isAdmin`, so an old admin build's create
sheet would fail while the toggle was still on screen. The key was instead
kept in the `assertPayloadShape` allowlist as **accepted-and-ignored**
(`#compat-1.47.0`), because rejecting it would have broken create AND Reset
password on every un-updated admin device — including the Reset password
button the pre-flight remediation runs on (`docs/DEPLOYMENT.md` §4a).

The real rollout behaviour is therefore the opposite, and is worth stating
plainly: an old admin build's create sheet **succeeds silently** with the
Admin-access toggle switched on, and mints a plain `employee` anyway — no
error, no UI signal. That is the intended outcome (a pre-empted account must
never be an admin one), but an admin using an old build will believe they
created an admin. Promote from the edit sheet after setup, and prefer
shipping the app build promptly so the toggle stops being on screen.

## Out of scope

- The login screen's layout, the forgot-password flow, and the app-lock
  biometric gate.
- The edit sheet's admin toggle.
- Any change to what an `invited` account can read; the rules already grant it
  nothing, and that stays the real containment.

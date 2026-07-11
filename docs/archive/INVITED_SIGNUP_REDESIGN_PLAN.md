# Invited-Employee Signup Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the `resolveMyInvite` pre-verification invite lookup with admin-issued one-time signup codes that authorize signup and activate the account on redemption — resolving the functions deploy blocker.

**Architecture:** A new admin-only `createEmployeeInvite` callable generates a per-invite code, stores only its `sha256` hash in a client-locked `signupCodes/{hash}` collection, and returns the plaintext once. The employee submits email + password + code; `redeemSignupCode` validates server-side (14-day expiry, email must match) and atomically sets the invite `active`. Each callable's security-critical logic is a pure, jest-tested function; the Firestore wiring is verified via the emulator.

**Tech Stack:** Firebase Cloud Functions (Node, jest), Firestore rules, Flutter/Dart (Riverpod, mocktail), `cloud_functions` callables.

**Spec:** `docs/plans/INVITED_SIGNUP_REDESIGN.md`

**Note on test harness:** `functions/` has jest but no `firebase-functions-test` and no existing function tests. This plan unit-tests **pure helpers** (`functions/signup_code_utils.js`) with jest, and verifies the `onCall` + Firestore flow with the emulator. Firestore rules have no automated harness in this repo; rules changes are verified by careful review + emulator.

---

## File Structure

**Create:**
- `functions/signup_code_utils.js` — pure helpers: `generateSignupCode`, `hashSignupCode`, `validateRedemption`, constants. Only `require("crypto")`. Fully unit-testable.
- `functions/invites.js` — the three `onCall` handlers (`createEmployeeInvite`, `regenerateSignupCode`, `redeemSignupCode`). Thin wiring over the pure helpers + Firestore.
- `functions/test/signup_code_utils.test.js` — jest tests for the pure helpers.

**Modify:**
- `functions/index.js` — re-export the three new callables; remove `resolveMyInvite`.
- `functions/account.js` — delete `resolveMyInvite` (and its now-unused FIXME marker).
- `firestore.rules` — lock `signupCodes`; remove the `users` self-activation clause.
- `lib/features/auth/domain/auth_failure.dart` — add `AuthFailureInvalidSignupCode`, `AuthFailureSignupCodeExpired`.
- `lib/features/auth/services/auth_service.dart` — add `signUpWithCode`; remove `createEmployeeAccount` + `tryActivateInvitedEmployee` + FIXME marker.
- `lib/features/employees/data/firebase_employees_repository.dart` + `domain/employees_repository.dart` — add `createEmployeeInvite`, `regenerateSignupCode`, `redeemSignupCode`; remove `findInvitedEmployeeForCurrentUser`, `addEmployee`.
- `lib/features/auth/screens/create_account_screen.dart` — add code field; new flow; remove verification/resend UI.
- `lib/features/auth/screens/login_screen.dart` — remove the activation branch.
- `lib/features/employees/widgets/sheets/employee_form_sheet.dart` + employees screen — call `createEmployeeInvite`, show the code dialog, add a Regenerate-code action.
- `lib/core/validators/text_limits.dart` — add `signupCode` cap.
- `lib/l10n/app_en.arb` + `lib/l10n/app_fr.arb` — add new keys; prune now-unused verification keys.

**Delete (verify zero refs first):** `InvitedEmployeeMatch` type (if unused), the verification-email l10n keys.

---

## Phase A — Cloud Functions: signup codes

### Task 1: Pure signup-code helpers

**Files:**
- Create: `functions/signup_code_utils.js`
- Test: `functions/test/signup_code_utils.test.js`

- [ ] **Step 1: Write the failing tests**

```js
// functions/test/signup_code_utils.test.js
const {
  generateSignupCode,
  hashSignupCode,
  validateRedemption,
  INVITE_CODE_TTL_MS,
} = require("../signup_code_utils");

describe("generateSignupCode", () => {
  test("formats as three dash-separated groups of four", () => {
    expect(generateSignupCode()).toMatch(/^[0-9A-Z]{4}-[0-9A-Z]{4}-[0-9A-Z]{4}$/);
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
  const invite = {status: "invited", uid: "", email: "a@b.com", role: "employee", name: "A"};
  const code = {inviteDocId: "x", email: "a@b.com", expiresAt: future};

  test("ok for a valid, unexpired, matching-email invite", () => {
    expect(validateRedemption({codeData: code, inviteData: invite,
      tokenEmail: "a@b.com", nowMs: 1_500_000})).toEqual({ok: true});
  });
  test("invalid when the code doc is missing", () => {
    expect(validateRedemption({codeData: null, inviteData: invite,
      tokenEmail: "a@b.com", nowMs: 1_500_000})).toEqual({ok: false, reason: "invalid"});
  });
  test("invalid when the invite is already claimed", () => {
    expect(validateRedemption({codeData: code,
      inviteData: {...invite, uid: "u1", status: "active"},
      tokenEmail: "a@b.com", nowMs: 1_500_000})).toEqual({ok: false, reason: "invalid"});
  });
  test("invalid when the token email does not match the invite", () => {
    expect(validateRedemption({codeData: code, inviteData: invite,
      tokenEmail: "other@b.com", nowMs: 1_500_000})).toEqual({ok: false, reason: "invalid"});
  });
  test("expired when past expiresAt", () => {
    expect(validateRedemption({codeData: {...code, expiresAt: past}, inviteData: invite,
      tokenEmail: "a@b.com", nowMs: 1_500_000})).toEqual({ok: false, reason: "expired"});
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd functions && npx jest test/signup_code_utils.test.js`
Expected: FAIL — "Cannot find module '../signup_code_utils'".

- [ ] **Step 3: Implement the pure helpers**

```js
// functions/signup_code_utils.js
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
 * @param {{codeData: ?object, inviteData: ?object, tokenEmail: string,
 *   nowMs: number}} args inputs.
 * @return {{ok: boolean, reason?: string}}
 */
function validateRedemption({codeData, inviteData, tokenEmail, nowMs}) {
  if (!codeData || !inviteData) return {ok: false, reason: "invalid"};
  if (inviteData.status !== "invited" || (inviteData.uid || "") !== "") {
    return {ok: false, reason: "invalid"};
  }
  const inviteEmail = String(inviteData.email || "").trim().toLowerCase();
  const claimEmail = String(tokenEmail || "").trim().toLowerCase();
  if (!claimEmail || inviteEmail !== claimEmail) {
    return {ok: false, reason: "invalid"};
  }
  const expiresAtMs = codeData.expiresAt && typeof codeData.expiresAt.toMillis ===
    "function" ? codeData.expiresAt.toMillis() : 0;
  if (expiresAtMs <= nowMs) return {ok: false, reason: "expired"};
  return {ok: true};
}

module.exports = {
  INVITE_CODE_TTL_MS,
  generateSignupCode,
  hashSignupCode,
  validateRedemption,
};
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd functions && npx jest test/signup_code_utils.test.js`
Expected: PASS (all tests green).

- [ ] **Step 5: Lint + commit**

Run: `cd functions && npm run lint`
Expected: clean (Google ESLint, 80-char).

```bash
git add functions/signup_code_utils.js functions/test/signup_code_utils.test.js
git commit -m "feat(functions): pure signup-code helpers (generate/hash/validate)"
```

---

### Task 2: `invites.js` callables (createEmployeeInvite, regenerateSignupCode, redeemSignupCode)

**Files:**
- Create: `functions/invites.js`

- [ ] **Step 1: Implement the callables**

```js
// functions/invites.js
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");
const {
  assertPayloadShape, requireString, assertAdmin, enforceDurableRateLimit,
} = require("./security");
const {
  INVITE_CODE_TTL_MS, generateSignupCode, hashSignupCode, validateRedemption,
} = require("./signup_code_utils");

// Mirrors account.js: auth-sensitive redemption is throttled per uid.
const REDEEM_RATE_MAX = 5;
const REDEEM_RATE_WINDOW_MS = 15 * 60 * 1000;

// Optional trimmed string with a length + control-char guard (phone may be
// empty; requireString rejects empty, so read it leniently here).
function optionalString(data, key, maxLen) {
  const v = typeof data?.[key] === "string" ? data[key].trim() : "";
  if (v.length > maxLen) throw new HttpsError("invalid-argument", `invalid-${key}`);
  return v;
}

// TODO(pre-ship): set enforceAppCheck:true once the app ships through the
// stores and Play Integrity can mint verified App Check tokens.
const APP_CHECK = {enforceAppCheck: false};

const createEmployeeInvite = onCall(APP_CHECK, async (req) => {
  if (!req.auth || !req.auth.uid) {
    throw new HttpsError("unauthenticated", "auth-required");
  }
  await assertAdmin(req.auth.uid);
  assertPayloadShape(req.data, new Set(["name", "email", "phone", "colorValue"]));
  const name = requireString(req.data, "name", 100);
  const email = requireString(req.data, "email", 254).toLowerCase();
  const phone = optionalString(req.data, "phone", 40);
  const colorValue = requireString(req.data, "colorValue", 40);

  const db = getFirestore();
  const dup = await db.collection("users")
      .where("email", "==", email).limit(1).get();
  if (!dup.empty) throw new HttpsError("already-exists", "email-exists");

  const code = generateSignupCode();
  const inviteRef = db.collection("users").doc();
  const codeRef = db.collection("signupCodes").doc(hashSignupCode(code));
  const expiresAt = new Date(Date.now() + INVITE_CODE_TTL_MS);
  await db.runTransaction(async (tx) => {
    tx.set(inviteRef, {
      name, email, phone, colorValue,
      role: "employee", status: "invited", uid: "",
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    tx.set(codeRef, {
      inviteDocId: inviteRef.id, email, expiresAt,
      createdAt: FieldValue.serverTimestamp(),
    });
  });
  return {code};
});

const regenerateSignupCode = onCall(APP_CHECK, async (req) => {
  if (!req.auth || !req.auth.uid) {
    throw new HttpsError("unauthenticated", "auth-required");
  }
  await assertAdmin(req.auth.uid);
  assertPayloadShape(req.data, new Set(["inviteDocId"]));
  const inviteDocId = requireString(req.data, "inviteDocId", 200);

  const db = getFirestore();
  const inviteSnap = await db.collection("users").doc(inviteDocId).get();
  const invite = inviteSnap.exists ? inviteSnap.data() : null;
  if (!invite || invite.status !== "invited") {
    throw new HttpsError("failed-precondition", "not-a-pending-invite");
  }
  const prior = await db.collection("signupCodes")
      .where("inviteDocId", "==", inviteDocId).get();
  const code = generateSignupCode();
  const batch = db.batch();
  prior.forEach((d) => batch.delete(d.ref));
  batch.set(db.collection("signupCodes").doc(hashSignupCode(code)), {
    inviteDocId, email: invite.email || "",
    expiresAt: new Date(Date.now() + INVITE_CODE_TTL_MS),
    createdAt: FieldValue.serverTimestamp(),
  });
  await batch.commit();
  return {code};
});

const redeemSignupCode = onCall(APP_CHECK, async (req) => {
  if (!req.auth || !req.auth.uid) {
    throw new HttpsError("unauthenticated", "auth-required");
  }
  assertPayloadShape(req.data, new Set(["code"]));
  const code = requireString(req.data, "code", 32);
  const tokenEmail = req.auth.token && req.auth.token.email;
  if (typeof tokenEmail !== "string" || tokenEmail === "") {
    throw new HttpsError("failed-precondition", "no-email-claim");
  }
  await enforceDurableRateLimit(
      "redeemSignupCode", req.auth.uid, REDEEM_RATE_MAX, REDEEM_RATE_WINDOW_MS);

  const db = getFirestore();
  const codeRef = db.collection("signupCodes").doc(hashSignupCode(code));
  const outcome = await db.runTransaction(async (tx) => {
    const codeSnap = await tx.get(codeRef);
    const codeData = codeSnap.exists ? codeSnap.data() : null;
    let inviteData = null;
    let inviteRef = null;
    if (codeData) {
      inviteRef = db.collection("users").doc(codeData.inviteDocId);
      const inviteSnap = await tx.get(inviteRef);
      inviteData = inviteSnap.exists ? inviteSnap.data() : null;
    }
    const v = validateRedemption({
      codeData, inviteData, tokenEmail, nowMs: Date.now(),
    });
    if (!v.ok) return v;
    tx.update(inviteRef, {
      uid: req.auth.uid, status: "active",
      updatedAt: FieldValue.serverTimestamp(),
    });
    tx.delete(codeRef);
    return {ok: true, role: inviteData.role || "employee", name: inviteData.name || ""};
  });
  if (!outcome.ok) {
    if (outcome.reason === "expired") {
      throw new HttpsError("failed-precondition", "code-expired");
    }
    throw new HttpsError("invalid-argument", "invalid-code");
  }
  return {role: outcome.role, name: outcome.name};
});

module.exports = {createEmployeeInvite, regenerateSignupCode, redeemSignupCode};
```

- [ ] **Step 2: Lint**

Run: `cd functions && npm run lint`
Expected: clean. Fix any 80-char/JSDoc violations.

- [ ] **Step 3: Commit**

```bash
git add functions/invites.js
git commit -m "feat(functions): createEmployeeInvite/regenerate/redeemSignupCode callables"
```

---

### Task 3: Wire into index.js; delete resolveMyInvite

**Files:**
- Modify: `functions/index.js`
- Modify: `functions/account.js`

- [ ] **Step 1: Add the invites re-exports; drop resolveMyInvite**

In `functions/index.js`, after `const account = require("./account");` add:
```js
const invites = require("./invites");
```
Remove the line `exports.resolveMyInvite = account.resolveMyInvite;` and add:
```js
exports.createEmployeeInvite = invites.createEmployeeInvite;
exports.regenerateSignupCode = invites.regenerateSignupCode;
exports.redeemSignupCode = invites.redeemSignupCode;
```

- [ ] **Step 2: Delete `resolveMyInvite` from account.js**

Remove the entire `const resolveMyInvite = onCall(...)` block (its FIXME marker, the `email_verified` gate, and the body) and its entry in `account.js`'s `module.exports`. If `AUTH_RATE_MAX`/`AUTH_RATE_WINDOW_MS` are now used only by `deleteAccount`, leave them. Verify nothing else in `account.js` references `resolveMyInvite`.

- [ ] **Step 3: Lint + verify no dangling references**

Run: `cd functions && npm run lint`
Run: `cd functions && grep -rn "resolveMyInvite" . --exclude-dir=node_modules` → expect no matches.
Expected: lint clean, grep empty.

- [ ] **Step 4: Emulator smoke (manual)**

Run the Firestore + Functions emulator (`firebase emulators:start --only functions,firestore`). With a seeded admin in `usersByUid`, call `createEmployeeInvite` (expect a code + an `invited` users doc + a `signupCodes` doc), then `redeemSignupCode` as a signed-in user whose token email matches (expect the invite flips to `active`, the code doc is deleted). Note results.

- [ ] **Step 5: Commit**

```bash
git add functions/index.js functions/account.js
git commit -m "feat(functions): wire signup-code callables; remove resolveMyInvite"
```

---

## Phase B — Firestore rules

### Task 4: Lock signupCodes; remove client self-activation

**Files:**
- Modify: `firestore.rules`

- [ ] **Step 1: Add the signupCodes lockdown**

Add a match block (next to `rateLimits`):
```
match /signupCodes/{codeHash} {
  allow read, write: if false; // Cloud Functions (Admin SDK) only.
}
```

- [ ] **Step 2: Remove the users self-activation clause**

In the `users` update rule, remove the clause that allowed a user to flip their own invited doc to `active` when `request.auth.token.email_verified == true`. Activation is now exclusively server-side via `redeemSignupCode`. Keep all other `users` update clauses (admin writes, profile edits) intact. Read the surrounding rule carefully and confirm no other client flow depended on that clause.

- [ ] **Step 3: Verify (emulator/manual)**

In the emulator, confirm: a client read/write to `signupCodes` is denied; a client can no longer update its own `users` doc `status` to `active`. Document the checks.

- [ ] **Step 4: Commit**

```bash
git add firestore.rules
git commit -m "feat(rules): lock signupCodes; remove client self-activation"
```

---

## Phase C — Dart data + service layer

### Task 5: New AuthFailure types + l10n

**Files:**
- Modify: `lib/features/auth/domain/auth_failure.dart`
- Modify: `lib/l10n/app_en.arb`, `lib/l10n/app_fr.arb`
- Test: `test/features/auth/auth_failure_test.dart` (create if absent)

- [ ] **Step 1: Add the two l10n keys (both ARBs, EN gets @key blocks)**

In `lib/l10n/app_en.arb`:
```json
"error_thatCodeIsntValidAskYourAdmin": "That code isn't valid. Ask your admin for a new one.",
"@error_thatCodeIsntValidAskYourAdmin": { "description": "Shown when a signup code is wrong, already used, or for a different email." },
"error_thatCodeHasExpiredAskYourAdmin": "That code has expired. Ask your admin for a new one.",
"@error_thatCodeHasExpiredAskYourAdmin": { "description": "Shown when a signup code is past its expiry." }
```
In `lib/l10n/app_fr.arb` add the French strings (same keys, no @blocks):
```json
"error_thatCodeIsntValidAskYourAdmin": "Ce code n'est pas valide. Demandez-en un nouveau à votre administrateur.",
"error_thatCodeHasExpiredAskYourAdmin": "Ce code a expiré. Demandez-en un nouveau à votre administrateur."
```

- [ ] **Step 2: Run gen-l10n**

Run: `flutter gen-l10n`
Expected: succeeds; `lib/l10n/.gen/untranslated.json` shows no drift for the new keys.

- [ ] **Step 3: Write the failing test**

```dart
// test/features/auth/auth_failure_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/features/auth/domain/auth_failure.dart';
import 'package:scheduling/l10n/l10n.dart';

void main() {
  Future<String> messageFor(WidgetTester tester, AuthFailure f) async {
    late String msg;
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(builder: (c) {
        msg = f.toLocalizedMessage(c);
        return const SizedBox();
      }),
    ));
    return msg;
  }

  testWidgets('invalid signup code message', (t) async {
    expect(await messageFor(t, const AuthFailureInvalidSignupCode()),
        contains("isn't valid"));
  });
  testWidgets('expired signup code message', (t) async {
    expect(await messageFor(t, const AuthFailureSignupCodeExpired()),
        contains('expired'));
  });
}
```

Run: `flutter test test/features/auth/auth_failure_test.dart`
Expected: FAIL — types undefined.

- [ ] **Step 4: Add the failure types**

In `lib/features/auth/domain/auth_failure.dart`, after `AuthFailureNotAuthorized`:
```dart
class AuthFailureInvalidSignupCode extends AuthFailure {
  const AuthFailureInvalidSignupCode();
  @override
  String toLocalizedMessageInContext(BuildContext c, AuthErrorContext _) =>
      c.l10n.error_thatCodeIsntValidAskYourAdmin;
}

class AuthFailureSignupCodeExpired extends AuthFailure {
  const AuthFailureSignupCodeExpired();
  @override
  String toLocalizedMessageInContext(BuildContext c, AuthErrorContext _) =>
      c.l10n.error_thatCodeHasExpiredAskYourAdmin;
}
```

- [ ] **Step 5: Run test + analyze**

Run: `flutter test test/features/auth/auth_failure_test.dart` → PASS
Run: `flutter analyze` → No issues.

- [ ] **Step 6: Commit**

```bash
git add lib/features/auth/domain/auth_failure.dart lib/l10n/app_en.arb lib/l10n/app_fr.arb test/features/auth/auth_failure_test.dart
git commit -m "feat(auth): AuthFailureInvalidSignupCode + SignupCodeExpired"
```

---

### Task 6: Repository — invite + redeem callables

**Files:**
- Modify: `lib/features/employees/domain/employees_repository.dart`
- Modify: `lib/features/employees/data/firebase_employees_repository.dart`
- Test: `test/features/employees/firebase_employees_repository_test.dart` (extend; create if absent)

- [ ] **Step 1: Update the domain interface**

In `employees_repository.dart`: remove `addEmployee(...)` and `findInvitedEmployeeForCurrentUser()`; add:
```dart
/// Creates an invite via the createEmployeeInvite callable; returns the
/// one-time signup code to show the admin once.
Future<String> createEmployeeInvite({
  required String name,
  required String email,
  required String phone,
  required String colorValue,
});

/// Issues a fresh code for a pending invite; returns it.
Future<String> regenerateSignupCode(String inviteDocId);

/// Redeems a signup code for the current user (activates the invite).
Future<void> redeemSignupCode(String code);
```
Remove the `InvitedEmployeeMatch` class if no longer referenced anywhere (grep first).

- [ ] **Step 2: Write the failing tests**

```dart
// in firebase_employees_repository_test.dart
test('createEmployeeInvite returns the code from the callable', () async {
  when(() => functions.httpsCallable('createEmployeeInvite'))
      .thenReturn(callable);
  when(() => callable.call<dynamic>(any()))
      .thenAnswer((_) async => fakeResult({'code': 'K7Q2-9MZ4-XR8T'}));
  final code = await repo.createEmployeeInvite(
    name: 'A', email: 'A@B.com', phone: '', colorValue: '1');
  expect(code, 'K7Q2-9MZ4-XR8T');
  final captured = verify(() => callable.call<dynamic>(captureAny())).captured.single;
  expect((captured as Map).cast<String, dynamic>()['email'], 'a@b.com');
});

test('createEmployeeInvite maps email-exists to EmployeesFailureEmailAlreadyExists',
    () async {
  when(() => functions.httpsCallable('createEmployeeInvite')).thenReturn(callable);
  when(() => callable.call<dynamic>(any())).thenThrow(
      FirebaseFunctionsException(message: 'email-exists', code: 'already-exists'));
  expect(() => repo.createEmployeeInvite(
        name: 'A', email: 'a@b.com', phone: '', colorValue: '1'),
      throwsA(isA<EmployeesFailureEmailAlreadyExists>()));
});

test('redeemSignupCode calls the callable with the code', () async {
  when(() => functions.httpsCallable('redeemSignupCode')).thenReturn(callable);
  when(() => callable.call<dynamic>(any()))
      .thenAnswer((_) async => fakeResult({'role': 'employee', 'name': 'A'}));
  await repo.redeemSignupCode('K7Q2-9MZ4-XR8T');
  final captured = verify(() => callable.call<dynamic>(captureAny())).captured.single;
  expect((captured as Map).cast<String, dynamic>()['code'], 'K7Q2-9MZ4-XR8T');
});
```
Provide `fakeResult` returning a stub whose `.data` is the map (mocktail `HttpsCallableResult` mock). Mirror the existing callable-mock setup used elsewhere in the repo tests; `FirebaseFunctions`/`HttpsCallable`/`HttpsCallableResult` mocks register with `registerFallbackValue` as needed.

Run: `flutter test test/features/employees/firebase_employees_repository_test.dart`
Expected: FAIL — methods undefined.

- [ ] **Step 3: Implement the methods**

In `firebase_employees_repository.dart` (replace `addEmployee` + `findInvitedEmployeeForCurrentUser`):
```dart
@override
Future<String> createEmployeeInvite({
  required String name,
  required String email,
  required String phone,
  required String colorValue,
}) async {
  try {
    final res = await _functions.httpsCallable('createEmployeeInvite').call<dynamic>({
      'name': name.trim(),
      'email': email.trim().toLowerCase(),
      'phone': phone.trim(),
      'colorValue': colorValue,
    });
    final data = (res.data as Map?)?.cast<String, dynamic>();
    final code = data?['code'] as String?;
    if (code == null || code.isEmpty) {
      throw const EmployeesFailureUnknown();
    }
    return code;
  } on FirebaseFunctionsException catch (e) {
    if (e.message == 'email-exists') {
      throw const EmployeesFailureEmailAlreadyExists();
    }
    rethrow;
  }
}

@override
Future<String> regenerateSignupCode(String inviteDocId) async {
  final res = await _functions
      .httpsCallable('regenerateSignupCode')
      .call<dynamic>({'inviteDocId': inviteDocId});
  final data = (res.data as Map?)?.cast<String, dynamic>();
  final code = data?['code'] as String?;
  if (code == null || code.isEmpty) throw const EmployeesFailureUnknown();
  return code;
}

@override
Future<void> redeemSignupCode(String code) async {
  await _functions.httpsCallable('redeemSignupCode').call<dynamic>({'code': code});
}
```
If `EmployeesFailureUnknown` does not exist, add it to the `EmployeesFailure` family (mirror an existing variant) or reuse an existing generic variant — check `lib/features/employees/domain/employees_failure.dart` first and use what's there.

- [ ] **Step 4: Run tests + analyze**

Run: `flutter test test/features/employees/firebase_employees_repository_test.dart` → PASS
Run: `flutter analyze` → expect errors only at the now-stale `addEmployee`/`findInvitedEmployeeForCurrentUser` call sites (fixed in later tasks). Note them.

- [ ] **Step 5: Commit**

```bash
git add lib/features/employees/domain/employees_repository.dart lib/features/employees/data/firebase_employees_repository.dart test/features/employees/firebase_employees_repository_test.dart
git commit -m "feat(employees): invite/redeem signup-code repository methods"
```

---

### Task 7: AuthService — signUpWithCode

**Files:**
- Modify: `lib/features/auth/services/auth_service.dart`
- Test: `test/features/auth/services/auth_service_test.dart`

- [ ] **Step 1: Write the failing tests**

Replace the `createEmployeeAccount` test group with `signUpWithCode` cases:
```dart
group('signUpWithCode', () {
  test('redeems the code after registering (active, signed in)', () async {
    when(() => auth.createUserWithEmailAndPassword(
        email: any(named: 'email'), password: any(named: 'password')))
        .thenAnswer((_) async => credential);
    when(() => employees.redeemSignupCode(any())).thenAnswer((_) async {});

    await service.signUpWithCode(
        email: 'a@b.com', password: 'pw123456', code: 'K7Q2-9MZ4-XR8T');

    verify(() => employees.redeemSignupCode('K7Q2-9MZ4-XR8T')).called(1);
  });

  test('maps invalid-code to AuthFailureInvalidSignupCode and rolls back', () async {
    when(() => auth.createUserWithEmailAndPassword(
        email: any(named: 'email'), password: any(named: 'password')))
        .thenAnswer((_) async => credential);
    when(() => employees.redeemSignupCode(any())).thenThrow(
        FirebaseFunctionsException(message: 'invalid-code', code: 'invalid-argument'));
    when(() => user.delete()).thenAnswer((_) async {});

    await expectLater(
        service.signUpWithCode(email: 'a@b.com', password: 'pw123456', code: 'bad'),
        throwsA(isA<AuthFailureInvalidSignupCode>()));
    verify(() => user.delete()).called(1);
  });

  test('maps code-expired to AuthFailureSignupCodeExpired', () async {
    when(() => auth.createUserWithEmailAndPassword(
        email: any(named: 'email'), password: any(named: 'password')))
        .thenAnswer((_) async => credential);
    when(() => employees.redeemSignupCode(any())).thenThrow(
        FirebaseFunctionsException(message: 'code-expired', code: 'failed-precondition'));
    when(() => user.delete()).thenAnswer((_) async {});

    await expectLater(
        service.signUpWithCode(email: 'a@b.com', password: 'pw', code: 'x'),
        throwsA(isA<AuthFailureSignupCodeExpired>()));
  });
});
```
Remove the old `createEmployeeAccount` and `tryActivateInvitedEmployee` groups. Register `FirebaseFunctionsException` fallback if mocktail needs it.

Run: `flutter test test/features/auth/services/auth_service_test.dart`
Expected: FAIL — `signUpWithCode` undefined.

- [ ] **Step 2: Implement signUpWithCode; remove old methods**

In `auth_service.dart`, replace `createEmployeeAccount` with:
```dart
/// Invited-employee signup. Registers (or adopts an existing account), then
/// redeems the admin-issued one-time code, which activates the account
/// server-side. On redemption failure the freshly-created Auth user is rolled
/// back so no orphan is left.
Future<void> signUpWithCode({
  required String email,
  required String password,
  required String code,
}) async {
  final normalizedEmail = email.trim().toLowerCase();
  UserCredential credential;
  var freshlyCreated = true;
  try {
    credential = await register(email: normalizedEmail, password: password);
  } on FirebaseAuthException catch (e) {
    if (e.code != 'email-already-in-use') rethrow;
    credential = await signIn(email: normalizedEmail, password: password);
    freshlyCreated = false;
  }

  try {
    await _employees.redeemSignupCode(code.trim());
  } catch (e, st) {
    _logger.warn('signUpWithCode: redeemSignupCode failed', e, st);
    final failure = _mapRedemptionError(e);
    if (freshlyCreated) {
      await _rollbackOrFailLoud(credential, reason: 'code-redemption-failed');
    } else {
      await _signOutQuietly();
    }
    throw failure;
  }
}

AuthFailure _mapRedemptionError(Object e) {
  if (e is FirebaseFunctionsException) {
    switch (e.message) {
      case 'code-expired':
        return const AuthFailureSignupCodeExpired();
      case 'invalid-code':
        return const AuthFailureInvalidSignupCode();
    }
    if (e.code == 'unavailable' || e.code == 'deadline-exceeded') {
      return const AuthFailureNetwork();
    }
  }
  return const AuthFailureUnknown();
}
```
Delete `tryActivateInvitedEmployee` and the `FIXME(pre-deploy)` marker. Keep `_rollbackOrFailLoud`, `_signOutQuietly`, `resendVerificationEmail` only if still referenced (resend is no longer used — see Task 8/9; remove if unreferenced). Add the `cloud_functions` import for `FirebaseFunctionsException` if not already present.

- [ ] **Step 3: Run tests + analyze**

Run: `flutter test test/features/auth/services/auth_service_test.dart` → PASS
Run: `flutter analyze` → expect stale call-site errors in `create_account_screen`/`login_screen` (next tasks). Note them.

- [ ] **Step 4: Commit**

```bash
git add lib/features/auth/services/auth_service.dart test/features/auth/services/auth_service_test.dart
git commit -m "feat(auth): signUpWithCode replaces createEmployeeAccount"
```

---

## Phase D — Dart UI

### Task 8: create_account_screen — code field + new flow

**Files:**
- Modify: `lib/features/auth/screens/create_account_screen.dart`
- Modify: `lib/core/validators/text_limits.dart`
- Modify: `lib/l10n/app_en.arb`, `lib/l10n/app_fr.arb`
- Test: `test/features/auth/screens/create_account_screen_test.dart` (extend; create if absent)

- [ ] **Step 1: Add the code-field l10n keys + TextLimits cap**

`app_en.arb`: `auth_signupCode` = "Signup code", `validation_pleaseEnterYourSignupCode` = "Please enter your signup code." (+ `@` blocks). Add French equivalents. Run `flutter gen-l10n`.
In `text_limits.dart` add `static const int signupCode = 32;`.

- [ ] **Step 2: Write the failing widget test**

```dart
testWidgets('shows an error when the signup code is invalid', (tester) async {
  // Pump CreateAccountScreen with a fake AuthService whose signUpWithCode
  // throws AuthFailureInvalidSignupCode; enter valid email/password + a code,
  // tap create, and assert the localized "isn't valid" banner appears.
  // (Mirror the harness in the existing auth screen tests: ProviderScope
  // overrides for authServiceProvider, localization delegates, secure-storage
  // mock init.)
});
```
Fill the body following the existing auth-screen test harness in `test/features/auth/screens/`. 
Run it → FAIL (no code field yet).

- [ ] **Step 3: Implement the field + flow**

- Add `final _codeController = TextEditingController();` (dispose it).
- Add a `LabeledTextField` for the code below the password field:
```dart
LabeledTextField(
  controller: _codeController,
  label: context.l10n.auth_signupCode,
  maxLength: TextLimits.signupCode,
  textInputAction: TextInputAction.done,
  errorText: _submitted ? _errors['code'] : null,
),
```
- In `_validate()`, require a non-empty code (`_errors['code'] = ...pleaseEnterYourSignupCode` when blank).
- Replace the `_createAccount` body's service call:
```dart
await _authService.signUpWithCode(
  email: _emailController.text,
  password: _passwordController.text,
  code: _codeController.text,
);
TextInput.finishAutofillContext();
if (!mounted) return;
// Account is active and signed in — route into the app exactly as the
// successful sign-in path does (mirror login_screen's post-sign-in
// Navigator call / AppRoutes destination).
```
- Remove the `_created` "check your email" state, the `_resendVerification` method, the resend button, and the related `_isResending`/`_resendFailed`/`_resendMessage`/`_restartTick` state.
- On failure, keep the existing `catch` → `AuthErrorMapper.map(error).toLocalizedMessageInContext(context, AuthErrorContext.register)` banner (it passes `AuthFailureInvalidSignupCode`/`Expired` through unchanged).

(Read `login_screen.dart`'s post-sign-in navigation and reuse the exact route/Navigator call so an active signed-in user lands on the same home screen.)

- [ ] **Step 4: Run test + analyze**

Run: `flutter test test/features/auth/screens/create_account_screen_test.dart` → PASS
Run: `flutter analyze` → clean for this file.

- [ ] **Step 5: Commit**

```bash
git add lib/features/auth/screens/create_account_screen.dart lib/core/validators/text_limits.dart lib/l10n/app_en.arb lib/l10n/app_fr.arb test/features/auth/screens/create_account_screen_test.dart
git commit -m "feat(auth): signup code field + activate-on-redeem flow"
```

---

### Task 9: employee_form_sheet — create invite via callable + show code dialog

**Files:**
- Modify: `lib/features/employees/widgets/sheets/employee_form_sheet.dart`
- Modify: `lib/l10n/app_en.arb`, `lib/l10n/app_fr.arb`
- Test: extend the employees widget tests.

- [ ] **Step 1: Add dialog l10n keys**

`app_en.arb`: `employees_signupCodeTitle` = "Signup code", `employees_shareThisCodeWith` = "Share this code with {name}. They'll need it and their email to sign in." (placeholder `name`, String), `employees_copyCode` = "Copy code", `common_copied` = "Copied". Add `@` blocks (with the typed `name` placeholder) + French. `flutter gen-l10n`.

- [ ] **Step 2: Replace the invite write with the callable + dialog**

In the non-edit branch, replace `repo.addEmployee(...)` with:
```dart
final code = await repo.createEmployeeInvite(
  name: name, email: email, phone: phone, colorValue: colorValue,
);
if (!mounted) return;
Navigator.pop(context, true);
await showSignupCodeDialog(context, name: name, code: code);
```
Add a `showSignupCodeDialog` helper (in the employees `widgets/` dir) that shows the code in a selectable, monospace `Text` with a copy-to-clipboard button (`Clipboard.setData`) and an OK button. Keep the existing `EmployeesFailureEmailAlreadyExists` → field-error handling in the `catch`.

- [ ] **Step 3: Widget test**

Add a test: tapping invite with a fake repo returning a code pops the sheet and shows the code dialog containing the code text. Run → iterate to PASS.

- [ ] **Step 4: Analyze + commit**

Run: `flutter analyze` → clean.
```bash
git add lib/features/employees/widgets/sheets/employee_form_sheet.dart lib/features/employees/widgets/ lib/l10n/app_en.arb lib/l10n/app_fr.arb test/features/employees/
git commit -m "feat(employees): create invite via callable; show signup-code dialog"
```

---

### Task 10: Regenerate-code action on a pending invite

**Files:**
- Modify: the employee detail/list surface that shows a pending invite (e.g. `lib/features/employees/widgets/views/employee_details_view.dart` or the employees screen action menu).
- Test: widget test for the action.

- [ ] **Step 1: Add the action**

For an employee with `status == 'invited'`, add a "Regenerate code" action (menu item / button) that calls `ref.read(employeesRepositoryProvider).regenerateSignupCode(employee.id)` (guarded by a busy flag per the CLAUDE.md submit/save reentrancy rule), then shows the same `showSignupCodeDialog`. On error, surface via `composeErrorNotice(context, intro:, tag: 'EMP-CODE', error:)` and a matching `logger.warn('EMP-CODE ...')` (add an `error_introRegenerateCode` l10n key per the error-handling rule).

- [ ] **Step 2: Widget test → PASS, analyze clean, commit**

```bash
git add lib/features/employees/ lib/l10n/app_en.arb lib/l10n/app_fr.arb test/features/employees/
git commit -m "feat(employees): regenerate signup code for a pending invite"
```

---

### Task 11: login_screen — remove the activation branch

**Files:**
- Modify: `lib/features/auth/screens/login_screen.dart`
- Test: `test/features/auth/screens/login_screen_test.dart`

- [ ] **Step 1: Simplify the post-sign-in path**

Remove the `if (userDoc == null) { tryActivateInvitedEmployee; re-find }` block and both email-verification sub-branches. After `findUserByUid`: if `userDoc == null`, sign out and show `error_noUserProfileFoundForThisAccount` (single branch — verification no longer exists). Keep `_retryOnAuthPropagation` around `findUserByUid`. Remove any now-unused `resendVerificationEmail` call here.

- [ ] **Step 2: Update tests**

Adjust `login_screen_test.dart`: drop the activation/verification expectations; assert a signed-in user with an active doc proceeds, and a no-doc user is signed out with the no-profile message. Run → PASS.

- [ ] **Step 3: Analyze + commit**

```bash
git add lib/features/auth/screens/login_screen.dart test/features/auth/screens/login_screen_test.dart
git commit -m "refactor(auth): drop invite-activation branch from sign-in"
```

---

## Phase E — Cleanup, docs, verification

### Task 12: Prune dead code + l10n; update docs

**Files:**
- `lib/l10n/app_en.arb`, `lib/l10n/app_fr.arb`
- `CLAUDE.md`, `docs/audits/AUDIT_FOLLOWUPS.md`, `docs/ARCHITECTURE.md`

- [ ] **Step 1: Remove now-unused verification l10n keys**

Grep each candidate key for `context.l10n.<key>` usage across `lib/`; remove only those with zero references (likely `auth_resendVerificationEmail`, `auth_verificationEmailSentCheckInboxAndSpam`, `auth_verificationEmailResentCheckInboxAndSpam`, `auth_pleaseVerifyYourEmailBeforeSigningIn`). Remove from **both** ARBs (and the `@` block in EN) in lockstep. Keep `error_noUserProfileFoundForThisAccount` (still used). Run `flutter gen-l10n`; check `untranslated.json` shows no drift.

- [ ] **Step 2: Remove any dead `InvitedEmployeeMatch` / `resendVerificationEmail`**

Grep `InvitedEmployeeMatch` and `resendVerificationEmail`; delete if unreferenced.

- [ ] **Step 3: Update docs**

- `CLAUDE.md` "Employee activation flow" invariant: rewrite to describe the new flow (admin `createEmployeeInvite` issues a one-time code shared out-of-band; `redeemSignupCode` activates server-side; no email verification; `signupCodes` collection is Cloud-Functions-only). Remove the `resolveMyInvite` pre-deploy blocker note. Update the Cloud Functions section's function list.
- `docs/audits/AUDIT_FOLLOWUPS.md`: mark §4 done, pointing to the shipped design + this plan.
- `docs/ARCHITECTURE.md`: update the auth/onboarding flow prose and the Cloud Functions list (drop `resolveMyInvite`; add the three new callables + the `signupCodes` collection in the data model).

- [ ] **Step 4: Commit**

```bash
git add lib/l10n/ CLAUDE.md docs/audits/AUDIT_FOLLOWUPS.md docs/ARCHITECTURE.md
git commit -m "chore: prune verification keys; document signup-code flow"
```
(CLAUDE.md is gitignored here, so it won't appear in the commit — that's expected; it remains a local-only update.)

---

### Task 13: Full verification

- [ ] **Step 1: Functions**

Run: `cd functions && npm run lint` → clean
Run: `cd functions && npx jest` → all green

- [ ] **Step 2: Dart**

Run: `flutter gen-l10n` → clean
Run: `flutter analyze` → **No issues found**
Run: `flutter test` → all green (note the new total)

- [ ] **Step 3: Emulator end-to-end (manual)**

With the emulator: admin creates an invite (code shown) → new user registers with that email + code → account becomes active and lands in the app → a second redemption of the same code fails ("invalid"). Try an expired code (seed `expiresAt` in the past) → "expired". Document results.

- [ ] **Step 4: Final commit (if any residual fixes)**

```bash
git add -A
git commit -m "test: full verification for signup-code redesign"
```

---

## Self-Review (completed by plan author)

**Spec coverage:** §3.1 data model → Tasks 2,4. §3.2 callables → Tasks 1–3. §3.3 rules → Task 4. §3.4 format/expiry/rate-limit → Tasks 1,2. §3.5 admin UI → Tasks 9,10. §3.6 employee UI + failures → Tasks 5,7,8. §3.7 login → Task 11. §4 deletions → Tasks 3,7,11,12. §5 migration (regenerate) → Task 10. §7 tests → throughout. All sections covered.

**Type consistency:** `generateSignupCode`/`hashSignupCode`/`validateRedemption` signatures match between `signup_code_utils.js`, its tests, and `invites.js`. Repo method names (`createEmployeeInvite`, `regenerateSignupCode`, `redeemSignupCode`) are identical in the domain interface, impl, service, and UI. Failure types (`AuthFailureInvalidSignupCode`, `AuthFailureSignupCodeExpired`) consistent across definition, mapper, and tests. Callable names match between Dart (`httpsCallable('...')`) and `index.js` exports.

**Open verifications flagged inline (not placeholders):** exact post-sign-in navigation to mirror in Task 8; presence of an `EmployeesFailureUnknown` variant in Task 6; the precise `users` self-activation clause to remove in Task 4 — each task says to read the specific file and reuse what's there.

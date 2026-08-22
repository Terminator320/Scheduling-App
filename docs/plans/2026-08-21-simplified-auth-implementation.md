# Simplified Sign-in and Account Setup — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the email-verification step from employee account setup and the
admin toggle from account creation, replacing the shared starting password
`Welcome123!` with a random per-account one.

**Architecture:** The verification gate exists only because every account is
minted on a password every admin knows. Make the starting password an
unguessable per-account secret and the gate has nothing left to defend, so it
can be deleted along with the client UI, the `AuthService` API, the typed
failure and the "must differ from the starting password" validation rule. New
accounts are additionally forced to `role: "employee"`, so a pre-empted account
can never be an admin one.

**Tech Stack:** Flutter/Dart 3.10.7 (Riverpod 3, `flutter_test` + `mocktail`),
Node.js 24 Cloud Functions (`firebase-functions` v2 `onCall`, Jest 29),
`gen_l10n` ARB localization.

**Spec:** `docs/plans/2026-08-21-simplified-auth-design.md`

---

## Deviations from the spec (decided while writing this plan)

Four things the spec did not resolve, decided here rather than left open.
(Deviation 4 was decided during implementation, not while writing the plan, so
Task 2's body below still describes the behaviour it supersedes.)

1. **`crypto.randomInt`, not `crypto.randomBytes`.** The spec named
   `randomBytes`. Reducing a random byte into an alphabet with `%` is modulo-
   biased; `crypto.randomInt(max)` is uniform and is in the same module. Same
   intent, correct primitive.
2. **The strength meter needs a replacement 4th band.**
   `passwordStrengthScore` awards one point for `PasswordRequirement.symbol`,
   and `PasswordStrengthMeter` renders **four** segments with "Strong" gated on
   a score of 4. Deleting the symbol requirement without replacing that band
   makes "Strong" unreachable forever. Task 4 replaces it with an advisory
   length-≥12 band. It is a meter band, not a requirement — nothing gates on it.
3. **`completeEmployeeSetup`'s guard removal gets a real test after all.**
   `functions/__tests__/employee_accounts.test.js` says the `onCall` wrappers
   "live elsewhere and aren't covered here" — and "elsewhere" turns out to be
   `functions/__tests__/employee_accounts_callables.test.js`, which has existed
   since 2026-08-11 and already covers `changeEmployeeEmail`. Task 3 APPENDS to
   it. (This plan first said Task 3 would *create* that file; that was wrong and
   would have overwritten a live suite. Corrected 2026-08-21.)
4. **`isAdmin` stays in `createEmployeeAccount`'s allowlist, accepted and
   ignored.** Task 2 below says to remove the key and adds a test asserting it
   is rejected; that test was never written, and the key was kept instead.
   `assertPayloadShape` throws `unexpected-field` on the first unrecognised
   key, and every admin build shipped before Task 7 sends `isAdmin`
   unconditionally on **both** create and Reset password. Removing it would
   therefore have broken both actions on every admin device until it updated —
   including the Reset password button that `docs/DEPLOYMENT.md` requires for
   remediating existing `invited` accounts *before* this deploy. Nothing reads
   the field: `performCreateAccount` hard-codes `role: "employee"`, which is
   what the callables suite now pins. This keeps the allowlist a superset of
   the deployed one, the compatibility contract in `docs/DEPLOYMENT.md` §4a.
   Drop the key once no build in the wild still sends it.

---

## File Structure

**Cloud Functions**

| File | Change | Responsibility after |
|---|---|---|
| `functions/employee_accounts.js` | Modify | `DEFAULT_PASSWORD` → `generateStartingPassword()`; `createEmployeeAccount` drops `isAdmin`; `completeEmployeeSetup` drops the `email_verified` guard |
| `functions/__tests__/employee_accounts.test.js` | Modify | Pure/transactional cores; password-generator shape assertions replace the pinned literal |
| `functions/__tests__/employee_accounts_callables.test.js` | **Modify (it already exists)** | `onCall` wrapper guards; already covers `changeEmployeeEmail` — APPEND the new describes, never overwrite |

**Dart — validation**

| File | Change |
|---|---|
| `lib/core/validators/password_requirements.dart` | Modify — drop `symbol` |
| `lib/core/validators/password_strength.dart` | Modify — symbol band → length-≥12 band |
| `lib/features/auth/widgets/password_requirements_checklist.dart` | Modify — drop the `symbol` switch arm |

**Dart — auth**

| File | Change |
|---|---|
| `lib/features/auth/services/auth_service.dart` | Modify — delete `isEmailVerified`, `sendVerificationEmail`, `refreshEmailVerified`, and the `email-not-verified` mapping |
| `lib/features/auth/domain/auth_failure.dart` | Modify — delete `AuthFailureEmailNotVerified` and its three branches |
| `lib/features/auth/screens/account_setup_screen.dart` | Modify — delete all verification state and UI; delete the must-differ rule |
| `lib/features/auth/widgets/account_setup/verify_email_panel.dart` | **Delete** |
| `lib/features/auth/widgets/account_setup/signed_in_chip.dart` | **Delete** |
| `lib/features/auth/widgets/account_setup/locked_email_panel.dart` | Modify — drop `isVerified` |
| `lib/features/employees/domain/policies/starting_password_policy.dart` | **Delete** (in Task 9 — the tile is its last reader) |

**Dart — employees**

| File | Change |
|---|---|
| `lib/features/employees/domain/employees_repository.dart` | Modify — drop `isAdmin` param |
| `lib/features/employees/data/firebase_employees_repository.dart` | Modify — drop `isAdmin` from the payload |
| `lib/features/employees/application/employee_form_controller.dart` | Modify — stop passing `isAdmin` |
| `lib/features/employees/widgets/sheets/invite_person_sheet.dart` | Modify — delete `_accessSection` and `_isAdmin` |
| `lib/features/employees/widgets/cards/pending_invite_tile.dart` | Modify — masked password when none is held |
| `lib/features/employees/widgets/fields/credential_line.dart` | Modify — email-only copy path |

**Dart — feature tour**

| File | Change |
|---|---|
| `lib/features/feature_tour/domain/tour_step_id.dart` | Modify — remove `personAccess` |
| `lib/features/feature_tour/domain/tour_definitions.dart` | Modify — remove `personAccess` |
| `lib/features/feature_tour/widgets/tour_step_text.dart` | Modify — remove the `personAccess` arm |

**Localization + docs:** `lib/l10n/app_en.arb`, `lib/l10n/app_fr.arb`,
`CLAUDE.md`, `.claude/rules/employees.md`, `.claude/rules/security.md`,
`docs/CLOUD_FUNCTIONS.md`.

> **Localization note:** a `PostToolUse` hook runs `flutter gen-l10n`
> automatically whenever an ARB file is touched with Edit or Write
> (`.claude/hooks/gen-l10n.sh`). Do **not** run it manually after an ARB edit;
> only run it if you edited an ARB some other way.

---

## Task 1: Random starting-password generator

**Files:**
- Modify: `functions/employee_accounts.js`
- Test: `functions/__tests__/employee_accounts.test.js`

- [ ] **Step 1: Write the failing tests**

In `functions/__tests__/employee_accounts.test.js`, add `generateStartingPassword`
to the destructured `require("../employee_accounts")` at the top of the file
(keep `DEFAULT_PASSWORD` in the list for now — Task 2 removes it), then add this
block immediately above `describe("provisionAuthAccount", ...)`:

```js
describe("generateStartingPassword", () => {
  test("is 12 unambiguous characters carrying each required class", () => {
    for (let i = 0; i < 200; i++) {
      const pw = generateStartingPassword();
      expect(pw).toHaveLength(12);
      expect(pw).toMatch(/[A-Z]/);
      expect(pw).toMatch(/[a-z]/);
      expect(pw).toMatch(/[0-9]/);
      // The admin reads this aloud, so no glyph pair anyone mishears.
      expect(pw).not.toMatch(/[0O1lI]/);
    }
  });

  test("does not repeat across calls", () => {
    const seen = new Set();
    for (let i = 0; i < 100; i++) seen.add(generateStartingPassword());
    expect(seen.size).toBe(100);
  });

  test("shuffles, so the guaranteed classes are not always in front", () => {
    // Without the shuffle the first character is ALWAYS the uppercase pick,
    // so this count would be exactly 200.
    const upperFirst = Array.from({length: 200}, generateStartingPassword)
        .filter((pw) => /[A-Z]/.test(pw[0])).length;
    expect(upperFirst).toBeGreaterThan(20);
    expect(upperFirst).toBeLessThan(180);
  });
});
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd functions && npx jest employee_accounts -t "generateStartingPassword"
```

Expected: FAIL — `generateStartingPassword is not a function`.

- [ ] **Step 3: Implement the generator**

In `functions/employee_accounts.js`, add `const crypto = require("crypto");` to
the `require` block at the top of the file (after the `firebase-admin` requires,
before the local `./security` require). Then **replace** the `DEFAULT_PASSWORD`
constant and its whole doc comment with:

```js
/**
 * The starting password a new employee account is created with.
 *
 * Random per account, and never stored: it is returned to the admin who
 * created the account and lives only in that surface's widget state. That is
 * what makes the onboarding window survivable now that setup no longer
 * requires a verified email — knowing someone's address is not enough to sign
 * in as them.
 *
 * The alphabet is deliberately unambiguous (no 0/O, no 1/l/I) because the
 * admin reads this out loud, and it carries an uppercase, a lowercase and a
 * digit so it satisfies the client-side policy in
 * lib/core/validators/password_requirements.dart.
 */
const PASSWORD_UPPER = "ABCDEFGHJKLMNPQRSTUVWXYZ";
const PASSWORD_LOWER = "abcdefghijkmnopqrstuvwxyz";
const PASSWORD_DIGITS = "23456789";
const PASSWORD_ALPHABET = PASSWORD_UPPER + PASSWORD_LOWER + PASSWORD_DIGITS;
const PASSWORD_LENGTH = 12;

/**
 * One uniformly-random character of [alphabet].
 *
 * randomInt, not `randomBytes()[0] % length` — the modulo is biased whenever
 * the alphabet does not divide 256.
 *
 * @param {string} alphabet Characters to choose from.
 * @return {string} One character.
 */
function pickChar(alphabet) {
  return alphabet[crypto.randomInt(alphabet.length)];
}

/**
 * Generates a starting password.
 *
 * @return {string} 12 unambiguous characters with at least one uppercase, one
 *   lowercase and one digit.
 */
function generateStartingPassword() {
  const chars = [
    pickChar(PASSWORD_UPPER),
    pickChar(PASSWORD_LOWER),
    pickChar(PASSWORD_DIGITS),
  ];
  while (chars.length < PASSWORD_LENGTH) {
    chars.push(pickChar(PASSWORD_ALPHABET));
  }
  // Fisher-Yates: without it the three guaranteed picks always sit in front,
  // which leaks 3 of the 12 positions' character classes.
  for (let i = chars.length - 1; i > 0; i--) {
    const j = crypto.randomInt(i + 1);
    [chars[i], chars[j]] = [chars[j], chars[i]];
  }
  return chars.join("");
}
```

Add `generateStartingPassword` to `module.exports` at the bottom of the file
(keep `DEFAULT_PASSWORD` exported for now; Task 2 removes it).

- [ ] **Step 4: Run the tests to verify they pass**

```bash
cd functions && npx jest employee_accounts -t "generateStartingPassword"
```

Expected: PASS, 3 tests.

- [ ] **Step 5: Commit**

```bash
git add functions/employee_accounts.js functions/__tests__/employee_accounts.test.js
git commit -m "feat(functions): add random starting-password generator"
```

---

## Task 2: `createEmployeeAccount` uses the generator and stops accepting `isAdmin`

**Files:**
- Modify: `functions/employee_accounts.js`
- Test: `functions/__tests__/employee_accounts.test.js`

- [ ] **Step 1: Update the existing tests to the new contract**

In `functions/__tests__/employee_accounts.test.js`:

a) Remove `DEFAULT_PASSWORD` from the destructured require at the top.

b) Remove `isAdmin: false,` from the `FIELDS` object.

c) Delete this test entirely (it pinned the removed constant):

```js
  test("the shared starting password is the exact mirrored literal", () => {
    expect(DEFAULT_PASSWORD).toBe("Welcome123!");
  });
```

d) In the remaining `provisionAuthAccount` / `resetProvisionedPassword` tests,
replace every `DEFAULT_PASSWORD` reference with a local literal declared at the
top of that `describe` block — those tests are about the plumbing, not the
value:

```js
const PW = "TestPw23456x";
```

e) **Replace** the `"maps isAdmin onto the role field"` test with:

```js
  test("always writes role employee, even if a caller smuggles isAdmin",
      async () => {
        const {db, ops} = fakeDb();

        await performCreateAccount(
            db, {...FIELDS, isAdmin: true}, {uid: "u", serverTimestamp});

        // The field is gone from the payload allowlist, but the core must not
        // read it either — two independent reasons a created account is never
        // an admin one.
        expect(ops.find((o) => o.op === "set").data.role).toBe("employee");
      });
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd functions && npx jest employee_accounts
```

Expected: FAIL — the `role employee` case reports `"admin"`, and any test still
referencing `DEFAULT_PASSWORD` errors as undefined.

- [ ] **Step 3: Apply the source changes**

In `functions/employee_accounts.js`:

a) In `performCreateAccount`, remove `isAdmin` from the destructuring and hard-
code the role. The first lines of the function body become:

```js
  const {
    name, firstName, lastName, email, phone, colorValue, jobTitle,
  } = fields;
  const {uid, serverTimestamp} = opts;
  // Never "admin": a created account can be pre-empted by whoever holds the
  // starting password, so it must never be able to arrive privileged. An
  // existing admin promotes a person from the edit sheet once they have set
  // up (lib/features/employees/widgets/sheets/edit_person_sheet.dart).
  const role = "employee";
```

Also update that function's JSDoc `@param` for `fields` to drop
`isAdmin: boolean`.

b) In the `createEmployeeAccount` handler, remove `"isAdmin"` from the
`assertPayloadShape` key set:

```js
  assertPayloadShape(req.data, new Set([
    "name", "firstName", "lastName", "email", "phone", "colorValue",
    "jobTitle",
  ]));
```

c) Delete the line `const isAdmin = req.data.isAdmin === true;`.

d) Remove `isAdmin` from the object literal passed to `performCreateAccount`:

```js
    const outcome = await performCreateAccount(
        db,
        {name, firstName, lastName, email, phone, colorValue, jobTitle},
        {
          uid: provisioned.uid,
          serverTimestamp: () => FieldValue.serverTimestamp(),
        },
    );
```

e) Generate the password once per call. Immediately above the
`const provisioned = ...` line, add:

```js
  // One password per call, shared by the mint path and the reset path so the
  // value returned to the admin is always the value that was actually set.
  const startingPassword = generateStartingPassword();
```

Then replace the three `DEFAULT_PASSWORD` uses:

```js
  const provisioned = existingAuth ?
      {uid: existingAuth.uid, reused: true} :
      await provisionAuthAccount(auth, email, name, startingPassword);
```

```js
    if (provisioned.reused) {
      await resetProvisionedPassword(
          auth, provisioned.uid, name, startingPassword);
    }
```

```js
  return {email, password: startingPassword};
```

f) Remove `DEFAULT_PASSWORD` from `module.exports`.

- [ ] **Step 4: Run the tests to verify they pass**

```bash
cd functions && npx jest employee_accounts
```

Expected: PASS, whole file.

- [ ] **Step 5: Commit**

```bash
git add functions/employee_accounts.js functions/__tests__/employee_accounts.test.js
git commit -m "feat(functions): per-account starting password, employee-only creation"
```

---

## Task 3: `completeEmployeeSetup` drops the `email_verified` guard

**Files:**
- Modify: `functions/employee_accounts.js:626-645`
- Modify: `functions/__tests__/employee_accounts_callables.test.js`

> **CORRECTION (2026-08-21):** this file ALREADY EXISTS — committed since
> 2026-08-11 (`a90474cc`), and it already covers `changeEmployeeEmail`'s guard
> order with its own `jest.mock("../security")` harness. The plan originally
> said "Create", which would have destroyed that suite. **Read it first**,
> reuse its existing mocks and helpers, and APPEND the two new `describe`
> blocks below. Do not rewrite the file and do not duplicate a helper it
> already defines.

- [ ] **Step 1: Write the failing wrapper tests**

Append to `functions/__tests__/employee_accounts_callables.test.js`. The sketch below is written standalone for clarity — reconcile it with what the file already has (its `jest.mock` calls, its `beforeEach`, and any fake-Firestore helper) rather than adding a second copy of anything:

```js
"use strict";

/**
 * Guards on the employee-account onCall wrappers, using the same mocked-
 * security harness as wave_callables.test.js: the transactional cores are
 * covered in employee_accounts.test.js, this file covers what the wrapper
 * itself accepts and refuses.
 */

jest.mock("../security");
jest.mock("firebase-admin/firestore");
jest.mock("firebase-admin/auth");

const security = require("../security");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");
const {getAuth} = require("firebase-admin/auth");

const {
  createEmployeeAccount,
  completeEmployeeSetup,
} = require("../employee_accounts");

const UID = "employee-uid";

/**
 * Fake Firestore holding exactly one users doc for the uid under test.
 * @param {?Object} userData Doc data, or null for "no such account".
 * @return {{db: !Object, updates: !Array}}
 */
function fakeDb(userData) {
  const updates = [];
  const ref = {id: "doc-1"};
  const snapshot = {
    empty: userData === null,
    docs: userData === null ? [] : [{ref, data: () => userData}],
  };
  const query = {
    where: () => query,
    limit: () => query,
  };
  const db = {
    collection: () => query,
    runTransaction: async (fn) => fn({
      get: async () => snapshot,
      update: (r, patch) => updates.push({ref: r, patch}),
    }),
  };
  return {db, updates};
}

beforeEach(() => {
  jest.clearAllMocks();
  FieldValue.serverTimestamp = jest.fn(() => "SERVER_TS");
  security.assertPayloadShape.mockImplementation(() => {});
  security.enforceDurableRateLimit.mockResolvedValue(undefined);
  security.assertAdmin.mockResolvedValue(undefined);
  security.optionalString.mockImplementation(
      (data, key) => (typeof data[key] === "string" ? data[key] : ""));
  security.requireString.mockImplementation((data, key) => data[key]);
  security.requireDocId.mockImplementation((data, key) => data[key]);
});

describe("completeEmployeeSetup", () => {
  test("activates an account whose token is NOT email-verified", async () => {
    const {db, updates} = fakeDb({status: "invited", firstName: "Sam"});
    getFirestore.mockReturnValue(db);

    const result = await completeEmployeeSetup.run({
      auth: {uid: UID, token: {email_verified: false}},
      data: {firstName: "Sam", lastName: "Lee", phone: "",
        termsAccepted: true, locationConsent: true},
    });

    expect(result).toEqual({ok: true});
    expect(updates).toHaveLength(1);
    expect(updates[0].patch.status).toBe("active");
  });

  test("activates even when the token carries no email claim at all",
      async () => {
        const {db, updates} = fakeDb({status: "invited"});
        getFirestore.mockReturnValue(db);

        await completeEmployeeSetup.run({
          auth: {uid: UID, token: {}},
          data: {firstName: "Sam", lastName: "Lee", phone: "",
            termsAccepted: true, locationConsent: true},
        });

        expect(updates[0].patch.status).toBe("active");
      });

  test("still refuses an account that is no longer invited", async () => {
    const {db} = fakeDb({status: "active"});
    getFirestore.mockReturnValue(db);

    await expect(completeEmployeeSetup.run({
      auth: {uid: UID, token: {email_verified: true}},
      data: {firstName: "", lastName: "", phone: "",
        termsAccepted: true, locationConsent: true},
    })).rejects.toThrow("setup-not-pending");
  });

  test("still refuses an unauthenticated caller", async () => {
    await expect(completeEmployeeSetup.run({auth: null, data: {}}))
        .rejects.toThrow("auth-required");
  });
});

describe("createEmployeeAccount", () => {
  test("does not accept isAdmin in its payload allowlist", async () => {
    getFirestore.mockReturnValue(fakeDb(null).db);
    getAuth.mockReturnValue({
      getUserByEmail: jest.fn(async () => {
        throw new Error("not-found");
      }),
      createUser: jest.fn(async () => ({uid: "new-uid"})),
      updateUser: jest.fn(),
      deleteUser: jest.fn(),
    });

    await createEmployeeAccount.run({
      auth: {uid: "admin-uid", token: {}},
      data: {name: "A B", firstName: "A", lastName: "B",
        email: "a@b.test", phone: "", colorValue: "1", jobTitle: ""},
    }).catch(() => {});

    expect(security.assertPayloadShape).toHaveBeenCalled();
    const [, allowedKeys] = security.assertPayloadShape.mock.calls[0];
    expect(allowedKeys.has("isAdmin")).toBe(false);
  });
});
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd functions && npx jest employee_accounts_callables
```

Expected: FAIL — the two activation cases throw `email-not-verified`. (The
`createEmployeeAccount` case should already pass from Task 2; that is fine.)

- [ ] **Step 3: Delete the guard**

In `functions/employee_accounts.js`, inside `completeEmployeeSetup`, delete the
whole comment block and `if` currently at lines 630-645 — everything from
`// The account is created on a SHARED starting password` down to and including:

```js
  if (!req.auth.token || req.auth.token.email_verified !== true) {
    throw new HttpsError("failed-precondition", "email-not-verified");
  }
```

Replace it with this comment, so the next reader knows the gate was removed on
purpose and what carries the weight now:

```js
  // No mailbox check: the starting password is random per account and is
  // handed over out-of-band, so signing in is itself the proof this guard used
  // to provide. See docs/plans/2026-08-21-simplified-auth-design.md.
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
cd functions && npx jest employee_accounts_callables
```

Expected: PASS, 5 tests.

- [ ] **Step 5: Run the whole backend suite and the linter**

```bash
cd functions && npm run lint && npx jest
```

Expected: lint clean (watch the 80-column limit in the new code), all Jest
suites pass.

- [ ] **Step 6: Commit**

```bash
git add functions/employee_accounts.js functions/__tests__/employee_accounts_callables.test.js
git commit -m "feat(functions): drop the email-verified gate on completeEmployeeSetup"
```

---

## Task 4: Drop the symbol requirement and re-band the strength meter

**Files:**
- Modify: `lib/core/validators/password_requirements.dart`
- Modify: `lib/core/validators/password_strength.dart`
- Modify: `lib/features/auth/widgets/password_requirements_checklist.dart:39`
- Test: `test/core/validators/password_requirements_test.dart`
- Test: `test/core/validators/password_strength_test.dart`

- [ ] **Step 1: Update the existing tests, then add the new ones**

**a)** `test/core/validators/password_requirements_test.dart`:

- Delete the whole `group('PasswordRequirement.symbol', ...)` block
  (lines ~51-63).
- In `group('PasswordRequirement.allMetBy', ...)`, delete this line from the
  refusal case — it now passes, which is the point of the change:

```dart
      expect(PasswordRequirement.allMetBy('Abcdefg1'), isFalse); // no symbol
```

- Add:

```dart
    test('no longer demands a symbol', () {
      expect(PasswordRequirement.allMetBy('Abcdefg1'), isTrue);
    });

    test('still demands the other four', () {
      expect(PasswordRequirement.allMetBy('abcdefg1'), isFalse); // no upper
      expect(PasswordRequirement.allMetBy('ABCDEFG1'), isFalse); // no lower
      expect(PasswordRequirement.allMetBy('Abcdefgh'), isFalse); // no number
      expect(PasswordRequirement.allMetBy('Abc1'), isFalse); // too short
    });
```

**b)** `test/core/validators/password_strength_test.dart`. Careful with wording
here: this file already calls the `minLength` band "the length band"
(`'withholds the length band from a short strong password'`, line ~31). The new
fourth band is a *different*, longer threshold — call it the **bonus band** so
the two never read as the same thing.

- Update `test('scores a password meeting every band 4', ...)` (line ~27): its
  password must now be **12 or more characters**, since the symbol band is gone
  and the bonus band replaced it. Use `'Passw0rdAbcd'`.
- Re-read the test at line ~31 and the comment at line ~11 (`"Fails length,
  mixed case, digit and symbol alike."`) and correct any wording that names the
  symbol band.
- Add:

```dart
  test('a compliant password without a symbol can still reach Strong', () {
    // The meter renders four segments and gates "Strong" on 4, so the top
    // band has to be reachable by a password the validator actually accepts.
    expect(passwordStrengthScore('Passw0rdAbcd'), 4);
  });

  test('a compliant but short password stops one band below Strong', () {
    expect(passwordStrengthScore('Passw0rd'), 3);
  });

  test('the bonus band is length, not a symbol', () {
    // Eight characters with a symbol used to score 4; it must not any more.
    expect(passwordStrengthScore('Passw0r!'), 3);
  });
```

**c)** `test/features/auth/widgets/password_requirements_checklist_test.dart`
derives its expected row count from `PasswordRequirement.values.length`
(line ~28), so it adapts on its own. Read it to confirm nothing else names the
symbol row.

- [ ] **Step 2: Run the tests to verify they fail**

```bash
flutter test test/core/validators/password_requirements_test.dart test/core/validators/password_strength_test.dart
```

Expected: FAIL — `allMetBy('Passw0rdAbc')` is false, and
`passwordStrengthScore('Passw0rdAbcd')` is 3.

- [ ] **Step 3: Apply the source changes**

`lib/core/validators/password_requirements.dart` — remove the `symbol` member,
its regex and its `isMetBy` arm:

```dart
enum PasswordRequirement {
  minLength,
  uppercase,
  lowercase,
  number;

  static const int minLengthChars = 8;

  static final RegExp _uppercase = RegExp(r'\p{Lu}', unicode: true);
  static final RegExp _lowercase = RegExp(r'\p{Ll}', unicode: true);
  static final RegExp _number = RegExp(r'\d');

  bool isMetBy(String password) => switch (this) {
    minLength => password.length >= minLengthChars,
    uppercase => _uppercase.hasMatch(password),
    lowercase => _lowercase.hasMatch(password),
    number => _number.hasMatch(password),
  };

  static bool allMetBy(String password) =>
      values.every((requirement) => requirement.isMetBy(password));
}
```

`lib/core/validators/password_strength.dart` — replace the symbol band with a
length band and document why the count stayed at four:

```dart
import 'package:scheduling/core/validators/password_requirements.dart';

/// Length at which the meter awards its fourth band. Advisory only — nothing
/// gates on it, unlike [PasswordRequirement.minLengthChars].
const int kStrongPasswordLength = 12;

/// 0–4 for the strength meter's segments. Display-only — the submit gate stays
/// [PasswordRequirement.allMetBy] via `AuthValidators.newPassword`, and this
/// must never drift into a second validator that can disagree with the
/// checklist rendered beside it.
///
/// Four bands, not five: mixed case counts as one bar, matching the design's
/// 4-segment meter. The fourth band is LENGTH, not a symbol — the symbol
/// requirement was removed (2026-08-21) and without a replacement band the
/// meter's "Strong" label became unreachable by any password the validator
/// accepts.
int passwordStrengthScore(String password) {
  var score = 0;
  if (PasswordRequirement.minLength.isMetBy(password)) score++;
  if (PasswordRequirement.uppercase.isMetBy(password) &&
      PasswordRequirement.lowercase.isMetBy(password)) {
    score++;
  }
  if (PasswordRequirement.number.isMetBy(password)) score++;
  if (password.length >= kStrongPasswordLength) score++;
  return score;
}
```

`lib/features/auth/widgets/password_requirements_checklist.dart` — delete this
line from the `_label` switch:

```dart
      PasswordRequirement.symbol => l10n.validation_passwordReqSymbol,
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
flutter test test/core/validators/ test/features/auth/widgets/password_requirements_checklist_test.dart
```

Expected: PASS. `auth_validators_test.dart` is in that directory — if any of its
cases used a symbol to make a password "valid", they still pass (a symbol is
allowed, just no longer required), but any case asserting a symbol-less password
is *rejected* now fails and must be updated.

- [ ] **Step 5: Commit**

```bash
git add lib/core/validators/ lib/features/auth/widgets/password_requirements_checklist.dart test/core/validators/
git commit -m "feat(auth): drop the symbol password requirement"
```

---

## Task 5: Remove the verification API from `AuthService` and `AuthFailure`

**Files:**
- Modify: `lib/features/auth/services/auth_service.dart`
- Modify: `lib/features/auth/domain/auth_failure.dart`
- Test: `test/features/auth/services/auth_service_test.dart`

- [ ] **Step 1: Write the failing test**

`AuthService.completeAccountSetup`'s ordering guarantee is unchanged and must
stay pinned. Add one test to `test/features/auth/services/auth_service_test.dart`
proving the setup path no longer consults verification at all:

```dart
  test('completeAccountSetup never asks the user about email verification',
      () async {
    when(() => user.updatePassword(any())).thenAnswer((_) async {});

    await service().completeAccountSetup(
      newPassword: 'Passw0rdAbc',
      firstName: 'Sam',
      lastName: 'Lee',
      termsAccepted: true,
      locationConsent: true,
    );

    // The gate is gone: no reload, no forced token refresh, no verification
    // send anywhere on the setup path.
    verifyNever(() => user.reload());
    verifyNever(() => user.sendEmailVerification());
    verifyNever(() => user.getIdToken(any()));
  });
```

- [ ] **Step 2: Run the test to verify it fails or errors**

```bash
flutter test test/features/auth/services/auth_service_test.dart
```

Expected: PASS or FAIL depending on the existing mock setup — either way, run
it now so you have a baseline to compare against after Step 3. If it passes
already, that is fine; it is a regression guard.

- [ ] **Step 3: Delete the verification members**

In `lib/features/auth/services/auth_service.dart`, delete:

- the `isEmailVerified` getter and its doc comment,
- the whole `sendVerificationEmail()` method and its doc comment,
- the whole `refreshEmailVerified()` method and its doc comment,
- inside `_mapSetupError`, this branch and its comment:

```dart
      // The screen gates on this before submitting, so reaching it means the
      // token still carried the pre-verification claim — which the "Check
      // again" action fixes by forcing a refresh.
      if (e.message == 'email-not-verified') {
        return const AuthFailureEmailNotVerified();
      }
```

In `lib/features/auth/domain/auth_failure.dart`, delete:

- the `AuthFailureEmailNotVerified` class and the comment above it (lines
  ~186-193),
- the `AuthFailureEmailNotVerified() => true,` arm in `isExpected` (and the
  comment above it if it only describes that arm),
- `AuthFailureEmailNotVerified() ||` from the `toLocalizedMessage` switch at
  line ~253, leaving `AuthFailureSessionExpired() || AuthFailureUnknown() =>`.

- [ ] **Step 4: Run the tests to verify they pass**

```bash
flutter test test/features/auth/
```

Expected: `account_setup_screen_test.dart` FAILS to compile (it still stubs the
deleted methods). That is expected and is fixed in Task 6. `auth_service_test.dart`
must PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/auth/services/auth_service.dart lib/features/auth/domain/auth_failure.dart test/features/auth/services/auth_service_test.dart
git commit -m "refactor(auth): remove the email-verification API"
```

---

## Task 6: Strip verification from `AccountSetupScreen`

**Files:**
- Modify: `lib/features/auth/screens/account_setup_screen.dart`
- Modify: `lib/features/auth/widgets/account_setup/locked_email_panel.dart`
- Delete: `lib/features/auth/widgets/account_setup/verify_email_panel.dart`
- Delete: `lib/features/auth/widgets/account_setup/signed_in_chip.dart`
- Test: `test/features/auth/screens/account_setup_screen_test.dart`

> **Ordering:** `starting_password_policy.dart` is NOT deleted here.
> `pending_invite_tile.dart:296` still reads `kDefaultStartingPassword` until
> Task 9, so deleting the file now breaks `flutter analyze` for three tasks.
> This task only removes the setup screen's import and use of it.

- [ ] **Step 1: Update the tests to the new contract**

In `test/features/auth/screens/account_setup_screen_test.dart`:

a) Delete the whole `group('the email-verification gate', ...)` block
(lines ~249-344).

b) Delete the whole `group('the starting-password gate', ...)` block
(lines ~221-247) and the `starting_password_policy.dart` import.

c) Delete the two stub lines in `setUp`:

```dart
    when(() => auth.sendVerificationEmail()).thenAnswer((_) async {});
    when(() => auth.refreshEmailVerified()).thenAnswer((_) async => false);
```

and any `when(() => auth.isEmailVerified).thenReturn(...)` stub.

d) The sign-out group at line ~370 drives the flow through the
`sendVerificationEmail` button, which no longer exists. Rewrite that first test
to reach the sign-out control directly. The file's helpers are
`_harness({required auth, offline, resumeOutcome})`, `_fillForm(tester,
{password})`, `_consent(tester)` and `_submit(tester)` — use them:

```dart
    testWidgets('signing out returns to login', (tester) async {
      when(() => auth.signOut()).thenAnswer((_) async {});
      await tester.pumpWidget(_harness(auth: auth));
      await tester.pumpAndSettle();

      final logOut = find.widgetWithText(TextButton, 'Log out');
      await tester.ensureVisible(logOut);
      await tester.pumpAndSettle();
      await tester.tap(logOut);
      await tester.pumpAndSettle();

      verify(() => auth.signOut()).called(1);
    });
```

e) Add a test proving the previously-blocked submit now goes through. Note
`_fillForm` defaults its password to the file's `_chosen` constant
(`'Chosen1!pass'`), which still satisfies the loosened policy:

```dart
    testWidgets('an unverified address no longer blocks activation',
        (tester) async {
      await tester.pumpWidget(_harness(auth: auth));
      await tester.pumpAndSettle();
      await _fillForm(tester);
      await _consent(tester);
      await _submit(tester);

      verify(
        () => auth.completeAccountSetup(
          newPassword: any(named: 'newPassword'),
          firstName: any(named: 'firstName'),
          lastName: any(named: 'lastName'),
          phone: any(named: 'phone'),
          termsAccepted: true,
          locationConsent: true,
        ),
      ).called(1);
    });
```

Cross-check the named-argument matchers against the existing `'consent is
passed through as true once given'` test and copy its exact shape if it differs.

- [ ] **Step 2: Run the tests to verify they fail**

```bash
flutter test test/features/auth/screens/account_setup_screen_test.dart
```

Expected: FAIL to compile — `VerifyEmailPanel` and `_emailVerified` still exist
in the screen, and `LockedEmailPanel` still requires `isVerified`.

- [ ] **Step 3: Strip the screen**

In `lib/features/auth/screens/account_setup_screen.dart`:

a) Delete these imports:

```dart
import 'package:scheduling/features/auth/widgets/account_setup/verify_email_panel.dart';
import 'package:scheduling/features/employees/domain/policies/starting_password_policy.dart';
```

b) Delete these fields and the doc comment above `_emailVerified`:

```dart
  late bool _emailVerified;
  bool _isSendingVerification = false;
  bool _isCheckingVerification = false;
  bool _verificationSent = false;
  String? _verificationNotice;
```

c) In `initState`, delete `_emailVerified = _authService.isEmailVerified;`.

d) Delete the `_isVerificationBusy` getter, the whole `_sendVerificationEmail()`
method and the whole `_checkVerification()` method, with their doc comments.

e) Simplify `_isTransitionBusy`:

```dart
  bool get _isTransitionBusy => _isLoading || _isSigningOut;
```

f) In `_validate`, replace the password block and its long comment with:

```dart
    // The meter beside this field is advisory; the gate stays the strict
    // new-password validator so it can never disagree with the checklist.
    //
    // Validated TRIMMED, because `completeAccountSetup` stores the trimmed
    // value: checking `"Aa1!bcd "` (8) and then setting `"Aa1!bcd"` (7) let a
    // password through that does not meet the policy it was checked against.
    final password = _passwordController.text.trim();
    final passwordErr = AuthValidators.newPassword(context, password);
```

g) In `_finishSetup`, replace the gate and its comment with:

```dart
    // Consent is the gate, and this is where it is enforced: the confirm-
    // password field's keyboard-submit reaches here without consulting the
    // disabled button, so gating only at the CTA would let Done through.
    if (!_consented) return;
```

h) In `_finishSetup`'s `catch`, delete this line and its comment:

```dart
        // The local flag said verified but the token did not carry the claim,
        // so put the step back rather than leaving a CTA that can only fail.
        if (failure is AuthFailureEmailNotVerified) _emailVerified = false;
```

i) Replace `_identityPanels()` with:

```dart
  /// The read-only address they signed in with.
  List<Widget> _identityPanels() {
    final email = _authService.currentUser?.email ?? '';
    if (email.isEmpty) return const [];
    return [
      const SizedBox(height: AppSpacing.sp16),
      LockedEmailPanel(email: email),
    ];
  }
```

j) In `_submitBlock`, replace the button's gate and comment:

```dart
      AnimatedLoadingButton(
        label: l10n.auth_finishSetup,
        isLoading: _isLoading || _isSigningOut,
        // The checkbox IS the gate — it is on screen and self-explanatory, so
        // a disabled button needs no error copy of its own.
        onPressed: _consented ? _finishSetup : null,
      ),
```

- [ ] **Step 4: Simplify `LockedEmailPanel`**

In `lib/features/auth/widgets/account_setup/locked_email_panel.dart`:

- delete the `signed_in_chip.dart` import,
- remove the `isVerified` parameter and field so the constructor is
  `const LockedEmailPanel({required this.email, super.key});`,
- replace the `Wrap(...)` block with the label alone:

```dart
            Text(l10n.common_email, style: theme.textTheme.labelLarge),
```

- [ ] **Step 5: Delete the two dead panels**

```bash
git rm lib/features/auth/widgets/account_setup/verify_email_panel.dart \
       lib/features/auth/widgets/account_setup/signed_in_chip.dart
```

If a widget test exists for either deleted panel, `git rm` it too:

```bash
ls test/features/auth/widgets/account_setup/ 2>/dev/null
```

- [ ] **Step 6: Run the tests to verify they pass**

```bash
flutter analyze && flutter test test/features/auth/
```

Expected: `No issues found!` and all auth tests pass.
`starting_password_policy.dart` is still present and still referenced by
`pending_invite_tile.dart`, so the analyzer stays clean.

- [ ] **Step 7: Commit**

```bash
git add -A lib/features/auth test/features/auth
git commit -m "feat(auth): remove the email-verification step from account setup"
```

---

## Task 7: Drop `isAdmin` from the account-creation call chain

**Files:**
- Modify: `lib/features/employees/domain/employees_repository.dart:20-28`
- Modify: `lib/features/employees/data/firebase_employees_repository.dart:111-135`
- Modify: `lib/features/employees/application/employee_form_controller.dart:203`
- Test: `test/features/employees/data/firebase_employees_repository_test.dart`
- Test: `test/features/employees/widgets/cards/pending_invite_tile_test.dart`

- [ ] **Step 1: Update the tests to the new payload**

**a)** `test/features/employees/data/firebase_employees_repository_test.dart`
already has a `stubCallable(String name, {Object? data})` helper that stubs the
call and returns the mock for capture. Find the existing `createEmployeeAccount`
payload assertion, remove `'isAdmin': false` (or `true`) from the expected map,
and drop the `isAdmin:` named argument from the call. Then add:

```dart
    test('never sends isAdmin — the server decides the role', () async {
      final callable = stubCallable(
        'createEmployeeAccount',
        data: {'email': 'a@b.test', 'password': 'Pw23456789x'},
      );

      await repo().createEmployeeAccount(
        name: 'A B',
        firstName: 'A',
        lastName: 'B',
        email: 'a@b.test',
        phone: '',
        colorValue: '1',
        jobTitle: '',
      );

      final payload =
          verify(() => callable.call<dynamic>(captureAny<Object?>()))
              .captured
              .single as Map<Object?, Object?>;
      expect(payload.containsKey('isAdmin'), isFalse);
    });
```

**b)** `test/features/employees/widgets/cards/pending_invite_tile_test.dart`
passes `isAdmin: any(named: 'isAdmin')` to `repo.createEmployeeAccount` in
**five** places — the `verifyNeverCreated()` helper at line ~114 and the
`verify`/`when` blocks at lines ~48, ~122, ~277 and ~343. Every one of them
stops compiling when the parameter goes. Delete that line from all five:

```bash
grep -n "isAdmin" test/features/employees/widgets/cards/pending_invite_tile_test.dart
```

Expected after the edit: no matches.

- [ ] **Step 2: Run the test to verify it fails**

```bash
flutter test test/features/employees/data/firebase_employees_repository_test.dart
```

Expected: FAIL to compile — `createEmployeeAccount` still requires `isAdmin`.

- [ ] **Step 3: Remove the parameter**

`lib/features/employees/domain/employees_repository.dart` — delete
`required bool isAdmin,` from the `createEmployeeAccount` signature, and update
its doc comment's "resets the password back to the shared default" sentence to:

```dart
  /// Re-running this for someone who hasn't set up yet is the supported
  /// "they never signed in / they lost the password" path: it refreshes their
  /// editable fields and issues a NEW random starting password. It throws
  /// `EmployeesFailureEmailAlreadyExists` once they HAVE set up, so it can
  /// never reset a password someone chose.
  ///
  /// The account is always created as a plain employee; promotion to admin is
  /// a separate edit once the person has set up.
```

`lib/features/employees/data/firebase_employees_repository.dart` — delete
`required bool isAdmin,` from the signature and `'isAdmin': isAdmin,` from the
payload map.

`lib/features/employees/application/employee_form_controller.dart` — delete
`isAdmin: employee.isAdmin,` from the `createEmployeeAccount` call at line 203.

- [ ] **Step 4: Run the tests to verify they pass**

```bash
flutter test test/features/employees/data/firebase_employees_repository_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/employees test/features/employees
git commit -m "feat(employees): accounts are always created as employees"
```

---

## Task 8: Remove the admin toggle from the create sheet and retire its tour step

**Files:**
- Modify: `lib/features/employees/widgets/sheets/invite_person_sheet.dart`
- Modify: `lib/features/feature_tour/domain/tour_step_id.dart:48`
- Modify: `lib/features/feature_tour/domain/tour_definitions.dart:99-107`
- Modify: `lib/features/feature_tour/widgets/tour_step_text.dart:173-176`
- Test: `test/features/feature_tour/domain/tour_definitions_test.dart:147`

- [ ] **Step 1: Update the tests**

In `test/features/feature_tour/domain/tour_definitions_test.dart`, delete the
assertion referencing `TourStepId.personAccess` at line 147 (and the enclosing
`test(...)` if `personAccess` is the only thing it asserts).

In `test/features/employees/widgets/sheets/invite_person_sheet_test.dart`,
delete any interaction with `Key('adminAccess')` and add this test. The file's
helpers are `wrap({Set<int> usedColors, double textScale})` and
`fillRequired(tester)`:

```dart
  testWidgets('offers no admin toggle — new accounts are always employees',
      (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('adminAccess')), findsNothing);
  });

  testWidgets('saves the new person as an employee', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();
    await fillRequired(tester);

    // Match the file's existing save-and-verify test for how it taps the
    // primary action and which captured argument holds the EmployeeRecord.
    final record = verify(
      () => repo.createEmployeeAccount(
        name: any(named: 'name'),
        firstName: any(named: 'firstName'),
        lastName: any(named: 'lastName'),
        email: any(named: 'email'),
        phone: any(named: 'phone'),
        colorValue: any(named: 'colorValue'),
        jobTitle: any(named: 'jobTitle'),
      ),
    );
    expect(record, isNotNull);
  });
```

If that file has no existing save-path test to model the second case on, keep
only the first — the toggle's absence is the assertion that matters, and
`role: 'employee'` is already pinned server-side by Task 2.

- [ ] **Step 2: Run the tests to verify they fail**

```bash
flutter test test/features/feature_tour/domain/tour_definitions_test.dart test/features/employees/widgets/sheets/
```

Expected: FAIL — the toggle is still rendered.

- [ ] **Step 3: Strip the sheet**

In `lib/features/employees/widgets/sheets/invite_person_sheet.dart`:

a) Delete the field `bool _isAdmin = false;`.

b) In `_save`, change the record's role to a constant:

```dart
            role: 'employee',
```

c) Delete the whole `_accessSection` method (lines ~305-320) and remove
`..._accessSection(theme, l10n),` from the `children:` list in `build`.

d) The `WarningNote` that lived in `_accessSection` must survive. Append it to
the end of the last remaining section's child list, immediately before that
section's trailing `SizedBox`:

```dart
        WarningNote(message: l10n.employees_invitedNote),
        const SizedBox(height: AppSpacing.sp24),
```

Keep the `WarningNote` import.

- [ ] **Step 4: Retire the tour step**

- `lib/features/feature_tour/domain/tour_step_id.dart` — delete the
  `personAccess,` enum member.
- `lib/features/feature_tour/domain/tour_definitions.dart` — delete
  `TourStepId.personAccess,` from the invite-person step list, and the comment
  above it that explains its position ("Before personAccess on purpose: …") if
  that comment now describes nothing.
- `lib/features/feature_tour/widgets/tour_step_text.dart` — delete the
  `TourStepId.personAccess => (...)` switch arm.

The tour's storage key is `TourForm.invitePerson`, which is unchanged, so no
one's tour replays.

- [ ] **Step 5: Run the tests to verify they pass**

```bash
flutter analyze && flutter test test/features/feature_tour/ test/features/employees/
```

Expected: `No issues found!` and both suites pass.

- [ ] **Step 6: Commit**

```bash
git add lib/features/employees lib/features/feature_tour test/features
git commit -m "feat(employees): remove the admin toggle from account creation"
```

---

## Task 9: Mask the roster row's password when none is held

**Files:**
- Modify: `lib/features/employees/widgets/cards/pending_invite_tile.dart`
- Modify: `lib/features/employees/widgets/fields/credential_line.dart`
- Modify: `lib/l10n/app_en.arb`, `lib/l10n/app_fr.arb`
- Delete: `lib/features/employees/domain/policies/starting_password_policy.dart`
- Test: `test/features/employees/widgets/cards/pending_invite_tile_test.dart`

This is the task that finally retires `kDefaultStartingPassword` — the tile is
its last remaining reader, which is why Task 6 left the file in place.

- [ ] **Step 1: Write the failing tests**

In `test/features/employees/widgets/cards/pending_invite_tile_test.dart`, delete
the assertion that the row renders `Welcome123!` (and the
`starting_password_policy.dart` import), then add the two tests below.

The file's helpers are `wrap(EmployeeRecord employee, {double textScale})`,
the `_invited` fixture, `useTallViewport(tester)` and `expand(tester)`.
**`expand` deliberately pumps a fixed span instead of settling** — the
credentials render in `SelectableText`s whose cursors never settle, so
`pumpAndSettle` after expanding will time out. Follow that same pattern:

```dart
  testWidgets('masks the password when the app holds none', (tester) async {
    useTallViewport(tester);
    await tester.pumpWidget(wrap(_invited));
    await tester.pumpAndSettle();
    await expand(tester);

    // No stored plaintext credential exists to show, and the constant it used
    // to fall back to is gone.
    expect(find.text('••••••••'), findsOneWidget);
    expect(find.text('Reset password to issue a new one'), findsOneWidget);
    expect(find.text('Copy email'), findsOneWidget);
    expect(find.text('Copy both'), findsNothing);
  });

  testWidgets('shows the real pair after a reset', (tester) async {
    useTallViewport(tester);
    await tester.pumpWidget(wrap(_invited));
    await tester.pumpAndSettle();
    await expand(tester);

    await tester.tap(find.text('Reset password'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Pw23456789x'), findsOneWidget);
    expect(find.text('••••••••'), findsNothing);
  });
```

Set the file's `repo.createEmployeeAccount` stub to return
`const NewAccountCredentials(email: 'zoe@company.test', password: 'Pw23456789x')`
so the second test has a known value to assert. Match the email to whatever the
`_invited` fixture carries.

- [ ] **Step 2: Run the tests to verify they fail**

```bash
flutter test test/features/employees/widgets/cards/pending_invite_tile_test.dart
```

Expected: FAIL to compile (the deleted policy import) or FAIL on the mask
assertion.

- [ ] **Step 3: Add the ARB keys**

In `lib/l10n/app_en.arb`, beside the other `employees_` keys:

```json
  "employees_copyEmail": "Copy email",
  "@employees_copyEmail": {
    "description": "Copy control on a pending-account row that has no password to show"
  },
  "employees_passwordHiddenUntilReset": "Reset password to issue a new one",
  "@employees_passwordHiddenUntilReset": {
    "description": "Hint under the masked password on a pending-account roster row whose starting password the app no longer holds"
  },
```

In `lib/l10n/app_fr.arb`, at the matching position:

```json
  "employees_copyEmail": "Copier le courriel",
  "employees_passwordHiddenUntilReset": "Réinitialisez le mot de passe pour en générer un nouveau",
```

The `PostToolUse` hook regenerates `lib/l10n/.gen/` automatically — do not run
`flutter gen-l10n` by hand.

- [ ] **Step 4: Add the email-only copy path**

In `lib/features/employees/widgets/fields/credential_line.dart`, add beside
`copyCredentialsToClipboard`:

```dart
/// Copies the email alone, for a pending row whose starting password the app
/// no longer holds. Beside [copyCredentialsToClipboard] so the two clipboard
/// payloads this feature can produce stay in one place.
void copyEmailToClipboard(String email) {
  Clipboard.setData(ClipboardData(text: email));
}
```

and widen the label helper (both call sites keep working because the new flag
defaults to the existing behaviour):

```dart
/// The button's label, split out for the Cupertino dialog action, which takes
/// a bare child rather than a Material button.
String copyCredentialsLabel(
  BuildContext context, {
  bool copied = false,
  bool hasPassword = true,
}) {
  if (copied) return context.l10n.common_copied;
  return hasPassword
      ? context.l10n.employees_copyBoth
      : context.l10n.employees_copyEmail;
}
```

Add the matching `hasPassword` field to `CopyCredentialsButton` (defaulting to
`true`) and pass it through to `copyCredentialsLabel`.

- [ ] **Step 5: Render the masked state**

In `lib/features/employees/widgets/cards/pending_invite_tile.dart`:

a) In `_buildBody`, replace the two fallback lines and their comment with:

```dart
    // Before any reset the row shows the stored email; the starting password
    // is random per account and is never persisted, so there is nothing to
    // show until a reset issues a new one.
    final email = reissued?.email ?? widget.employee.email;
    final password = reissued?.password;
```

b) Change `_copy` to handle the absent password:

```dart
  void _copy(String email, String? password) {
    if (password == null) {
      copyEmailToClipboard(email);
    } else {
      copyCredentialsToClipboard(email: email, password: password);
    }
    setState(() => _copied = true);
  }
```

c) Change `_CredentialsBlock`'s `password` field to `final String? password;`
and render the mask plus the hint when it is null:

```dart
    final copyButton = CopyCredentialsButton(
      copied: copied,
      hasPassword: password != null,
      onCopy: onCopy,
    );

    final values = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        CredentialLine(label: l10n.common_email, value: email),
        const SizedBox(height: AppSpacing.sp8),
        CredentialLine(
          label: l10n.employees_temporaryPassword,
          value: password ?? '••••••••',
        ),
        if (password == null) ...[
          const SizedBox(height: AppSpacing.sp4),
          Text(
            l10n.employees_passwordHiddenUntilReset,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.palette.textMuted,
            ),
          ),
        ],
      ],
    );
```

- [ ] **Step 6: Delete the now-unreferenced policy file**

```bash
grep -rn "kDefaultStartingPassword\|starting_password_policy" lib/ test/ --include=*.dart
```

Expected: no matches. Then:

```bash
git rm lib/features/employees/domain/policies/starting_password_policy.dart
```

If `lib/features/employees/domain/policies/` is now empty, leave the empty
directory alone — git does not track it.

- [ ] **Step 7: Run the tests to verify they pass**

```bash
flutter analyze && flutter test test/features/employees/
```

Expected: `No issues found!` and the employees suite passes.

- [ ] **Step 8: Commit**

```bash
git add -A lib/features/employees lib/l10n test/features/employees
git commit -m "feat(employees): mask a pending row's password when none is held"
```

---

## Task 10: Remove the dead ARB keys

**Files:**
- Modify: `lib/l10n/app_en.arb`, `lib/l10n/app_fr.arb`

- [ ] **Step 1: Confirm each key is genuinely unreferenced**

```bash
for k in auth_emailVerified auth_sendVerificationEmail auth_resendVerificationEmail \
         auth_verificationEmailSent auth_emailNotVerifiedYet \
         validation_passwordMustDifferFromStarting validation_passwordReqSymbol \
         error_verifyYourEmailBeforeFinishing tour_personAccessTitle tour_personAccessDesc; do
  echo "== $k"
  grep -rn "$k" lib/ test/ --include=*.dart | grep -v "lib/l10n/.gen" || echo "  (unreferenced)"
done
```

Expected: every key prints `(unreferenced)`. If any still has a hit, that
task's source change was missed — go back and finish it before deleting the key.

- [ ] **Step 2: Delete the entries**

From **both** `lib/l10n/app_en.arb` and `lib/l10n/app_fr.arb`, delete these keys
(and, in `app_en.arb` only, each one's `"@key"` metadata block):

```
auth_emailVerified
auth_sendVerificationEmail
auth_resendVerificationEmail
auth_verificationEmailSent
auth_emailNotVerifiedYet
validation_passwordMustDifferFromStarting
validation_passwordReqSymbol
error_verifyYourEmailBeforeFinishing
tour_personAccessTitle
tour_personAccessDesc
```

**Do NOT delete** `employees_sectionAccess`, `employees_adminAccess` or
`employees_adminAccessDescription` — the edit sheet's promote toggle still
renders all three.

Watch the JSON: removing the last entry of a file leaves a trailing comma.

- [ ] **Step 3: Verify generation and drift**

The hook regenerates on save. Confirm both files still parse and nothing is
newly untranslated:

```bash
python -c "import io,json; [json.load(io.open(f,encoding='utf-8')) for f in ['lib/l10n/app_en.arb','lib/l10n/app_fr.arb']]; print('ARB JSON ok')"
cat lib/l10n/.gen/untranslated.json
```

Expected: `ARB JSON ok`, and `untranslated.json` lists nothing new versus
`git diff`.

- [ ] **Step 4: Run the analyzer and the full suite**

```bash
flutter analyze && flutter test
```

Expected: `No issues found!` and a green suite.

- [ ] **Step 5: Commit**

```bash
git add lib/l10n
git commit -m "chore(l10n): drop the strings the verification step used"
```

---

## Task 11: Update the documentation that asserts the old guarantees

**Files:**
- Modify: `CLAUDE.md`
- Modify: `.claude/rules/employees.md`
- Modify: `.claude/rules/security.md`
- Modify: `docs/CLOUD_FUNCTIONS.md`

These files do not merely mention the old flow — they state it as the reason
other code is safe. Leaving them is worse than leaving no docs at all.

- [ ] **Step 1: `.claude/rules/employees.md`**

Rewrite the P4c bullet's claims:

- `Welcome123!` → a random per-account password generated by
  `generateStartingPassword()` in `functions/employee_accounts.js`, returned to
  the admin and never persisted.
- Delete the paragraph beginning "**What stops them going further is
  `completeEmployeeSetup`'s `email_verified` guard (added 2026-08-08)**" and the
  sentences around it describing the mailbox check, the verification email and
  `refreshEmailVerified`. Replace with: the starting password is now the secret,
  so knowing the address is no longer sufficient; the residual risk is whoever
  holds the address **and** the generated password, and the mitigation is
  operational (create the account when handing the credentials over).
- Delete the paragraph about `AccountSetupScreen` rejecting
  `kDefaultStartingPassword` by name — both the constant and the rule are gone.
- Delete the `kDefaultStartingPassword` hand-mirroring bullet entirely.
- Add: accounts are always created as `role: "employee"`; promotion is an edit
  on `edit_person_sheet.dart` after setup.
- Keep the ORDER-IS-THE-GUARANTEE paragraph — `completeAccountSetup` still
  rotates the password before activating, and that is still only client-side
  ordering.

- [ ] **Step 2: `.claude/rules/security.md`**

In the rate-limit bullet, delete the sentence
"`completeEmployeeSetup`'s `email_verified` check is an identity guard too and
sits in the same slot." The guard order (auth → `assertAdmin` →
`assertPayloadShape` → `enforceDurableRateLimit` → work) is unchanged and stays.

Check whether the fail-closed bullet ("**A guard must FAIL CLOSED on missing
input**") uses `req.auth.token.email_verified` as its worked example — it does.
Keep the rule, and re-point the example at a guard that still exists, noting the
`email_verified` one was removed on 2026-08-21 so a future reader does not go
looking for it.

- [ ] **Step 3: `CLAUDE.md`**

- In the **Auth** invariant, the `invited` exception paragraph is still correct
  — leave it.
- Find and correct any sentence naming `Welcome123!` or "the shared starting
  password" (the Auth bullet references "the shared starting password").
- Verify the **Users collection read rule** bullet still reads correctly; it
  discusses a retired `email_verified` rules clause that was already deleted on
  2026-08-08 and is unrelated to this change. Leave it alone, but confirm it
  does not now read as describing the guard you just removed.

- [ ] **Step 4: `docs/CLOUD_FUNCTIONS.md`**

- `createEmployeeAccount`: remove `isAdmin` from the documented payload; note
  the returned password is random per call and that the role is always
  `employee`.
- `completeEmployeeSetup`: remove `email_verified` from the documented guard
  list and the `email-not-verified` error code from its documented errors.

- [ ] **Step 5: Verify nothing still claims the guard exists**

```bash
grep -rn "email_verified\|Welcome123\|kDefaultStartingPassword\|email-not-verified" \
  CLAUDE.md .claude/rules/ docs/ lib/ functions/ test/ \
  --include=*.md --include=*.dart --include=*.js \
  | grep -v "docs/plans/2026-08-21-simplified-auth"
```

Expected: only historical references that are explicitly dated and marked as
removed. Any live claim is a doc bug — fix it.

- [ ] **Step 6: Commit**

```bash
git add CLAUDE.md .claude/rules docs/CLOUD_FUNCTIONS.md
git commit -m "docs: the starting password is the secret now, not the mailbox"
```

---

## Task 12: Full verification

**Files:** none — this task only runs checks.

- [ ] **Step 1: Analyzer**

```bash
flutter analyze
```

Expected: `No issues found!` — the repo's baseline. Any lint is from this work.

- [ ] **Step 2: Full Flutter suite**

```bash
flutter test
```

Expected: all tests pass. The last recorded baseline is 2352 tests; the count
will be slightly lower here because verification-gate tests were deleted and
slightly higher from the ones added — a net change of a handful is expected, a
drop of dozens is not.

- [ ] **Step 3: Full backend suite and linter**

```bash
cd functions && npm run lint && npx jest && cd ..
```

Expected: lint clean, all Jest suites pass (baseline 1269 tests, plus the
handful added here).

- [ ] **Step 4: BOM scan**

The repo has been bitten by UTF-8 BOMs before, and this work touched ARB files
containing accented French text.

```bash
for f in $(git diff --name-only main...HEAD | grep -E '\.(dart|arb|js)$'); do
  [ -f "$f" ] && head -c 3 "$f" | od -An -tx1 | grep -q 'ef bb bf' && echo "BOM: $f"
done; echo "BOM scan done"
```

Expected: `BOM scan done` with no `BOM:` lines.

- [ ] **Step 5: Confirm the French accents survived**

```bash
grep -n "employees_passwordHiddenUntilReset" lib/l10n/app_fr.arb
```

Expected: the value reads `Réinitialisez le mot de passe pour en générer un
nouveau` with real accented characters, not `é` escapes or mojibake.

- [ ] **Step 6: Commit any fixes and stop**

Do **not** deploy. Deployment is owner-run and has ordering constraints
(backend before the app build) documented in
`docs/plans/2026-08-21-simplified-auth-design.md` and `docs/DEPLOYMENT.md`.

```bash
git status
```

Expected: clean tree.

---

## Deployment note for whoever ships this

Backend first, then the app build — both callable payload shapes changed.

Two windows to be aware of, both self-healing once the app build ships:

1. An admin on the **old** build who creates an account sees the correct
   password in the new-account dialog (it renders the server echo), but that
   person's roster row afterwards shows `Welcome123!`, which is wrong.
2. An old admin build still sends `isAdmin` on both create and Reset password.
   `createEmployeeAccount` **accepts and ignores** it — the key was kept in the
   `assertPayloadShape` allowlist on purpose (see deviation 4), so those builds
   keep working and the role is still hard-coded `"employee"`. The toggle stays
   on screen until the app build ships, but it no longer decides anything.

Run `cd functions && npm run lint` before deploying, clear
`AI_AGENT`/`CLAUDECODE`/`CLAUDE_CODE` from the shell, and never pass `--force`.

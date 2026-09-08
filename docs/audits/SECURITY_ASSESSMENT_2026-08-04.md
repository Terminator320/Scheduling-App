# Security Assessment — ES Pro (Scheduling-App)

**Date:** 2026-08-04
**Target:** `schedulingapp-88727` · branch `redesgin` @ `f9562f32` · app 1.41.0+66
**Method:** adversarial (external attacker with only the shipped artefact) + standards mapping (OWASP MASVS, OWASP Mobile Top 10, OWASP API Top 10, STRIDE) + dependency review
**Authorisation:** granted by the owner for live read-only inspection and live testing, including writes.

Every claim below is backed by a `file:line` reference or a command whose output is reproduced. Nothing is inferred without being labelled as such.

---

## 0. What I did, and what I deliberately did not do

Live, non-destructive probes were run against production. I stopped short of the one destructive test the owner authorised — **creating a real Firebase Auth account** — because the act of creating it *is* the exploit in Finding 1: it would have permanently bricked the chosen email address for in-app onboarding and left an orphaned Auth record needing Firebase-console cleanup. The non-destructive probe below establishes the finding without incurring it.

Verified clean along the way (no drift, no action needed):

| Check | Result |
|---|---|
| Deployed Firestore rules vs. repo | **Byte-identical** (`firebase_get_security_rules` vs `firestore.rules`) |
| Deployed function set vs. `index.js` | **27/27 match**, all `nodejs24`, `us-central1` |
| Secrets in tracked files | None (`AIza…`/`BEGIN PRIVATE KEY`/`sk_live_`/`AKIA` scan clean) |
| `dev/.env` ever committed | **Never** (only `dev/.env.example`) |

---

## 1. Findings

### F1 — HIGH — Anyone on the internet can create Firebase Auth accounts in this project, and can permanently block any email address from ever being onboarded

**Evidence — reproduce with the key that is in this repo's git history:**

```
$ curl -s -X POST "https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=AIzaSyBNH…uY8BU" \
    -H 'Content-Type: application/json' \
    -d '{"email":"probe@example.invalid","password":"a","returnSecureToken":true}'

{"error":{"code":400,"message":"PASSWORD_DOES_NOT_MEET_REQUIREMENTS : Missing password
 requirements: [Password must contain at least 8 characters, …]"}}
```

The response is `PASSWORD_DOES_NOT_MEET_REQUIREMENTS`, **not** `ADMIN_ONLY_OPERATION`. That single distinction proves three things at once:

1. **Client-side sign-up is enabled.** The request cleared the "is registration permitted" gate and failed only on password policy. Had registration been disabled, Identity Platform returns `ADMIN_ONLY_OPERATION` *before* policy evaluation.
2. **App Check is not enforced on Identity Toolkit.** The request carried no App Check token and was processed anyway.
3. **The API key carries no iOS-app restriction covering this API.** `curl` sends no `X-Ios-Bundle-Identifier`; a key restricted to the `net.vogas.scheduling` bundle would have rejected it at the key layer.

A supplying positive: a password policy *is* configured (≥8 chars, upper, non-alphanumeric). That is good and should stay.

**Impact chain.** No direct data access — an account with no `users` doc has no `usersByUid` bridge doc, so `isActiveUser()` and `isAdmin()` are both false and every rule denies (`firestore.rules:21-38`). The damage is elsewhere:

**(a) Permanent, remote, silent denial of onboarding — the serious one.** An attacker pre-registers `newhire@vogas.net`. When the admin later tries to onboard that person, `createEmployeeAccount` runs:

```js
// functions/employee_accounts.js:230-239
const existingAuth = await auth.getUserByEmail(email).catch(() => null);
if (existingAuth) {
  const byUid = await db.collection("users")
      .where("uid", "==", existingAuth.uid).limit(1).get();
  if (byUid.empty || byUid.docs[0].data().status !== "invited") {
    throw new HttpsError("already-exists", "email-exists");
  }
}
```

The attacker's Auth account exists, no `users` doc claims its uid, so `byUid.empty` is true and the callable throws. The admin sees "email exists" for an address nobody in the business has ever used. **There is no in-app recovery**: `deleteEmployeeAccount` requires a `users` doc to delete (`employee_accounts.js:566-580`), and none exists. Fixing it requires the Firebase console. The codebase already recognises this exact state as unrecoverable, in a different context — `employee_accounts.js:286-288`:

> *"it permanently bricks that email for re-creation (the pre-flight above refuses an Auth account whose uid no doc claims). Nothing can recover it in-app."*

**(b) Unbounded account creation** — Identity Platform MAU billing and quota consumption, with no rate limit in front of it (`enforceDurableRateLimit` guards callables, not Identity Toolkit).

**Mapping:** STRIDE **S**poofing + **D**oS · MASVS-AUTH-1 · OWASP API4:2023 Unrestricted Resource Consumption, API8:2023 Security Misconfiguration.

**Fix — eventual.** In Google Cloud console → Identity Platform → Settings → User actions, disable **"Enable create (sign-up)"**. The Admin SDK path (`auth.createUser`, `employee_accounts.js:76`) is an administrative operation and is unaffected, and the current build never self-registers — verified:

```
$ grep -rn "createUserWithEmailAndPassword" lib/     # → no matches
```

**This is blocked, and the block is long.** It would break the **1.37.1+64 build, which is still the shipping App Store build** — its invite acceptance calls client-side `register()` and then `redeemSignupCode` on the next line (`functions/invites.js:160-167`). So this shares a gate with the `#compat-1.37.1` shim retirement. **They are one lifecycle item, not two**, and since 1.41 has not yet been submitted, that gate is months away, not weeks.

**Two routes were considered and rejected as the interim control:**

- *Blocking function (`beforeUserCreated`)* — rejected on two counts. It **requires upgrading the project to Firebase Authentication with Identity Platform**, which is a billing-plan change rather than a toggle ([docs](https://firebase.google.com/docs/auth/extend-with-blocking-functions)). And whether the Admin SDK bypasses blocking functions is **undocumented** — the official page is silent, and the only evidence is an emulator bug report ([firebase-tools #6235](https://github.com/firebase/firebase-tools/issues/6235), [firebase-functions #1219](https://github.com/firebase/firebase-functions/issues/1219)). If it does *not* bypass, this rejects `createEmployeeAccount` itself, because that function mints the Auth account **before** the `users` doc exists (`employee_accounts.js:253-273`). Paying for GCIP to stand up a control that might break onboarding is the wrong trade.
- *API key application restrictions* — worth doing for other reasons (F3), but as an F1 control it is a **speed bump only**: the bundle identifier is sent as a plain request header and is trivially spoofed. Do not count it as a mitigation.

### Fix — interim, and it is strictly better than waiting

**The lockout is not a platform constraint. It is a policy choice in our own code, and it can be reversed without touching Firebase configuration at all.**

`createEmployeeAccount` refuses because it finds an Auth account whose uid no `users` doc claims (`employee_accounts.js:230-239`). That state has exactly three causes, and *all three want the same resolution*:

1. an attacker pre-registered the address (F1),
2. our own rollback `deleteUser` failed (`employee_accounts.js:289-294`),
3. `deleteEmployeeAccount` deleted the doc and then failed on Auth (`employee_accounts.js:609-621`).

Causes 2 and 3 are already known, already logged as `logger.error(… delete it by hand)`, and already have no in-app recovery. So this one change closes a pre-existing gap *and* neutralises F1's impact.

**Do not auto-reclaim silently, and do not adopt the orphaned uid.** Adoption is the dangerous variant: the attacker knows that account's password, so adopting their uid hands them a working credential for the new employee — converting a lockout into a takeover. The safe shape is delete-and-remint, behind an explicit admin confirmation:

- `createEmployeeAccount` distinguishes the orphan case and returns a **distinct** error — `failed-precondition / orphaned-auth-account` — instead of the generic `already-exists / email-exists`.
- The admin surface renders that as an actionable state ("This address has a stale sign-in record with no employee attached") offering **Reclaim**.
- Reclaim calls a separate, explicitly-confirmed admin callable that `deleteUser`s the orphan and then proceeds with normal creation. It inherits the existing 20/hour per-admin limiter.

One caveat to honour in the UI copy: an orphan can also be a **real person whose `users` doc was deleted** — reachable today through the `#compat-1.37.1` `allow delete` grant on `/users` (F5). That person is already invisible and already broken, so deletion is still the correct cleanup, but the confirmation must say what it is destroying rather than presenting itself as routine.

**Net effect:** "permanently bricked, Firebase console required" becomes "one confirmed extra tap". F1's residual impact drops to nuisance account creation and Identity Platform MAU consumption — which is what the eventual sign-up disable will clean up.

---

### F2 — HIGH — The shared starting password is a source-code constant, and it is also handed to *admin* accounts

```js
// functions/employee_accounts.js:40
const DEFAULT_PASSWORD = "Welcome123!";
```
```dart
// lib/features/employees/domain/policies/starting_password_policy.dart:18
const String kDefaultStartingPassword = 'Welcome123!';
```

`CLAUDE.md` documents this as a deliberate, owner-signed-off trade-off, and its stated mitigation is sound as far as it goes: an `invited` user is granted nothing by the rules, so the window is *"can reach the setup screen as this person"*, not *"can read the business"*. Two things the existing write-up does not say:

**(a) The window ends in full account ownership, not just screen access.** Anyone who knows the email can `signInWithPassword` from `curl` today (F1 proves Identity Toolkit takes unattested requests) and hold a valid ID token for that person. Finishing setup requires `completeEmployeeSetup`, which *is* App Check-enforced (`employee_accounts.js:504`) — so it cannot be driven from a script. But it can be driven from a genuine install of the app, which attests normally. The barrier is "install the app", not "be the employee".

**(b) The same constant is used for admin invites.** `createEmployeeAccount` accepts `isAdmin` (`employee_accounts.js:207`) and maps it straight to `role` (`:133`), while the password is unconditional (`:255`, `:280`). So for an admin invite the takeover window yields **admin** — every client record, every address, every phone number. The documented mitigation ("granted nothing") describes the `invited` state correctly but stops one step short of the state the attacker is actually driving toward.

**Mapping:** STRIDE **S**poofing + **E**levation of privilege · MASVS-AUTH-2 · OWASP M1 Improper Credential Usage · API2:2023 Broken Authentication.

**Fix — small, and the plumbing already exists.** The callable already returns the password to the admin surface rather than assuming a constant (`employee_accounts.js:300`, `return {email, password: DEFAULT_PASSWORD}`), and the UI already displays whatever the server echoes back. So replacing the constant with a per-account random password is contained:

```js
const password = generateStartingPassword();   // crypto.randomBytes → policy-compliant
```

`kDefaultStartingPassword` on the Dart side is only a display fallback for rows created earlier (per `CLAUDE.md`), so it degrades to "we don't know this one — press Reset password", which is honest and safe. Worth pairing with an expiry on `invited` so a forgotten invite doesn't sit open indefinitely.

---

### F3 — LOW *(downgraded from Medium — repository confirmed private, 2026-08-04)* — Firebase iOS configuration was committed to git history and remains retrievable

```
$ git log --all --diff-filter=A -- '**/GoogleService-Info.plist'
c089978e  Sun Jun 21 16:04:52 2026  gvogas   setting up ios config

$ git show c089978e:ios/GoogleService-Info.plist
API_KEY         AIzaSyBNH…uY8BU          # redacted in this report — see note
GOOGLE_APP_ID   1:914958291749:ios:8661aad8546e8b5f0d00cc
PROJECT_ID      schedulingapp-88727
GCM_SENDER_ID   914958291749
```

The file was untracked later (`7d5deb96`) and is now correctly gitignored (`.gitignore:14`), but **removal from HEAD does not remove it from history** — the blob is still reachable in any clone or fork.

> The key is **truncated in this report on purpose.** It is already in this repository's history, which is the finding — but there is no reason to also place it in `HEAD`, where a grep of the working tree would surface it. The commit hash and path above are the full reproduction pointer; run the `git show` yourself to see the value.

**Be precise about the severity.** A Firebase API key is *not* a secret in the usual sense — Google documents it as safe to embed in client code; it identifies the project, it does not authorise access. The same key also ships inside the IPA regardless, because `dev/.env` is a bundled Flutter asset (`pubspec.yaml:127`). So this is not "a secret leaked". What it actually is: the artefact that let me run F1's probe without touching the app binary, plus a hygiene signal.

**Owner confirmed 2026-08-04 that the repository is private.** That bounds exposure to people who already hold repo access — who, being contributors, could equally pull the key out of a build. **Downgraded to LOW.** The blob's continued presence is now a hygiene item rather than a security one; the *restrictions* work below is what still matters, and it matters because of F1, not because of this.

**Mapping:** MASVS-STORAGE-2 · OWASP M9 Insecure Data Storage (weak instance) · STRIDE **I**nformation disclosure.

**Fix.** Rotation is low-value (the key ships in the app anyway). The actionable work is on the key's **restrictions**, which F1's probe showed are not currently constraining Identity Toolkit: set *Application restrictions* to the iOS bundle ID `net.vogas.scheduling` (and the Android package + SHA-1 for the dev harness), and *API restrictions* to only the APIs the client genuinely calls. History rewriting is optional and disruptive; I would not do it on a private repo.

---

### F4 — MEDIUM — App Check is very likely not enforced on Firestore or Cloud Storage

```
$ curl -s "https://firestore.googleapis.com/v1/projects/schedulingapp-88727/databases/(default)/documents/users?key=AIza…"
{"error":{"code":403,"message":"Missing or insufficient permissions.","status":"PERMISSION_DENIED"}}
```

The request carried no App Check token and reached the **rules engine** — `PERMISSION_DENIED / "Missing or insufficient permissions"` is a rules verdict. Under App Check enforcement the request is rejected at the App Check layer before rules evaluate. Callables, by contrast, correctly refuse (`{"error":{"message":"Unauthenticated"}}` from `waveGetConnection`), consistent with the explicit `enforceAppCheck: true` on every one of them.

**State the limit honestly:** this is strong evidence, not proof — I could not read the enforcement config directly (no `gcloud` credentials on this machine). Confirm in Firebase console → Security → App Check.

**Impact is defence-in-depth only.** Firestore rules still deny an unattested caller everything, as the probe itself shows. What enforcement buys you is that a *valid* credential — a real employee's stolen ID token — cannot be driven from a script outside the attested app.

**Mapping:** MASVS-RESILIENCE-1 · API8:2023 Security Misconfiguration.

**Fix.** Enable enforcement for Cloud Firestore and Cloud Storage after checking the App Check metrics screen for unverified traffic; it takes up to 15 minutes to take effect ([docs](https://firebase.google.com/docs/app-check/enable-enforcement)). Firestore enforcement supports Android and iOS clients only — no constraint here, since there is no web client.

---

### F5 — LOW (already self-documented) — the `#compat-1.37.1` shim keeps two genuine holes open

Both are annotated in-place with `TODO(george)` and an accurate description of the risk, so this is a tracking item rather than a discovery:

- `firestore.rules:573` — `allow delete` on `/clients`. A 1.37.1 admin can delete a client that has job history, orphaning those appointments — precisely what `deleteClient`'s live `count()` gate exists to prevent (`functions/clients.js:54`).
- `firestore.rules:156` — `allow delete` on `/users`. Orphans every past appointment's `employeeIds` link.
- `functions/invites.js:150-167` — `redeemSignupCode` deliberately has no `email_verified` gate, with a well-argued reason (adding it would break every in-flight invite on the App Store build and roll back the Auth account).

**Recommendation:** give the shim a concrete retirement trigger rather than a vague one — *App Store Connect reports zero sessions on 1.37.1 for 30 consecutive days*. That single event unblocks F1's fix and closes all three of these. `grep -rn "#compat-1.37.1"` → 8 sites.

---

### F6 — LOW — Cleartext URL carries a client address

```dart
// lib/features/maps/address_map_launcher.dart:33
uri: Uri.parse('http://maps.apple.com/?q=$navEncoded'),
```

Every other network path in the app is TLS (scan of `lib/` found this as the only `http://`), and ATS is correctly locked down — `NSAllowsArbitraryLoads` is **`<false/>`** (`ios/Runner/Info.plist:52-55`), which is the right setting and should stay. On a device with Apple Maps installed iOS claims the URL before it hits the network; without it, it goes to Safari over cleartext and then redirects, exposing the client's address in transit.

**Fix:** change to `https://`. One character. **Mapping:** MASVS-NETWORK-1 · OWASP M5 Insecure Communication.

---

### F7 — INFO — The custom URL scheme is claimable by another app

`esproschedule://` is registered in `android/app/src/main/AndroidManifest.xml:60` and `ios/Runner/Info.plist:32`. On Android any app may register the same scheme; on iOS the winner is undefined. The deep link carries only an appointment id (`esproschedule://appointment?id=…`) and no token, so a hijack leaks an opaque identifier and denies the user a working link. Low impact, recorded for completeness. Verified App Links (`https://` + `assetlinks.json`) would remove it if deep links ever carry anything sensitive.

---

### F8 — INFO — npm advisories: 11 reported, 1 critical, and the critical one is not reachable

```
$ npm audit --omit=dev          → 11 vulnerabilities (1 low, 9 moderate, 1 critical)
$ npm ls websocket-driver
firebase-admin@13.10.0 → @firebase/database-compat@2.1.4 → @firebase/database@1.1.3
  → faye-websocket@0.11.4 → websocket-driver@0.7.4
```

The critical advisory ([GHSA-xv26-6w52-cph6](https://github.com/advisories/GHSA-xv26-6w52-cph6), websocket-driver message corruption) is reachable **only** through the Realtime Database client. This project does not use RTDB — verified: `getDatabase` / `databaseURL` / `firebase-admin/database` / `firebase_database` return zero hits across `functions/` and `lib/`. The code is present in `node_modules` but no execution path reaches it.

The remainder are transitive and likewise not on a path that sees attacker-controlled input: `uuid` ([GHSA-w5hq-g745-h8pq](https://github.com/advisories/GHSA-w5hq-g745-h8pq), only when a `buf` argument is supplied), `body-parser` ([GHSA-v422-hmwv-36x6](https://github.com/advisories/GHSA-v422-hmwv-36x6)), and `gaxios`/`retry-request`.

Currency is good: `firebase-admin@13.10.0` already carries the 13.6.1 ReDoS fix and the 13.7.0 bump that resolved CVE-2026-25128 in `fast-xml-parser` ([release notes](https://firebase.google.com/support/release-notes/admin/node)).

**Recommendation: leave as-is.** `npm audit fix --force` would attempt a major bump of `firebase-admin`, which this project has already determined breaks on `firebase-functions` 7.x. Re-check on each `firebase-admin` minor release. This refines the earlier standing note — the reason to leave it is not just "the bump breaks", it is that the flagged code is unreachable.

---

## 2. STRIDE by trust boundary

| Boundary | S | T | R | I | D | E |
|---|---|---|---|---|---|---|
| **Internet → Identity Toolkit** | **F1, F2** | — | — | — | **F1** | **F2** |
| **App → Firestore rules** | ok | ok | ok | ok | ok | ok |
| **App → callables** | ok | ok | ok | ok | ok | ok |
| **Employee → admin data** | ok | ok | — | accepted¹ | — | ok |
| **1.37.1 build → rules** | — | **F5** | — | — | — | **F5** |
| **Functions → Google/Wave APIs** | ok | ok | ok | ok | ok | ok |
| **Device → OS (deep links, storage)** | **F7** | — | — | **F6** | — | — |

¹ Active employees can read every active peer's `users` doc, including email and phone (`firestore.rules:135`). This is a recorded product decision, not a defect — the crew pickers need names and colours, and Firestore rules are document-level so a field cannot be hidden from a document reader. The third-party emergency contact was correctly moved *out* to `users/{id}/private/emergency` for exactly this reason (`firestore.rules:326-337`).

**Repudiation** is thin across the board — Firestore holds `updatedAt` but there is no append-only audit trail of who changed what. For a business of this size that is a reasonable trade-off; worth revisiting if the client list ever becomes regulated data.

---

## 3. OWASP mapping

### MASVS

| Control | Verdict |
|---|---|
| **STORAGE-1/2** | Strong. Keychain at `first_unlock_this_device`, migration handles legacy items, `SecureStorageKeys.all` is a single audit point (`secure_storage_service.dart:27-35`). Weak spot is F3 only. |
| **CRYPTO-1** | No custom crypto. Codes use `crypto.randomBytes` + SHA-256 with an unbiased alphabet (`signup_code_utils.js:8-19`). |
| **AUTH-1/2/3** | **F1, F2.** Otherwise strong: role always re-read from Firestore, never cached (`security.js:214-226`); `deleteAccount` requires re-auth within 5 min (`account.js:17,54`). |
| **NETWORK-1** | ATS enforced, `NSAllowsArbitraryLoads=false`. **F6** is the one exception. No certificate pinning — acceptable, since all traffic is to Google endpoints. |
| **PLATFORM-1/2** | `android:allowBackup="false"`. **F7** noted. No WebView anywhere. |
| **CODE-4** | Payload guards are exemplary — `assertPayloadShape` enforces an explicit key allowlist plus a 4 KB cap (`security.js:34-53`); every callable declares its key set. |
| **RESILIENCE-1** | **F4.** App Check providers are correctly gated: debug providers only under `kDebugMode`, App Attest / Play Integrity in release (`lib/main.dart:117-124`). This is the single most commonly botched line in a Flutter+Firebase app and it is right here. |

### Mobile Top 10 (2024)

M1 Improper Credential Usage → **F2**. M3 Insecure Authentication/Authorization → **F1**. M5 Insecure Communication → **F6**. M8 Security Misconfiguration → **F4**. M9 Insecure Data Storage → **F3**. M2/M4/M6/M7/M10 → no findings.

### API Top 10 (2023) — the callable + rules surface

API1 BOLA → clean; every object access resolves the caller's identity server-side through the `usersByUid` bridge, never from the payload. API2 Broken Authentication → **F1, F2**. API3 Property-level authz → clean; function-owned fields (`uid`, consent stamps, `jobCount`, `wave*`) are denylisted in rules and the `emergencyFieldNotSet` asymmetry is genuinely well-designed. API4 Resource consumption → **F1** (Identity Toolkit is the one unlimited path; every callable is durably rate-limited). API5 BFLA → clean. API8 Misconfiguration → **F1, F4**.

---

## 4. What is genuinely strong — do not regress these

Stated explicitly because several of these are unusual and a future refactor could plausibly "simplify" them away:

1. **`firestore.rules` is the best part of this codebase.** Caller-checked rather than resource-checked predicates keep list queries provable; caps are sized to the widest value a *shipped write path* can produce rather than to the client limit, which is the correct direction and is rarely got right.
2. **`emergencyFieldNotSet`** (`firestore.rules:280-284`) permits removal and refuses a value. A flat denylist would have bricked any doc still carrying the pair — including for `deactivateEmployee`. That reasoning is correct.
3. **Guard ordering is consistent everywhere:** auth → `assertAdmin` → payload shape → rate limit → work. Verified across `places.js`, `clients.js`, `employee_accounts.js`, `wave/callables.js`. Validating before consuming a limiter slot is the right call and is applied uniformly.
4. **No PII in logs.** A targeted grep for email/phone/address/lat-lng/password in every `logger.*` call across `functions/` returned one hit, and it logs `docId` and an error string — not the address. Rate-limit breaches log a 12-char SHA-256 prefix instead of the key (`security.js:174-178`).
5. **App Check provider gating** (`lib/main.dart:117-124`) and **app-lock fail-closed** (`biometric_auth_service.dart:32-34` returns `false` on exception) are both correct.
6. **Deployed state matches source exactly** — no rules drift, no orphaned functions.

---

## 5. Recommended order of work

Revised 2026-08-04 after the owner confirmed 1.37.1+64 is still the shipping App Store build.

| # | Action | Effort | Status |
|---|---|---|---|
| 1 | **Orphaned-Auth reclaim path (F1 interim)** — distinct error + confirmed admin Reclaim | ~3 hr | ship now · **highest value** |
| 2 | Per-account random starting password (F2) | ~1 hr | ship now |
| 3 | `http://` → `https://` in `address_map_launcher.dart:33` (F6) | 1 min | ship now |
| 4 | Enable App Check enforcement: Firestore + Storage (F4) | 15 min | ship now · check metrics first |
| 5 | Set API key application + API restrictions (F3) | 10 min | ship now · speed bump, not a control |
| 6 | Disable Identity Platform sign-up (F1 proper) | 5 min | **blocked: 1.37.1 retirement** |
| 7 | Retire the `#compat-1.37.1` shim, all 8 sites (F5) | ~2 hr | **blocked: 1.37.1 retirement** |

Items 6 and 7 share one gate, and that gate is **months out** — 1.41 has not been submitted, so 1.37.1 will keep drawing sessions well past the point where installs migrate. That is precisely why item 1 was promoted to the top: it removes the damaging half of F1 without waiting for anything, and it closes two pre-existing orphan-recovery gaps on the way.

> **Status update 2026-08-29 — the gate has cleared.** The paragraph above is
> left as written because it records the reasoning at the time, and the call to
> promote item 1 was right. But it is no longer current:
>
> - **Item 7 is DONE.** The `#compat-1.37.1` shim was retired 2026-08-08 (all
>   8 sites, as one unit) and deployed — see `docs/DEPLOYMENT.md`. Its
>   successor carve-out `#compat-1.47.0` has since been opened *and* retired
>   too (2026-08-29), with the fleet on 1.53.
> - **Item 6 is UNBLOCKED and still OPEN.** Disabling Identity Platform
>   sign-up is a **Firebase console action** — it lives in no file in this
>   repo, so nothing here will ever close it and no code change will surface
>   it. It waited on 1.37.1's retirement, which happened three weeks ago.
>   Whoever picks this up: it is the 5-minute half of F1, and item 1's reclaim
>   path (shipped) only covered the damaging half.
>
> The lesson worth keeping is the failure mode, not the dates: a blocked item
> whose gate later clears has nothing to remind anyone. Both of these sat past
> their gate because the block was recorded once and never re-read.

Do **not** buy the Identity Platform upgrade to solve F1 with a blocking function — see F1's rejected routes.

---

## 6. Open questions

1. ~~Is the repository private?~~ **Answered 2026-08-04: private.** F3 downgraded to Low.
2. ~~Is 1.37.1+64 still live?~~ **Answered 2026-08-04: still the shipping App Store build.** Items 6–7 are blocked for months, which is why the reclaim path was promoted to first.
3. **Are API key restrictions configured in the Cloud console?** Still open — I could not enumerate them (no `gcloud` credentials available locally). F1's probe shows nothing currently blocks Identity Toolkit, but not what else may be set.
4. **New, raised by answer 2: when is 1.41 being submitted?** Everything gated on 1.37.1's retirement is downstream of that submission plus the tail of user upgrades. If submission is not imminent, the shim's two delete grants (F5) stay open for the same period, and it is worth deciding whether to accept that or to ship a 1.37.2 patch that removes only the two direct-delete buttons — which would let the grants be withdrawn much sooner than a full 1.41 migration.

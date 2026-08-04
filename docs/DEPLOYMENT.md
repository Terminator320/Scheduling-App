# Deploying a release (backend + app)

Project `schedulingapp-88727`, region `us-central1`.

This is the **release** runbook: what order to do things in, and how to check a
backend change won't break the app builds already on people's phones. For the
mechanics of the deploy command itself — prompts, expected warnings, secret
errors — use the `/deploy` skill, which this doc deliberately does not repeat.

---

## The one rule

> **Deploy the backend BEFORE you cut or ship the app build. Never the reverse.**

Every callable runs `assertPayloadShape(req.data, allowedKeys)`, which throws
`invalid-argument / unexpected-field` on the **first key it doesn't recognise**.
So:

| Direction | What happens |
|---|---|
| **New app build → old functions** | Every affected callable **fails outright.** P4c's build calls `createEmployeeAccount` / `completeEmployeeSetup` / `deleteEmployeeAccount`, which do not exist until it deploys → *no employee can be created or set up at all.* |
| **Old app build → new functions** | Fine **if** each new allowlist is a superset and each new field is optional. That is the contract to preserve — see the check below. |

The asymmetry is the whole point: the backend must always be able to serve the
build behind it *and* the build ahead of it. Ship backend first and you always
have that.

---

## 1. Pre-flight

```bash
flutter analyze                       # 0 issues is the baseline
flutter test                          # full suite
cd functions && npm run lint && npx jest
```

Then validate the rules without deploying (Firebase MCP
`firebase_validate_security_rules`, `source_file: firestore.rules`).

**Expected, ignore:** 3 warnings for `isAvailabilityOnlyChange` — one "Unused
function" and two "Invalid variable name". All three are artifacts of it being
uncalled and disappear when P5 wires it up.

## 2. Find out what is ACTUALLY live

Do not trust this repo's docs for this — they have been wrong. On 2026-08-02
`docs/CLOUD_FUNCTIONS.md` claimed 21 deployed and `recountClientJobs` missing;
production actually had 22 and `recountClientJobs` was live.

Firebase MCP `functions_list_functions`, or:

```bash
firebase functions:list
```

Diff that against the export list in `functions/index.js` — that list is the
source of truth for what *should* exist.

## 3. Diff the backend since the last deploy

Find the last deployed commit in the **Deploy log** at the bottom of this file,
then:

```bash
git --no-pager diff --stat <last-deploy-commit> -- functions/ firestore.rules firestore.indexes.json
```

## 4. Compatibility check — the step people skip

For **every callable whose payload handling changed**, answer two questions.

**(a) Is the new allowlist a superset of the deployed one?**

```bash
# deployed
git show <last-deploy-commit>:functions/employee_accounts.js | grep -n "assertPayloadShape" -A 4
# local
grep -n "assertPayloadShape" -A 4 functions/employee_accounts.js
```

If a key was **removed** from an allowlist, the currently-installed build breaks
the moment you deploy. Keep the key (ignore it server-side) until no build in
the wild still sends it.

**(b) Is every newly-added field optional?**

New fields must read through `optionalString(...)` or `x === true`, never
`requireString(...)`. A new *required* field breaks every older build.

**(c) Rules: is any cap tighter than what a shipped write path can produce?**

This is the most common way a rules deploy breaks the app, and it fails with an
opaque `permission-denied` that names no field. For each new/changed cap in
`isValidUserData` / `isValidClientData` / `isValidAppointmentData`, find the
widest value the **client** and the **callables** can actually write — check
`lib/core/validators/text_limits.dart` and the server's `requireString` limits.
A cap below either one makes matching docs **permanently un-updatable**,
including by `deactivateEmployee`.

Two real examples from this repo:

- `phone` is capped at **40** in rules, not `TextLimits.phone`, because
  `createEmployeeAccount` accepts 40.
- `employeeIds` was briefly capped at **30** (reasoning from
  `whereArrayContainsAny`) — wrong: that is a *query* chunk size, not an
  assignment limit, and nothing bounds the picker client-side. It is **500**,
  tied to `_userStreamLimit`.

Also check the converse: a **client** cap must not exceed the callable's, or the
field accepts input the server rejects as `invalid-argument`, which surfaces to
the user as an unexplained "Something went wrong".

## 5. Deploy

```bash
cd functions && npm run lint
firebase deploy --only functions,firestore:rules
```

- Add `,storage` when `storage.rules` changed. The target is **`storage`** —
  `storage:rules` is not a valid target.
- Add `,firestore:indexes` **only when `firestore.indexes.json` changed.** A new
  query whose index is missing fails `FAILED_PRECONDITION`, which the
  best-effort callers swallow into a silent no-op — so if you changed a query,
  you must deploy indexes.
- **Never pass `--force`.** It treats any prod field override missing from
  `firestore.indexes.json` as drift and DELETES it — this removed all 5 live TTL
  policies once (2026-07-21).
- Single function: `--only functions:<name>`.

## 6. Verify

1. `functions_list_functions` — count matches `functions/index.js` exports, no
   orphans.
2. Spot-check logs for anything you changed (MCP `functions_get_logs`) — look
   for startup errors and for `unexpected-field`, which means an older build is
   hitting a narrowed allowlist.
3. **Smoke-test with the OLD build** if one is installed. This is the check that
   proves step 4 was right.
4. Only now cut / upload the new app build.

## 7. Rollback

Functions are versioned by deploy, not by tag, so rollback = redeploy the
previous source:

```bash
git stash                                   # or branch off
git checkout <last-deploy-commit> -- functions/ firestore.rules
firebase deploy --only functions,firestore:rules
git checkout HEAD -- functions/ firestore.rules
```

Rules roll back instantly and cleanly. Functions take a minute per function.
**Anything already written under the new rules stays written** — a rollback does
not un-write data, so a widened cap that let bad data in is not undone by
reverting the cap.

---

## Repo-specific traps

- **TTL policies live in `firestore.indexes.json`** as `fieldOverrides` with
  `"ttl": true`. They are not console-only state. See the `--force` warning above.
- **TTL expiration offset must be `0`.** Every `expiresAt` in this app stores the
  *absolute* deletion instant; a non-zero offset silently multiplies retention.
  The offset is immutable once set — fixing one means delete → wait for it to
  disappear → recreate.
- **Deploying functions (re)activates App Check** (`enforceAppCheck: true`) on
  the callables. Expected and correct.
- **Secrets must already exist** in Secret Manager or binding fails at deploy:
  `GOOGLE_MAP_API_KEY`, `APNS_AUTH_KEY`, `APNS_KEY_ID`, `APNS_TEAM_ID`,
  `WAVE_FULL_ACCESS_TOKEN`, `WAVE_BUSINESS_NAME`. Only the two functions that
  *bind* `APNS_SECRETS` may read them — otherwise every invocation logs a "No
  value found for secret parameter" warning.
- **Emulator only:** clearing app data regenerates the App Check debug token;
  re-register it in the console or every write fails `permission-denied` while
  cached reads still succeed (making it look collection-specific).

---

## Per-release checklist

Copy this into the release PR / notes:

```
[ ] flutter analyze 0 · flutter test green · functions lint + jest green
[ ] rules validate (only the 3 isAvailabilityOnlyChange warnings)
[ ] recorded what is ACTUALLY live (functions:list), not what the docs claim
[ ] diffed functions/ + rules since the last deploy commit
[ ] every changed allowlist is a SUPERSET; every new field is optional
[ ] no rules cap is tighter than a shipped client OR callable write path
[ ] indexes: unchanged → omit target · changed → include it
[ ] deployed backend  (no --force)
[ ] verified function count + logs
[ ] smoke-tested with the OLD build
[ ] THEN cut the app build
[ ] appended a row to the Deploy log below
```

---

## Deploy log

Keep this current — step 3 depends on it, and it is the only reliable record of
what production is running.

| Date | Commit | Targets | Fns live | Notes |
|---|---|---|---|---|
| 2026-07-18 | — | functions, rules | 21 | `placesReverseGeocode`, travel-aware reminder rebuild |
| 2026-08-01 | `d916b16` | functions, rules | 22 | P3 clients; added `recountClientJobs` |
| 2026-08-03 | `95259db` | functions, rules | 25 | P4 + P4b + **P4c**: added `createEmployeeAccount`, `completeEmployeeSetup`, `deleteEmployeeAccount`; `private/emergency` rule; `isValidAppointmentData`. **Deleted nothing** — `revokeInvite`/`previewInvite` were never deployed (prod had 22, not the 24 an earlier draft of this row assumed), and `createEmployeeInvite`/`redeemSignupCode` were **kept as the `#compat-1.37.1` shim** for the 1.37.1+64 build on the App Store. No deletion prompt; 22 → 25. `firestore:indexes` omitted (file already in sync with prod). Verified post-deploy: 25 functions live, all three shim rules present, zero `unexpected-field` in logs. See the shim note above. |
| _(pending)_ | — | functions, rules, **indexes** | 26 | Client archive + delete: adds `deleteClient` (25 → 26), gated on a live `count()` of the client's appointments; `isValidClientData` accepts `archived` (optional, so 1.37.1 writes still pass). **`allow delete` on `/clients` is KEPT** as a second `#compat-1.37.1` shim entry (owner call 2026-08-03) — 1.37.1+64 ships an ungated Delete button doing a direct `doc.delete()`, and withdrawing the grant would fail it with an opaque `permission-denied`. Nothing in the new build uses it. **`firestore:indexes` IS required** — new `(archived, name, __name__)` composite for the list's server-side `where('archived','==',false)`. **Run `node functions/scripts/backfill-clients-archived.js` against prod FIRST** (dry-run first): Firestore excludes docs missing a filtered field, so any un-backfilled client vanishes from the list the moment the app build ships. Three ordered steps — backfill → deploy → wait for the index to finish building → cut the app build. Never `--force`. |

### The `#compat-1.37.1` shim

1.37.1+64 (`2b1ace5`, head of `origin/notification`) is the build on the App
Store. Verified compatible with this backend without changes: all 8 callables it
uses have byte-identical `assertPayloadShape` allowlists; the new
`isValidAppointmentData` caps equal its `TextLimits` exactly and every field it
writes is a non-nullable `@Default('')` string (so nothing trips the
`null is string` rejection); `isValidUserData` passes its `updateEmployee` field
map; and the push `data` keys are unchanged.

Three things would have broken, so they are shimmed rather than deleted:

| What | Why 1.37.1 needs it |
|---|---|
| `createEmployeeInvite`, `redeemSignupCode` (+ `invites.js`, `signup_code_utils.js`, the `/signupCodes` rules block and its TTL entry) | Called from `firebase_employees_repository.dart:82` and `:109`. Deleting them kills the invite flow and strands anyone mid-invite. |
| `allow delete` on `/users`, and the fourth `/users` read clause (`email_verified` + `invited` + email match) | "Delete employee" is a live button (`employee_details_view.dart:45`); the read clause is how the accept screen finds its own doc while `uid` is still empty. |
| `allow delete` on `/clients` (added to the shim 2026-08-03) | 1.37.1 predates the 2026-08-01 no-delete decision and ships an **ungated** "Delete client" button doing a direct `doc.delete()` (`client_detail_view.dart:72`). Withdrawing the grant fails it with an opaque `permission-denied`. |

**This last one is the only shim entry that leaves a real hole open.** The other
two merely keep retired paths reachable; this one lets a 1.37.1 admin delete a
client that still has appointments and orphan that history — precisely what the
new `deleteClient` callable's live `count()` gate exists to prevent. The
current build never deletes directly, so retiring it costs nothing here.

Retire all of it in one sweep — `grep -rn "#compat-1.37.1"` — once no 1.37.1
build remains in the field. Nothing in the current build calls any of it.

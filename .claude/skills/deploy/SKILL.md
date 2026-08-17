---
name: deploy
description: >-
  Deploy this app's Firebase backend — Cloud Functions, Firestore rules,
  Storage rules — with the required pre-flight lint/tests and post-deploy
  verification. Use whenever the user says deploy, redeploy, "push the
  functions/rules live", asks "what's the command to deploy", wants to check
  that all functions are deployed / everything is up to date, or after edits
  to functions/, firestore.rules, or storage.rules that need to go live.
---

# Firebase Deploy Runbook

Project `schedulingapp-88727`, region `us-central1`. Functions live in
`functions/` and are all re-exported from `functions/index.js` — that export
list is the source of truth for what should exist in prod.

## 1. Pre-flight (never skip)

```bash
cd functions && npm run lint   # Google ESLint, 80-char limit
cd functions && npm test       # jest — all suites must pass
```

Fix failures before deploying — a broken deploy leaves prod half-updated.

## 2. Deploy

```bash
firebase deploy --only functions,firestore:rules,storage
```

- `storage` is the target name, **not** `storage:rules` (invalid target).
- One function only: `--only functions:<name>`.
- Rules only: `--only firestore:rules`.
- Deploying functions (re)activates App Check enforcement
  (`enforceAppCheck: true`) on the callables — that is expected and correct.

## 3. Known prompts and errors — how to answer

- **"functions found in your project but do not exist in your local source
  code: X"** — X was renamed or removed. Before agreeing to delete, confirm
  it's intentionally gone: check `functions/index.js` exports and
  `git log -- functions/`. (Past example: `waveListBusinesses` was
  intentionally removed — deleting was correct.)
- **"The following functions will newly be retried in case of failure:
  propagateClientEdits, syncUsersByUid, waveUpsertCustomer"** — expected;
  these triggers are idempotent with `retry: true`. Proceed. A retry is
  billed like any execution but only fires on failure, so steady-state cost
  is unchanged.
- **"An Internal error has occurred… firebase-tools"** — transient backend
  issue. Wait a few minutes and retry once; if it persists, check the
  function's Cloud logs before changing anything locally.
- **Secret prompts** — `GOOGLE_MAP_API_KEY`, `WAVE_FULL_ACCESS_TOKEN`,
  `WAVE_BUSINESS_NAME` live in Secret Manager only. A prompt about an unbound
  secret means the secret name in code changed — verify before creating a
  new one.

## 4. Verify

- List deployed functions (Firebase MCP `functions_list_functions`, or
  `firebase functions:list`) and diff against the exports in
  `functions/index.js` — every export deployed, no orphans.
- For a function you just changed, spot-check its recent logs
  (MCP `functions_get_logs`) for startup errors.

Report what was deployed, the verification result, and anything skipped or
answered at a prompt — the user should be able to audit every choice made.

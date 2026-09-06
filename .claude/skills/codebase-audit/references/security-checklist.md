# Security audit checklist (Flutter + Firebase, this app)

Walk these for the security pass. Findings are **report-only** — never auto-edit
rules, auth, or secret handling. For each, capture `file:line`, the risk, a
suggested fix, and a confidence level. The last line of defense here is
`firestore.rules` / `storage.rules`; weigh findings against what the rules
actually enforce, not just client code.

## Secrets & config
- No secrets, API keys, tokens, or passwords in source, logs, or the report.
  Server-side keys (Stripe, OpenAI, Wave full-access token, admin tokens) must
  live in Google Secret Manager and be read in a Cloud Function — never in
  a `--dart-define` (those are compiled into the binary, client-config only —
  `dev/.env` and `flutter_dotenv` were retired 2026-09-04 because the file
  shipped as a readable IPA asset).
- `dev/firebase.local.json` and `ios/GoogleService-Info.plist` are gitignored — flag any commit,
  read-into-code, or log of them. The Wave token (`WAVE_FULL_ACCESS_TOKEN`),
  `GOOGLE_MAP_API_KEY` belong in Secret Manager only.
- Grep for hardcoded URLs, bearer tokens, private keys, `password =`, base64
  blobs that look like credentials.

## Auth & access control
- App Check (`FirebaseAppCheck.instance.activate()`) stays active in `main()`.
- Role/`isAdmin` always re-read from Firestore, never SharedPreferences/cache.
- Every signed-in user needs an `active` Firestore `users` doc; gate on
  `!employee.isActive`, not `isDisabled` (which misses `invited`/`''`).
- Employee appointment visibility filter (`employeeIds`) present on every
  appointment query/view.
- Self-activation flows: the account must be unreachable to someone who only
  knows the employee's email address. `completeEmployeeSetup` carried an
  `email_verified` guard for this until **2026-08-21**; it was removed when the
  starting password became a random per-account secret
  (`generateStartingPassword`) and created accounts were forced to
  `role: "employee"`. **Its absence is not a finding** — check instead that the
  starting password is still generated per account and never persisted, and
  that account creation still cannot mint an admin.

## Firestore / Storage rules
- Rules are restrictive and deny-by-default; no broad `allow read, write: if
  true` or `if request.auth != null` without an ownership/role check.
- **Query constraints match rules**: list queries must carry `.where(...)` that
  satisfies a rule clause or they fail `permission-denied`. The `users` read
  rule has **three** clauses — admin, `status == 'active'`, or `uid ==
  request.auth.uid` (own doc). New queries must satisfy one. (The fourth,
  email-matched invite clause was deleted 2026-08-08 with the `#compat-1.37.1`
  shim — don't look for it, and don't re-add it.)
- Client writes to `clients` must not include `waveCustomerId`/`wave`
  (function-owned; rules reject). Confirm `toMap` never emits them.
- Image uploads validated by magic bytes server-side
  (`validateUploadedImage` Storage trigger), not extension.

## Cloud Functions callables
- Admin callables (`waveBootstrap`, `waveImportCustomers`, …) enforce App Check
  + `assertAdmin` + `enforceDurableRateLimit`. Auth-sensitive routes
  (`deleteAccount`, `completeEmployeeSetup`) are rate-limited 5/15 min, and
  `changeEmployeeEmail` 5/hour plus a freshness gate (`assertFreshReauth`,
  non-admin callers only) — counters in `rateLimits/*`, which clients can't
  read or write. Guard order: auth → `assertAdmin`/identity → payload →
  re-auth → rate limit → work.
- Payloads validated: `assertPayloadShape` (reject non-object, >4 KB, unexpected
  keys) and `requireString`/`readSessionToken` (trim, length cap, control-char
  reject) before use. Flag any callable consuming `data.*` without validation.
- No secret/token/PII logged. Errors returned to the client must not leak raw
  Firebase codes, stack traces, or internal detail.

## Client-side trust & input
- All user input validated at the boundary; never trust UI data directly.
- Firebase callable responses cast loosely first:
  `(value as Map?)?.cast<String, dynamic>()` — a direct
  `as Map<String, dynamic>` depends on the plugin's choice of map type. The
  loose cast is the convention here regardless of platform.
- Raw Firebase error codes / stack traces never surfaced in UI text.
- Emails normalized through `normalizeEmail()`
  (`core/validators/email_format.dart`) before any Firestore read/write used in
  a security decision — a hand-spelled `.trim().toLowerCase()` is itself a
  finding.

## General vuln classes to scan for
- Injection where a query/command is built from user input (low risk here —
  Firestore + literal `String.contains` matching, no SQL — but verify no raw
  query string interpolation or `eval`-like dynamic execution slips in).
- Unhandled async in `initState`/stream subscriptions (silent crash → DoS-ish).
- Permissive CORS / open endpoints in Functions.
- Dependency risks: obviously abandoned or known-vulnerable packages in
  `pubspec.yaml` / `functions/package.json` (note, don't bump as part of audit).

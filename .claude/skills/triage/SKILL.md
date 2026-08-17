---
name: triage
description: >-
  Diagnose pasted Flutter/Firebase runtime errors for this app using its
  known error-to-cause map before touching code. Use whenever the user pastes
  an I/flutter log, a [cloud_firestore/...] or [firebase_functions/...]
  error, a Gradle/Kotlin build failure, l10n generation errors, or says "I
  get this error when..." — even if they ask for a fix rather than a
  diagnosis. Root-cause first (rules, App Check token, invite email, token
  propagation), then fix.
---

# Error Triage Map

Order of operations: (1) match the pasted error against the map below,
(2) gather evidence — Firebase MCP `functions_get_logs` for callable errors,
`firestore.rules` for permission errors — (3) state the root cause with that
evidence, (4) then fix. If the evidence contradicts the map, follow the
evidence; the map is priors, not verdicts.

## `[cloud_firestore/permission-denied]`

Check in this order — all four have caused this exact error here before:

1. **Query-vs-rules mismatch.** List/query rules evaluate against query
   *constraints*, not document data. A query missing a `.where()` that the
   rule requires (e.g. `status == 'active'`, or one of the four `users` read
   clauses) rejects the whole query. See `watchEmployees()` for the corrected
   pattern.
2. **Unregistered App Check debug token.** Writes and uncached reads fail
   while cached reads succeed — which makes it look collection-specific.
   The token changes on a new AVD, full reinstall, or `pm clear`;
   re-register it in Console → App Check → Manage debug tokens.
3. **Right after sign-in:** auth-token propagation race. Retry once via
   `retryAsync`/`retryStream` (`lib/core/utils/retry.dart`) — the reference
   uses are the appointments stream and `_retryOnAuthPropagation`.
4. **Surfacing as generic "Something went wrong" in an auth flow:**
   `AuthErrorMapper` only maps `FirebaseAuthException`; a Firestore rules
   rejection falls through to `AuthFailureUnknown`. Check `firestore.rules`
   first, not Auth error codes.

## `[firebase_functions/...]`

- **`invalid-code` on signup** — almost always the registration email ≠
  invite email, not a bad code. Compare the `users` invited doc email, the
  Auth email, and what the user typed. (A distinct `code-email-mismatch`
  error now exists for the case where the code is valid.)
- **`wave/not-bootstrapped`** — run `waveBootstrap` (admin, Settings).
  **`wave/business-ambiguous`** — the `WAVE_BUSINESS_NAME` secret must
  resolve to exactly one Wave business.
- **`failed-precondition` / `internal`** — read the function's logs
  (MCP `functions_get_logs`) before guessing; the client-side message is
  usually truncated.
- **`TypeError` casting a callable response on Android** — nested objects
  come back as `Map<dynamic, dynamic>`; use
  `(value as Map?)?.cast<String, dynamic>()`, never a direct generic cast.

## Build & tooling failures

- **Kotlin/Gradle `compileDebugKotlin`** — `flutter clean` first, then check
  for a plugin version bump in `pubspec.lock` and AGP/Kotlin alignment.
- **`flutter gen-l10n` errors** — a bare key missing its `@key` metadata
  block (`required-resource-attributes: true`), or EN/FR out of lockstep;
  check `lib/l10n/.gen/untranslated.json` for drift.
- **"LayoutBuilder does not support returning intrinsic dimensions"** (or a
  release-mode paint-time null-check on a scroll viewport) — a
  `LayoutBuilder`-based widget (`AutoSizeText`) under
  `IntrinsicHeight`/`IntrinsicWidth`. See the frontend rules.
- **A widget error that never reaches the console** — `FlutterError.onError`
  routes to Crashlytics, not stdout. Temporarily add
  `FlutterError.dumpErrorToConsole(details)` in that handler, or check
  Crashlytics via the MCP tools.

## Ground rules

State the diagnosis and its evidence before editing anything. Cheap checks
first (logs, rules, console state) — most of these errors are configuration
or rules issues where a code "fix" would be wrong.

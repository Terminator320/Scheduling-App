# Codebase Audit — 2026-07-22

> **Implementation status (same session, uncommitted on `notification`).**
> B1 fixed (`feature_tour_host.dart` — reset `_started` on the visibility-changed
> early-return). I2–I5 dead export lines removed (`notification_utils.js`,
> `widget_payload_utils.js`). **I1 deliberately left as-is** — its exports are
> consumed by `live_activity_registry.test.js`, so an export-only removal breaks
> the test, and the constant's comment documents a real client/server TTL hazard
> worth keeping; remove fully only if the future wiring is confirmed abandoned.
> Verified: `flutter analyze` clean · feature_tour tests 12/12 · jest
> notification_utils + widget_payload_utils 56/56 · `npm run lint` clean.

Scope: whole repo (`lib/`, `functions/`, `firestore.rules`, `storage.rules`,
`firestore.indexes.json`, `test/`). Baseline: working tree on branch
`notification` (clean at start, commit `53473a1`).

## Summary
- Scanned: whole `lib/` + `functions/` + rules; 5 parallel deep reviewers
  (security, bugs, dead-code/cleanliness, performance, maintainability) plus the
  deterministic static scan.
- Auto-fixed (safe, in the diff): **0** — `flutter analyze` reports no
  errors/warnings, `dart fix` has nothing to fix, Functions ESLint is clean, and
  there is no analyzer-confirmed dead code. Every remaining finding is a
  judgment call (behavior change or a test-consumed export), so nothing was
  auto-applied.
- Reported for your decision: **7** (⚠️ 0 pre-ship · 🔴 0 security · 🟠 1 bug ·
  🔵 6 dead-export/improvement)
- Verification: `flutter analyze` clean (no NEW issues — tree unchanged) ·
  `flutter test` not run (no code edited) · Functions ESLint clean.

## Auto-applied cleanups (review the diff)
None this run. The static level is already clean:
- `flutter analyze` — no errors or warnings (only ~1000 info-level lints, filtered).
- `dart fix --dry-run` — "Nothing to fix!"
- Functions ESLint — clean.
- Unused-file heuristic — 0 hits.
- Unused-dependency heuristic — 4 hits, all confirmed false positives:
  `google_maps_flutter_ios_sdk9` (the endorsed SPM override, used natively, per
  CLAUDE.md), `build_runner` / `freezed` / `flutter_launcher_icons` (CLI/codegen
  dev tooling with no `package:` import by design).

> Nothing below this line was changed. All items are report-only.

## 🔴 Security findings
**None.** The security pass was a clean sweep of `firestore.rules`,
`storage.rules`, all Cloud Functions callables/triggers, and the recently-worked
client features (presence, live_activity, notifications, siri, feature_tour).
Deny-by-default rules, query-constraint alignment, the guard order
(auth → assertAdmin → payload-shape → rate-limit → work), App Check enforcement,
Secret-Manager-only secrets, and the minimal-PII App-Group payload all hold up.
Three previously-documented accepted tradeoffs remain (contacts-array inner
string caps, lock-screen-readable App-Group container, per-instance Places
limiter) — all already annotated; not new findings.

## 🟠 Bug findings (review required)

### B1 — Feature tour can wedge for the session on a fast tab-switch during auto-start · severity: low · confidence: high
- **Where:** `lib/features/feature_tour/widgets/feature_tour_host.dart:142-157`
- **Problem:** `build()` sets `_started = true` and calls `unawaited(_start())`
  when the tab is visible + ready + unseen. `_start()` awaits
  `tourSeenProvider.ready`, then in a post-frame callback bails at line 157 if
  the hub's current tab changed (`readCurrentOf(context) != widget.tab`). That
  early `return` leaves `_started == true` and never marks the tab seen. Because
  the re-arm branch (`_started = false`) at line 139 only runs when the tab is
  *already seen*, `_started` stays stuck true: returning to the tab re-runs
  `build`, but `visible && ready && !_started` is now false, so the tour never
  re-arms. The tour silently doesn't show for the rest of the session (it does
  reappear on the next app launch, since the seen flag was never set).
  Trigger: switch away from a fresh tab within ~1 frame of it becoming
  visible-and-ready — most likely on a data-dependent tab (Calendar/LiveMap)
  that flips `ready` true just as the user taps another tab.
- **Fix:** reset the guard before the visibility-changed `return` so a later
  visible/ready `build` can retry:
  ```dart
  if (HubShellScope.readCurrentOf(context) != widget.tab) {
    _started = false; // conditions changed; allow a later retry
    return;
  }
  ```
  The other early-returns in `_start` are already safe (`keys.isEmpty` calls
  `_markSeen()`; the `catch` resets `_tourRunning`; `!mounted` means disposed).
  This is the one path that wedges the state machine. Low urgency — purely
  cosmetic (a missed tour that self-heals next launch), no data/permission
  impact.

## 🔵 Areas to improve — dead exports in `functions/` (your decision)
All six are Cloud Functions exports kept alive only by their jest tests, so none
are mechanically dead. Each is a keep-for-future vs. prune judgment call — none
auto-removable. Items I2–I5 are the safest (delete one `module.exports` line
each, keep the in-file constant); I1 is a matched pair.

### I1 — `activityTokenExpiry` + `TOKEN_TTL_MS` are production-dead · impact: low · confidence: high
- **Where:** `functions/live_activity_registry.js:94` (`activityTokenExpiry`,
  exported at `:377`) and `:59` (`TOKEN_TTL_MS`, exported at `:375`).
- **Opportunity:** the module's own comment (`:54-58`) states these are "unused
  by any write path" — Live Activity token rows are written client-side and
  `writeCardMarker` computes `expiresAt` inline at `:180`. The only consumers
  are each other and `__tests__/live_activity_registry.test.js`. Note this
  `TOKEN_TTL_MS` is distinct from `apns_client.js`'s `PROVIDER_TOKEN_TTL_MS`
  (that one is live).
- **Suggested improvement:** either remove the function + constant + their two
  exports + the test block, OR leave them pending the client/server
  reconciliation the comment describes. Don't remove blindly — the comment
  documents an intended future wiring; confirm that's abandoned first.

### I2 — `OVERDUE_LOOKBACK_MS` export line has no importer · impact: low · confidence: high
- **Where:** `functions/notification_utils.js:1176` (export). The constant
  itself (`:39`) is used in-file at `:44` and `:438` — keep it.
- **Suggested improvement:** remove only the `module.exports` entry; the
  constant stays.

### I3 — `CHANGE_RECIPIENT_ROLES` export line has no importer · impact: low · confidence: high
- **Where:** `functions/notification_utils.js:1177` (export). Used in-file at
  `:570` — keep the const. (Its sibling `TIMED_RECIPIENT_ROLES` *is* imported
  elsewhere, so that one stays exported.)
- **Suggested improvement:** remove only the export line.

### I4 — `isCancelledStatus` export line has no importer · impact: low · confidence: high
- **Where:** `functions/widget_payload_utils.js:178` (export). Used in-file at
  `:149` — keep the function.
- **Suggested improvement:** remove only the export line.

### I5 — `ROLLOVER_GRACE_MS` export line has no importer · impact: low · confidence: high
- **Where:** `functions/widget_payload_utils.js:176` (export). Used in-file at
  `:158` — keep the const.
- **Suggested improvement:** remove only the export line.

### I6 — (bundled) verify before pruning any of I1–I5
- **Opportunity:** these exports may have been added for symmetry or a planned
  consumer. Pruning them is safe (tests are the only readers) but low-value.
  If you prune, re-run `cd functions && npm run lint` and the affected
  `__tests__` file.

## 🟡 Code-quality suggestions (optional)
**None actionable.** Convention drift came back fully clean:
- `throw Exception(...)` in `lib/`: 0 hits (all typed `Failure` families).
- Raw `ScaffoldMessenger.showSnackBar`: only the sanctioned sites.
- `FirebaseFirestore.instance` in UI: 0 (all in data/service/bootstrap layers).
- `isDark`/brightness styling branches: 0 (all sanctioned mode-selection).
- Hardcoded colors/spacing/radius: all legitimate (token files, palette rings,
  scrims/contrast helpers, documented sub-4px nudges, theme-invariant hero hues).

Two low-payoff maintainability observations, both correctly **left as-is** per
the anti-abstraction rule:
- The three device-sync controllers (`push_registration_controller`,
  `presence_sync_controller`, `live_activity_registration_controller`) share a
  uid→docId resolve shape, but each gates differently and CLAUDE.md deliberately
  keeps them off `activeUserIdentityProvider` — extracting now risks a wrong
  abstraction. No change.
- `_MainCalendarState` (~483 lines) and `_LiveMapScreenState` (~432 lines) are
  large but already decomposed into single-purpose private builder methods;
  `build()` bodies are widget trees, not logic. File size only. No change.

## Notes / uncertainties
- No `TODO(pre-ship)` / destructive scaffolding found in `lib/` — no Pre-ship
  checklist section this run.
- Test coverage: no gaps found. 185 Dart test files + 28 jest files cover every
  load-bearing controller/repository/pure-domain function; the only untested
  files are device-only method-channel wrappers (documented untestable), whose
  pure builders *are* tested.
- l10n: all 463 `app_en.arb` keys are referenced — 0 orphans. No ARB pass needed.
- No files were edited, so no re-verification beyond the clean baseline was
  required.

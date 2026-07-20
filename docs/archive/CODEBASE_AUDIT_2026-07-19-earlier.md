# Codebase Audit — 2026-07-19

Scope: whole repo (`lib/`, `functions/`, `firestore.rules`, `storage.rules`, `test/`).
Baseline: working tree on branch `notification` (already dirty on 8 unrelated files
before this audit; audit fixes land as a distinct diff).

## Summary
- Scanned: 246 non-generated `lib/` Dart files + `functions/` modules + rules.
- Auto-fixed (safe, in the diff): **10 changes across 10 files** — 1 build()
  sub-widget extraction, 1 decorate-sort micro-opt, ~14 raw spacing literals →
  `AppSpacing` tokens across 8 files.
- Reported for your decision: **0 security · 0 bugs · 3 improvements (all low/opt)**.
- Verification: `flutter analyze` clean (no errors/warnings vs baseline) ·
  touched tests 27/27 pass · `functions` ESLint clean.

**Headline: this codebase is exceptionally clean.** Five parallel deep reviewers
(security, bugs, dead-code/cleanliness, performance, maintainability) found **zero
security issues, zero actionable bugs, zero dead code, and zero orphaned l10n
keys.** Performance is already at the optimization frontier for small-business
data volumes. The only findings were minor, mechanical, and are now applied.

## Auto-applied cleanups (review the diff)
| File | Change | Why |
|---|---|---|
| `lib/features/calendar/widgets/views/details_view_body.dart` | Extracted `_ClientSection` sub-widget; `build()` 116 → ~60 lines | Meets repo's own ~60-line `build()` guideline (frontend.md) |
| `lib/features/presence/domain/live_map_aggregator.dart` | `sortedByProximity` now decorate-sorts (distance computed once/point) | Was recomputing haversine O(n log n)× in the comparator |
| `lib/features/calendar/screens/main_calendar_screen.dart` | `EdgeInsets.fromLTRB` literals → `AppSpacing.sp4/sp8/sp16` | Design-token discipline |
| `lib/features/calendar/widgets/fields/month_year_picker.dart` | `EdgeInsets.symmetric` 16/8 → `sp16/sp8` | Design-token discipline |
| `lib/features/calendar/widgets/fields/appointment_address_field.dart` | `EdgeInsets.symmetric` 8/4 → `sp8/sp4` | Design-token discipline |
| `lib/features/settings/widgets/views/text_size_view.dart` | `EdgeInsets.symmetric` 4/8 → `sp4/sp8` | Design-token discipline |
| `lib/features/employees/widgets/views/employee_details_view.dart` | 10 `SizedBox` + 1 `EdgeInsets` component → tokens (2px nudges left raw) | Design-token discipline |
| `lib/features/settings/widgets/cards/settings_tiles.dart` | `EdgeInsets.only` left/bottom → tokens (top:2 nudge left raw) | Design-token discipline |
| `lib/features/clients/widgets/views/clients_list_view.dart` | 3 skeleton `SizedBox(8)` → `sp8` | Design-token discipline |
| `lib/features/clients/widgets/sections/additional_contacts_section.dart` | 6 `SizedBox` → tokens | Design-token discipline |

> Full detail is in `git diff`. Nothing below this line was auto-changed.

## ⚠️ Pre-ship checklist
No new ship-blocking scaffolding surfaced by this audit. The standing pre-ship
items remain as documented in CLAUDE.md / prior audits (iOS App Attest env flip
to `production`, Firestore ledger TTL policy enablement in console, on-device
verification of push/presence/widget). None are code defects; all are Mac/console
launch switches. See `docs/plans/APP_STORE_CONNECT_SUBMISSION.md` (this session).

## 🔴 Security findings
**None.** All 11 `onCall` callables enforce App Check; guard order is
auth → assertAdmin → payload validation → durable rate-limit → work; validation
runs before the limiter (malformed bursts can't burn a legit caller's window);
rules deny-by-default with server-side role resolution via the `usersByUid`
bridge; no secrets in `dev/.env` beyond restricted client keys; no PII in logs;
role/`isAdmin` never cached (splash fast-path routes in at least-privilege).

## 🟠 Bug findings
**None actionable.** The reviewer traced presence reentrancy, the throttle-clock
rollback, iOS background-location defaults, live-map admin gating, the travel
sweep bounds/indexes, the bridge presence purge truth table, and the splash/main
startup reorder — all correct by construction.

## 🔵 Areas to improve (report-only)
### I1 — `functions/notification_utils.js` is 977 lines · impact: low · confidence: high
- **Where:** `functions/notification_utils.js` (whole module)
- **Opportunity:** Largest single Functions module — diffing, message-building,
  EN/FR tables, timezone math, ledger helpers, and 4 orchestrators. Cohesive and
  well-tested (725-line jest file), so this is navigability only, not a defect.
- **Suggested improvement:** *Only if it grows further*, split the self-contained
  EN/FR `_MESSAGES` table + `buildNotificationMessage`/`buildDigestMessage`/`_fmt`
  cluster into a `notification_messages.js` sibling. Do **not** split preemptively.

### I2 — `appointment_history_view.dart` build() ~67 lines · impact: low · confidence: medium
- **Where:** `lib/features/clients/widgets/views/appointment_history_view.dart:262`
- **Opportunity:** Marginally over the 60-line guideline, but already decomposed
  into `_buildPaged`/`_buildFiltered`/`_skeleton`/`_buildEmptyState`.
- **Suggested improvement:** Leave as-is unless it grows; noted for completeness.

### I3 — (resolved this run) `live_map_aggregator` haversine recompute
- Was flagged by performance review; **fixed** via the decorate-sort above.

## 🟡 Code-quality suggestions
**None outstanding.** Convention adherence is strong: only the 3 sanctioned
`ScaffoldMessenger` sites, zero direct `FirebaseFirestore.instance` in UI, zero
`throw Exception(...)` (typed `Failure` families throughout), no `isDark`-branch
styling, no raw `Color(0xFF…)` outside the token file + documented theme-invariant
hues. The spacing literals were the only drift and are now tokenized.

## Notes / uncertainties
- Native `ios/Runner/AppDelegate.swift` and Android manifest background-location /
  capability wiring were out of Dart/JS scope and are device-only verifiable —
  not audited from source; covered by the App Store submission runbook.
- All 418 `app_en.arb` template keys resolve to a generated-getter usage — no
  orphaned l10n keys; no ARB pruning needed.

# Codebase Audit — 2026-07-18

Scope: whole repo (`lib/`, `functions/`, `firestore.rules`, `storage.rules`, `test/`).
Baseline: clean working tree on branch `notification` (HEAD `938691a`).

> **Update — findings implemented (2026-07-18).** The user said "do all", so 8 of
> the 9 findings were implemented (uncommitted): **S1** (rules now cap
> address-family + `contacts` — needs a `firestore:rules` deploy to take effect),
> **B1** (overdue sweep `.orderBy("startTime","desc")` + corrected log), **B2**
> (`upsertLocation` returns success; presence throttle rolls back on a failed
> write; repo test asserts the new contract), **I2** (travel context query capped
> at `CONTEXT_QUERY_MAX = 50`), **I3** (geocode cell coarsened 4→3 decimals),
> **I4** (`DateOnly.dateOnly` extension replacing the 8 day-floor sites), **I5**
> (`month_year_picker` controllers hoisted to State + disposed), **I6** (new
> `places_admin_gate.test.js` locking the App Check→admin gate on both untested
> places callables). Two functions test query-fakes gained `orderBy`/`limit`
> stubs to match the new chains. **I1 was intentionally NOT done** — on
> inspection `_buildMaster` is ~55 lines and already delegates to cohesive
> `_appearanceCard`/`_accountCard`/`_securityCard`/… helpers (the "165-line
> build()" was an inflated count); a full widget-extraction would thread ~10
> callbacks and state values through a screen that performs irreversible account
> deletion and sign-out — churn/risk out of proportion to the gain, against the
> `code-quality.md` anti-defaults. Verification: `flutter analyze` **No issues
> found** · `flutter test` **922 pass** · functions ESLint **clean** · functions
> jest **365 pass**. Only remaining action: deploy the S1 rules change when ready.

## Summary
- Scanned: 258 Dart files (`lib/`) + 152 test files + `functions/` (15 top-level + 8 `wave/` modules) + rules.
- Auto-fixed (safe): **0 code changes.** `dart fix` had nothing to apply; Functions ESLint clean; no dead code, orphan files, unused deps, or convention drift found. (One non-code action: regenerated stale gitignored l10n — see Notes.)
- Reported for your decision: **9**  (⚠️ 0 pre-ship · 🔴 1 security · 🟠 2 bugs · 🔵 6 improvements)
- Verification: `flutter analyze` **No issues found** (after l10n regen) · `dart fix` nothing · `functions` ESLint clean.

This is a disciplined, heavily-tested codebase. No critical or high-severity issues. All findings are low-severity defects (defense-in-depth) or proactive improvement opportunities. Every load-bearing invariant (App Check, status allowlist, role-from-Firestore, image magic bytes, presence self-only rules, ledger idempotency, travel-time degradation) was verified intact.

**Top 3 to look at first:**
1. **I2 (med-high)** — unbounded per-employee future-schedule read runs every 5 min and grows with the forward booking calendar (`travel_utils.js:354`).
2. **B1 (low)** — overdue "job finished?" sweep fetches oldest jobs first; the candidate cap can starve the newest-overdue jobs at high volume (`notification_utils.js:858`).
3. **I1 (high impact)** — `settings_screen.dart` `_buildMaster` is a ~165-line `build()` in a 610-line god file; good extraction target.

## Auto-applied cleanups
None. Nothing below this line was auto-changed — the tree is as you left it (aside from the gitignored `lib/l10n/.gen/` regeneration noted at the bottom, which is never committed).

## ⚠️ Pre-ship checklist
None. No `TODO(pre-ship)` scaffolding, no `enforceAppCheck: false` carve-outs, no destructive testing wiring found. Nothing ship-blocking surfaced.

## 🔴 Security findings

### S1 — `isValidClientData` leaves address-family & `contacts` fields un-capped · severity: low · confidence: med
- **Where:** `firestore.rules:258-267` (rule) vs `lib/features/clients/domain/models/client_record.dart:101-116` (`toMap`)
- **Risk:** The rule length-caps `name`/`businessName`/`firstName`/`lastName`/`phone`/`mobile`/`email`, but `toMap` also writes `address`, `apt`, `city`, `province`, `country`, `postalCode`, and a `contacts` array — none type/length-checked. A client write can land arbitrarily large strings and an arbitrarily large `contacts` array (bounded only by Firestore's 1 MB doc ceiling). Not exploitable by non-admins (clients collection is admin-only for create/update), so this is defense-in-depth against a compromised admin session / mass-assignment oversize write — the same threat model the existing caps in this function already defend.
- **Fix:** Extend `isValidClientData` to type- and length-check the address-family fields and bound the `contacts` array size, matching the posture of the fields already covered. Needs a `firestore:rules` deploy.

## 🟠 Bug findings

### B1 — Overdue sweep fetches oldest jobs first, can starve newest-overdue at cap · severity: low · confidence: high (mechanism), low (impact)
- **Where:** `functions/notification_utils.js:858-864` (`runOverduePromptSweep`)
- **Problem:** The query filters `startTime` in `[now-48h, now]` with `.limit(OVERDUE_SWEEP_MAX)` and **no explicit `orderBy`**, so Firestore implicitly orders by `startTime` **ascending** → the cap returns the *oldest* jobs. But `selectOverdueCandidates` keeps only jobs whose `endTime` is within the last 24h — the *recently* overdue ones, which have the *largest* `startTime`. Under a >500 open-job backlog the sweep spends its budget on old jobs (many already filtered away) while genuinely just-overdue jobs are deferred. The warning log at `:865-869` ("newest jobs deferred") describes the wrong outcome as if intended. Only bites at 500+ open jobs in 48h — far above this small-business scale.
- **Fix:** Add `.orderBy("startTime", "desc")` before `.limit()` so the cap keeps the newest candidates, and correct the comment/log rationale. Confirm the existing composite index covers the `status in` + `startTime` desc ordering before deploy.

### B2 — Presence throttle clock advances before the (error-swallowing) upload resolves · severity: low · confidence: med
- **Where:** `lib/features/presence/application/presence_sync_controller.dart:178-182` (movement) and `:199-203` (heartbeat)
- **Problem:** `_lastUploadAt = now` is set synchronously *before* `unawaited(_upload(position))`, and `PresenceRepository.upsertLocation` swallows all failures. A transient Firestore write failure still advances the throttle clock as if it succeeded, suppressing the next movement write for up to 2 min and the next heartbeat for up to 10 min. Two consecutive failed writes could let the presence doc approach the 25-min server staleness window and demote the travel-time reminder from live GPS to the address fallback. Self-heals via the 10-min heartbeat well inside the window, so single failures are tolerated.
- **Fix:** Advance `_lastUploadAt` only after the upload resolves successfully, or have `upsertLocation` return success/failure so the controller doesn't burn the throttle window on a failed write.

## 🔵 Areas to improve

### I1 — `settings_screen.dart` god file / ~165-line `_buildMaster` · impact: high · confidence: high
- **Where:** `lib/features/settings/screens/settings_screen.dart:148` (`_buildMaster`, ~165 lines; file is 610 lines)
- **Opportunity:** The master list mixes app-lock toggle, text-size, notifications, language, Wave, sign-out, and delete-account rows in one method — the largest real build-method complexity in the app.
- **Suggested improvement:** Extract a `_SettingsMasterList` widget or per-section sub-widgets (each row-group already reads as a unit). Proportionate; reduces the god file.

### I2 — Unbounded per-employee future-schedule read every 5 min · impact: med-high · confidence: high
- **Where:** `functions/travel_utils.js:354-359` (`runTravelAwareReminderSweep`)
- **Opportunity:** The origin-context query `array-contains employeeId` + `endTime > now-4h` + `orderBy(endTime)` has **no `.limit()` and no upper bound** — it reads every current + all future appointments per employee, but `decideOrigin` only consumes intervening jobs starting within 90 min and previous jobs ended within 4h. With this business's repeating pre-booked series, an active employee can carry dozens–hundreds of future docs; this runs 288×/day per employee with an imminent job → tens of thousands of wasted reads/day.
- **Suggested improvement:** Bound the read to what `decideOrigin` uses. Simplest single-inequality option: add a `.limit(N)` safety cap. Better (needs a composite index): also constrain `startTime <= now+90min` to drop the far-future tail. Tradeoff: a very long in-progress job whose `endTime` exceeds the cap would fall out of the "intervening" prong and degrade to the GPS/prev/30-min fallback — which the design already tolerates. Pick the bound.

### I3 — Reverse-geocode call amplification for moving staff + unbounded keepAlive cache · impact: low-med · confidence: med
- **Where:** `lib/features/maps/application/maps_providers.dart:23-24` (4-decimal ≈11 m cell) + `:55` (`ref.keepAlive()`); watched per row at `staff_roster_sheet.dart:225` and `staff_info_card.dart:47`
- **Opportunity:** Presence fixes arrive at 250 m granularity but the geocode key rounds to ~11 m, so a *moving* driver produces a new key → a new billable `placesReverseGeocode` call on almost every fix, one per active driver while the roster/map is open. Each success is `keepAlive`'d → one never-disposed cached provider per 11 m cell (small, but unbounded over a long session). The ≈11 m rounding is effectively a no-op at 250 m fix spacing.
- **Suggested improvement:** Round the geocode cell coarser (3 decimals ≈110 m, or align to the 250 m fix filter) so consecutive fixes along a drive collapse to fewer cells; optionally skip re-geocoding while a marker is `stale`. keepAlive growth is secondary and resolves once the call rate drops.

### I4 — `DateTime` day-floor duplicated 8× across 4 files · impact: low-med · confidence: high
- **Where:** `day_route_screen.dart:52,57`, `main_calendar_screen.dart:139,149`, `dashboard_aggregator.dart:70,99`, `widget_sync_service.dart:64,241`
- **Opportunity:** `DateTime(x.year, x.month, x.day)` is repeated 8 times — a subtle footgun if someone forgets to zero a component.
- **Suggested improvement:** A single `extension on DateTime { DateTime get dateOnly => DateTime(year, month, day); }` in `core/`. Proportionate (crosses the 3+ threshold), not premature abstraction.

### I5 — `month_year_picker` scroll controllers built inline in `build()` and leaked · impact: low · confidence: high
- **Where:** `lib/features/calendar/widgets/fields/month_year_picker.dart:109,130`
- **Opportunity:** Two `FixedExtentScrollController`s are constructed inline in `build()` and never disposed — re-allocated on every rebuild and leaked. Short-lived picker dialog, so impact is small.
- **Suggested improvement:** Hoist them into `State` fields created in `initState` and disposed in `dispose()`.

### I6 — `placesAutocomplete` / `placesGetDetails` have no direct admin-gate test · impact: low · confidence: high
- **Where:** `functions/places.js` (only `placesReverseGeocode` is tested)
- **Opportunity:** These are thin proxies over the tested `security.js` guards, but a test asserting the App Check + auth + `assertAdmin` gate is actually wired would prevent a regression on billable endpoints.
- **Suggested improvement:** Add a small jest test mirroring `test/places_reverse_geocode.test.js` for the two untested places callables. Optional.

## 🟡 Code-quality suggestions (optional)
- Five raw `EdgeInsets` integers where an `AppSpacing` token exists (`text_size_view.dart:216`, `employee_details_view.dart:333`, `main_calendar_screen.dart:488`, `month_year_picker.dart:74`, `splash_screen.dart:143`). All are either the documented intentional exceptions (48 px splash inset, sub-4 px nudges) or trivial — cosmetic, not blocking. The project's spacing-tokenization decision already sanctions these.
- A handful of long-but-flat declarative `build()` methods (`appointment_form_fields.dart:169`, `weekly_bar_chart.dart:38`, `image_viewer.dart:211`, `app_calendar_view.dart:66`) exceed ~60 lines but are linear layout — splitting adds indirection without reducing complexity. Left as-is per the anti-defaults; noted only for awareness.

## Notes / uncertainties
- **Stale l10n regeneration:** the initial static scan reported 6 `undefined_getter` errors for `liveMap_*` keys — the ARB keys exist in both `app_en.arb`/`app_fr.arb`, but the gitignored `lib/l10n/.gen/` output was stale. Ran `flutter gen-l10n`; analyzer then returned **No issues found**. `.gen/` is never committed, so there is no code change to review — just re-run `flutter gen-l10n` if you see those errors locally.
- l10n ARB: 418 keys each side, **zero EN/FR drift, zero orphaned keys** — no l10n prune pass needed.
- Dependency heuristic flagged `freezed`, `build_runner`, `flutter_launcher_icons`, `google_maps_flutter_ios_sdk9` — all verified **false positives** (active codegen, CLI dev tool, endorsed iOS SPM override). No unused deps.
- Device-only surfaces (background GPS stream, image pipeline, biometric lock) were reasoned about statically, not exercised — verify presence/notification behavior on a real device per the project's device-only testing note.

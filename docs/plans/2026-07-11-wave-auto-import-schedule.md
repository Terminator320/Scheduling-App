# Wave automatic-import cadence

**Date:** 2026-07-11
**Status:** Design approved — not yet implemented

## Goal

Let an admin choose whether the app imports customers from Wave automatically,
and how often. Wave customers are added on both sides, so an admin who adds a
customer in Wave wants it to appear in the app without remembering to press
**Import customers**.

The Settings → Wave section gains a cadence picker with three choices:

- **Off** — automatic import disabled (today's behavior). The manual **Import
  customers** button remains the only trigger.
- **Weekly** — a scheduled import runs when the last automatic run was more than
  7 days ago (or never).
- **Monthly** — same, at more than 30 days.

The manual **Import customers** button stays in all three modes for an
immediate, on-demand run.

## Why this is safe

`importCustomers()` (`functions/wave/customers.js`) is already idempotent —
keyed on `waveCustomerId`, a re-run updates existing client docs rather than
duplicating them, and archived Wave customers are skipped. Running it on a
schedule reuses that exact path; no new import logic is needed.

## Non-goals

- No "last automatic import" line in the UI (decided minimal — YAGNI).
- No near-real-time / daily / hourly cadence — weekly and monthly only.
- No change to the App→Wave write-back path (`waveSyncWorker`, `waveUpsertCustomer`).

## Architecture

### Storage

The cadence lives in the existing rules-locked, server-owned `wave/connection`
doc (the app cannot read or write the `wave` collection directly):

- `importSchedule: 'off' | 'weekly' | 'monthly'` — **absent → `'off'`**, so
  existing connections keep today's manual-only behavior after deploy.
- `lastAutoImportAt: Timestamp` — stamped after each successful scheduled run.
  Absent means "never auto-imported" → a weekly/monthly schedule is immediately
  due on its first daily check.

### Backend (`functions/wave/`)

**`import_schedule.js` (new, pure — jest-testable sibling)**

```
isImportDue(schedule, lastAutoImportMs, nowMs) -> boolean
```

- `'off'` → always `false`.
- `'weekly'` → `lastAutoImportMs == null` OR `nowMs - lastAutoImportMs > 7d`.
- `'monthly'` → `lastAutoImportMs == null` OR `nowMs - lastAutoImportMs > 30d`.
- Unknown/other schedule → `false` (fail safe; treat like off).

Kept in a pure sibling with no Storage/Firestore load, per the CLAUDE.md
testing note (`onSchedule` modules can't be `require()`d in jest because they
eagerly resolve a bucket).

**`waveScheduledImport` (new `onSchedule`, in `callables.js`)**

- `schedule: "every 24 hours"`, `secrets: [WAVE_FULL_ACCESS_TOKEN]`,
  `maxInstances: 1`. No App Check, no durable rate limit — it is
  server-triggered, at most once/day.
- Flow:
  1. Read `wave/connection` (reuse `readWaveBusinessId` + the cached
     `readWaveBusinessIdCached` gate so an unconnected install pays no
     per-run import work). Also read `importSchedule` and `lastAutoImportAt`.
  2. If not connected → return (nothing to do).
  3. If `!isImportDue(schedule, lastAutoImportMs, Date.now())` → return.
  4. `await importCustomers({businessId, graphql})`.
  5. On success, `update` `wave/connection` with
     `lastAutoImportAt: FieldValue.serverTimestamp()`.
  6. Log a summary line (`imported/updated/skippedArchived/pages`), matching
     the manual callable's log shape. Wave errors are classified via
     `classifyWaveError` and logged (not thrown to a user — there is none).

Daily granularity is deliberate: weekly/monthly cadences don't need finer
resolution, and a once-a-day scheduler keeps invocation cost negligible.

**`waveGetConnection` (extend)**

Return `importSchedule` alongside the existing `connected/businessId/
businessName`, defaulting to `'off'` when the field is absent. This is the only
read path the app has into `wave/connection`.

**`waveSetImportSchedule` (new `onCall`, in `callables.js`)**

- `enforceAppCheck: true`, `assertAdmin`, `assertPayloadShape(req.data, new
  Set(["schedule"]))`.
- Validate `schedule` is exactly one of `'off' | 'weekly' | 'monthly'` →
  else `HttpsError('invalid-argument', 'wave/invalid-schedule')`.
- Require an existing connection (a `businessId`) → else
  `HttpsError('failed-precondition', 'wave/not-bootstrapped')` (the picker is
  only shown when connected, but guard server-side anyway).
- `update` `wave/connection.importSchedule`. Return `{schedule}`.

**`index.js`** — re-export `waveScheduledImport` and `waveSetImportSchedule`
under their original names (thin wiring surface, per CLAUDE.md).

### Client (`lib/features/wave/`)

**`WaveImportSchedule` enum (new, domain)** — `{ off, weekly, monthly }` with
`raw` and `fromRaw(String)` (unknown/empty → `off`). Single string↔enum mapper;
no per-widget switch.

**`WaveConnection`** — add `final WaveImportSchedule importSchedule;`, parsed in
`fromMap` from `map['importSchedule']` via `WaveImportSchedule.fromRaw`,
defaulting to `off`. Update `==`/`hashCode`.

**`WaveService.setImportSchedule(WaveImportSchedule schedule)`** — calls the
`waveSetImportSchedule` callable with `{'schedule': schedule.raw}`, maps errors
via `WaveErrorMapper`, mirrors the loose-cast + logging pattern of the existing
methods.

**`WaveSettingsSection`** — when connected, between the business-name row and
the Import button, add a tappable "Automatic import" row (label + current
cadence value + chevron) that opens `showAdaptiveActionSheet` (the app's
canonical "pick one option" chooser) with Off / Weekly / Monthly. On pick:
- guard against the no-op (same value) — return early;
- set a local busy flag (synchronously, before the await, per the submit
  reentrancy rule);
- call `WaveService.setImportSchedule`;
- on success: update local `_connection` copy, `ref.invalidate(
  waveConnectionProvider)`, success notice `wave_autoImportUpdated`;
- on `WaveFailure`: error notice via `toLocalizedMessage`.

The picker reads its current value from `_connection ?? connectionAsync.value`,
same precedence the section already uses for connection status.

### Localization (`lib/l10n/app_en.arb` + `app_fr.arb`, lockstep)

New keys, each with an EN `@key` block:

- `wave_autoImportLabel` — "Automatic import" / "Importation automatique"
- `wave_autoImportOff` — "Off" / "Désactivée"
- `wave_autoImportWeekly` — "Weekly" / "Chaque semaine"
- `wave_autoImportMonthly` — "Monthly" / "Chaque mois"
- `wave_autoImportUpdated` — "Automatic import updated." / "Importation
  automatique mise à jour."

(French strings are a first pass; refine at implementation.) Run
`flutter gen-l10n` after editing (the ARB-edit hook regenerates automatically).

## Testing

**jest (`functions/wave/__tests__/`)**
- `isImportDue`: off → false; weekly/monthly with `null` last → true; just under
  vs. just over each threshold; unknown schedule → false.

**Flutter widget test (`test/features/wave/`)**
- Settings section connected: tapping the cadence row opens the sheet; choosing
  Weekly invokes `WaveService.setImportSchedule(weekly)` and shows the success
  notice. Mock `WaveService`; provide the l10n delegates + `ProviderScope` the
  section already requires.

`waveScheduledImport` itself is an `onSchedule` module (can't be `require()`d in
jest) — its logic is covered by testing `isImportDue` and the reused
`importCustomers` path (already tested).

## Deploy

`firebase deploy --only functions,firestore:rules` — but **rules need no
change** (the app never touches `wave/` directly; both new server touchpoints
are Admin-SDK). So: `firebase deploy --only functions`. Run
`cd functions && npm run lint` first.

## Open questions

None — design approved 2026-07-11.

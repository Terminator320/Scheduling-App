# Archived docs

Completed plans/specs and superseded audit snapshots — kept for history, not
maintained against the current code. Started 2026-07-10; last updated
2026-07-19.

**Do not treat these as accurate references.** For current state see
`docs/ARCHITECTURE.md`, `docs/CLOUD_FUNCTIONS.md`, and the active plans in
`docs/plans/`.

## Executed plans / specs (feature shipped)
- `INVITED_SIGNUP_REDESIGN.md` / `_PLAN.md` — canonical spec + implementation
  checklist for the one-time signup-code invite flow (shipped 1.19.4). Both live
  here now; CLAUDE.md and `docs/CLOUD_FUNCTIONS.md` cite the spec as the flow's
  reference, so it is the one archived doc still treated as authoritative. The
  checklist predates dropping `regenerateSignupCode`.
- `2026-06-06-error-animation.md` / `-design.md` — field-error shake/animation
  (shipped; now built into `LabeledTextField` / `AnimatedFormFieldWrapper`).
- `2026-07-01-ios-adaptive-feel.md` / `-design.md` — Cupertino-on-iOS adaptive
  layer (shipped; `lib/core/adaptive/`).
- `2026-07-08-admin-dashboard.md` — admin dashboard (shipped;
  `lib/features/dashboard/`).
- `2026-07-08-push-notifications.md` — FCM push triggers + iOS home-screen
  widget (implemented; `functions/notifications.js`,
  `lib/features/notifications/`, `lib/features/home_widget/`; functions + rules
  deployed to prod 2026-07-11). Residual ops items (Firestore ledger TTL policy,
  on-device verify) are tracked in CLAUDE.md, not here.
- `2026-07-11-wave-auto-import-schedule.md` / `-plan.md` — Wave auto-import
  cadence (deployed 2026-07-11; `functions/wave/import_schedule.js`,
  `waveScheduledImport` / `waveSetImportSchedule`). The design doc's "not yet
  implemented" status line was stale at archive time.
- `2026-07-13-offline-hardening.md` — offline guards + durable photo-upload
  retry queue (Tasks 1–6 implemented/committed on `notification`).
- `2026-07-13-day-route-view.md` — employee day-route timeline + multi-stop
  Google Maps hand-off (Tasks 1–5 implemented on `notification`;
  `lib/features/calendar/screens/day_route_screen.dart`). Task 6 is a
  device-only verification pass.
- `2026-07-09-travel-time-notifications.md` — travel-aware "time to leave"
  reminders with live background GPS presence (implemented + committed on
  `notification`, shipped in 1.31.0+50; `functions/travel_utils.js`,
  `lib/features/presence/`). Residual ops items (Routes API console enable +
  functions deploy + Mac Time-Sensitive entitlement) are tracked in CLAUDE.md,
  not here.
- `2026-07-15-live-staff-map.md` — admin-only Find-My-style live staff map
  (implemented + committed on `notification`, shipped in 1.32.0+51;
  `lib/features/presence/screens/live_map_screen.dart`, `LiveMapAggregator`,
  `placesReverseGeocode`; **functions + rules deployed to prod 2026-07-18**,
  client Maps keys + Geocoding API provisioned). Residual items (verify Routes
  API is enabled/restricted, on-device pass, App Store Location privacy
  declaration) are tracked in CLAUDE.md and the iOS handoff, not here. The
  plan's own header status line was stale (pre-deploy) at archive time.
- `2026-07-19-ios-live-activities.md` / `-implementation.md` — the iOS Live
  Activity "time to leave" Lock Screen card (built 2026-07-19; **functions,
  rules, and the two required composite indexes deployed to prod 2026-07-19**
  in 1.34.1). `functions/apns_client.js`, `live_activity_*.js`,
  `lib/features/live_activity/`, `ios/ScheduleWidget/JobLiveActivity.swift`.
  **Both header status lines were stale at archive time** — the design doc still
  said "NOT started, NOT approved to build" and the implementation doc still
  called the APNs secrets a deploy blocker; the secrets were created 2026-07-19
  and the deploy has happened. Residual item (on-device verification) is tracked
  in CLAUDE.md and `ios/ScheduleWidget/LIVE_ACTIVITY_README.md`, not here.

## Superseded audit snapshots
Point-in-time whole-repo audits; each run's findings were implemented at the
time. Superseded by later audits — the active one is
`docs/audits/CODEBASE_AUDIT.md` (2026-07-19 deep pass).
- `CODEBASE_AUDIT_2026-06-26.md`
- `CODEBASE_AUDIT_2026-07-01.md`
- `CODEBASE_AUDIT_2026-07-04.md`
- `CODEBASE_AUDIT_2026-07-07.md`
- `CODEBASE_AUDIT_2026-07-19-earlier.md` — the first 2026-07-19 run, which
  reported zero security findings and zero bugs. The **same-day deep pass that
  replaced it contradicts that conclusion** (it found the disabled-employee read
  hole and the two missing indexes), so this snapshot is kept only as a record
  of what a shallower pass missed. Its auto-applied spacing/token cleanups
  remain valid.
- `WAVE_REVIEW_FINDINGS.md` — Wave-integration ultra review (fixes applied
  2026-06-21; Wave shipped).

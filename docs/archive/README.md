# Archived docs

Completed plans/specs and superseded audit snapshots — kept for history, not
maintained against the current code. Archived 2026-07-10.

**Do not treat these as accurate references.** For current state see
`docs/ARCHITECTURE.md`, `docs/CLOUD_FUNCTIONS.md`, and the active plans in
`docs/plans/`.

## Executed plans / specs (feature shipped)
- `INVITED_SIGNUP_REDESIGN_PLAN.md` — implementation checklist for the one-time
  signup-code invite flow (shipped 1.19.4). The canonical spec it points to,
  `docs/plans/INVITED_SIGNUP_REDESIGN.md`, is still live. This checklist also
  predates dropping `regenerateSignupCode`.
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

## Superseded audit snapshots
Point-in-time whole-repo audits; each run's findings were implemented at the
time. Superseded by later audits — the most recent readiness audit
(`docs/audits/CODEBASE_AUDIT.md`, 2026-07-08) is still active.
- `CODEBASE_AUDIT_2026-06-26.md`
- `CODEBASE_AUDIT_2026-07-01.md`
- `CODEBASE_AUDIT_2026-07-04.md`
- `CODEBASE_AUDIT_2026-07-07.md`
- `WAVE_REVIEW_FINDINGS.md` — Wave-integration ultra review (fixes applied
  2026-06-21; Wave shipped).

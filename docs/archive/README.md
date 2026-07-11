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

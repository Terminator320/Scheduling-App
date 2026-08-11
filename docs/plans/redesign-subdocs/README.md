# Redesign sub-documents — P1 through P4c

**All complete.** These are the record of how each redesign project was built —
kept for rationale and task history, not as a description of the current
screens. For that read `CLAUDE.md`, which carries every invariant they
established. The program spec is `../2026-07-29-redesign-program.md`; the
projects it still owes are **P5, P6, P7 and P7b**.

Left here rather than moved to `docs/archive/` because `CLAUDE.md`,
`docs/CLOUD_FUNCTIONS.md` and the dated audit snapshots cite these paths.

| Project | Plan / handoff | State |
|---|---|---|
| **P1 Foundation** | `2026-07-30-p1-foundation.md` · `-HANDOFF.md` | Shipped (`c64de55`..`51e6386`). |
| **P2 Calendar** | `2026-07-30-p2-calendar.md` · `-HANDOFF.md` | Shipped (`d4b487f`). The plan is **superseded in part** — the first hardware pass (P2b) overturned five of its decisions; its own banner says so. |
| **P3 Clients** | `2026-08-01-p3-clients.md` · `-HANDOFF.md` | Shipped; backend deployed 2026-08-01. Its §5b `#pre-ship` delete hole is **closed** — the flag file was deleted 2026-08-03 and `allow delete` on `/clients` was withdrawn 2026-08-08. |
| **P4 Team** | `2026-08-02-p4-team.md` · `-HANDOFF.md` | Shipped; deployed 2026-08-03. §6.3's time-to-leave toggle and §6.4's self-service rules clause are **P5 work** and are tracked in `../README.md`. §7's deploy has long since run — do not re-run it from this doc. |
| **P4b Auth + invites** | `2026-08-02-p4b-auth-invites.md` · `-HANDOFF.md` | ⚠️ **WITHDRAWN.** The signup-code flow was replaced by P4c the same day and deleted from production 2026-08-08. Only the restyled sign-in / reset-password surfaces survive. Nothing in its "still open" list is live work. |
| **P4c Employee accounts** | `2026-08-02-p4c-HANDOFF.md` | Shipped; deployed 2026-08-03, hardened 2026-08-08 with the `email_verified` guard. Still the design reference for how an employee gets an account — `CLAUDE.md` and `docs/CLOUD_FUNCTIONS.md` both point here. Its §5 production migration is **closed**: prod was queried on 2026-08-08 and had zero `invited` users. |
| **Device test** | `2026-07-30-p1-p2-DEVICE-TEST.md` | **STILL OPEN — the one live document in this folder.** ~87 of its 95 checks have never been run. |

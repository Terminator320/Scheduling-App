# Time off booked over existing jobs — the clash alert

**Date:** 2026-08-24
**Status:** BUILT 2026-08-24, in the same pass as the sibling doc — one
release, one shared repository method (`findClashingAppointments`).
**Mockup:** https://claude.ai/code/artifact/859aa929-7801-472d-a45b-46914493df62
**Sibling:** `docs/plans/2026-08-24-assignee-availability.md` — the same clash
arriving from the other direction. Read both together; they share a lookup.
**Build order (owner call 2026-08-24): BOTH TOGETHER**, one release, so the
shared repository method is written and tested once.

An admin books a PERSONAL BLOCK — a day off or any other personal time — for
someone who already has client jobs inside that span. The block saves, then a
dialog lists the jobs it ran into and offers to swap the crew on each.

**Scope widened 2026-08-24 (owner call): ANY personal block, not just a day
off.** Day-off-only was recommended and rejected. See "What widening exposed"
below — it turns two latent problems into certain ones, and both must be solved
for this to be buildable.

This is the reverse of the picker work: dimming booked crew stops the clash
forming FORWARDS (assigning someone already off). It does nothing about jobs
already on the books when the time off goes in. This closes that hole.

This document is the DESIGN RECORD; the behaviour it describes now ships.

## Owner calls that framed it

Asked and answered 2026-08-24, in this order:

1. **Advisory, not blocking.** Closing the alert without fixing anything leaves
   the time off saved and the jobs untouched. Matches the posture of the
   existing `showBusyConflictDialog`, which warns and lets you push through.
   Time off is a fact about a person; the schedule does not get to veto it.
2. **Swap only** — no "take them off", no "cancel the job". Swap is the one fix
   that always leaves the job legal: `appointment_form_validator.dart:97`
   rejects an empty crew, so removing the only assignee would write a state the
   form itself forbids.
3. **The alert fires AFTER the save**, and each swap writes immediately. Nothing
   is held in limbo, so a swap survives closing the dialog.
4. **Any personal block triggers it**, not only a day off (2026-08-24).

## Chosen: Option A, "one dialog, swap in place", with three changes

Three options were rendered — A a dialog with in-row swap, B a full worklist
sheet, C a one-job-at-a-time stepper. **A was picked**, with three changes made
during the refinement:

- **The list scrolls between a pinned head and footer.** A's stated weakness was
  that a fortnight off would break the dialog. The count now sits in the header
  (`26 – 28 AUG · 3 JOBS`), and long lists group under day headings.
- **A settled row offers Undo.** The write lands immediately, so without this
  there was no way back at all. It sits on the ROW, not in the footer — the
  footer's job is dismissal, and one shared undo could not say which job it
  meant.
- **Only one row opens at a time.** Opening another closes the first, so the
  list shifts once rather than accumulating expanded rows.

### Anatomy

Built on `showBusyConflictDialog`
(`lib/features/calendar/widgets/dialogs/busy_conflict_dialog.dart`) — same
warning badge, title, mono when-line, rows, footer actions. Reuse it rather than
growing a second dialog vocabulary.

Row states: **idle** (struck-through name, anyone else on the job still shown,
`Swap`), **open** (blue outline, crew strip of people free in that job's window,
each labelled with when), **done** (green, "{name} takes this one", `Undo`),
**stuck** (amber, "Everyone else is booked", `Open job`).

Footer is `Leave them` / `Done`. **Never "Cancel"** — nothing here is undone by
dismissing, and Cancel would read as cancelling the time off, which this dialog
cannot do.

## The three extra states

| State | Behaviour |
|---|---|
| Long absence (14 jobs) | Scrolls between pinned head and footer, grouped by day heading; count in the header |
| Nobody can cover a job | Row goes amber, says "Everyone else is booked", hands off via `Open job` |
| Time off for several people | Jobs group under each person; each person's swap list excludes the others booked off with them |

## Copy

| Key | English |
|---|---|
| `calendar_timeOffClashTitle` | `{name} still has jobs booked` (+ plural twin for a crew) |
| `calendar_personalBlockClashBody` | `The block is saved. These jobs still have {name} on them.` — was `The time off is saved`; "time off" is wrong for a dentist block |
| `calendar_swapPersonFor` | `Swap {name} for` |
| `calendar_swap` | `Swap` |
| `calendar_takesThisJob` | `{name} takes this one` |
| `calendar_everyoneElseBooked` | `Everyone else is booked` |
| `calendar_openJob` | `Open job` |
| `calendar_leaveThem` | `Leave them` |
| `common_undo` | `Undo` — new, no such key exists yet |
| `common_done` | `Done` — **already exists**, reused |

## What widening exposed

Two consequences of covering every personal block. Neither is optional.

### The alert REPLACES the pre-save busy prompt for a personal save

The Save-time conflict check already runs for personal appointments today, so
booking a day off over Marc's jobs ALREADY pops "Schedule Conflict — Marc is
already booked / Book anyway". Adding this alert on top gives two dialogs about
the same clash, back to back. Widening to every personal block makes that
certain rather than occasional.

So: when the appointment being saved `isPersonal`, skip the
`AddEventBusyEmployees` / `EventDetailsBusyEmployees` prompt entirely and let
this alert handle it after the write. The new alert is strictly more useful —
it names the jobs and offers a fix, where the old prompt only names the person.
The old prompt stays exactly as it is for ordinary client jobs.

This is a change to EXISTING behaviour, not just new surface. Pin it with a test
that a personal save no longer returns the busy outcome.

### The clash list is CLIENT JOBS ONLY

A swap must never be offered on another personal block: "swap Marc for Nadia"
on Marc's own dentist appointment is nonsense — that block belongs to him. The
lookup therefore excludes `isPersonal` records from the results, even though
they are real clashes for busy-ness purposes.

Consequence to accept: booking a personal block that overlaps only ANOTHER
personal block raises no alert at all. That is correct — there is nothing here
to fix.

## Data — shared with the sibling doc

The alert needs the clashing CLIENT jobs for one employee over a span: a
**one-shot read at save time**, which is exactly the shape `findBusyEmployees`
already has. New repository method beside it, same chunked
`whereArrayContainsAny` batching (30-item cap), same `isTerminalStatusRaw` skip,
plus the `isPersonal` exclusion above — returning the clashing
`AppointmentRecord`s rather than the busy employees.

**The picker does NOT share the live-ness, only the method** (owner call
2026-08-24). One-shot-for-both was recommended and rejected: the picker stays
live, watching the range the calendar already holds open and falling back to
this same one-shot read only when the chosen span falls outside it. See the
sibling doc for that half. This alert has no live path — it runs once, at save.

Consequence to keep straight when building: the two surfaces answer the same
question through the same repository method, but the picker reduces a stream on
top of it. If the clash rules ever diverge between them, the bug is that the
rule lives in two places — put it in the repository method, not in either
consumer.

## Constraints the build must honour

- **A swap hits that occurrence only, never the series.** A weekly job's
  Wednesday slot is what clashes; the person is not off every Wednesday. Do not
  route this through `appointment_series_editor.dart`.
- **Swap replaces, never removes** — see owner call 2 above.
- **Terminal-status jobs are not a clash**, matching `findBusyEmployees`.
- **Editing a day off's dates re-runs the check** on the days added. Extending
  Mon–Tue to Friday is the common case.
- **A swap is an ordinary appointment write**, so it must clear the repository's
  search cache like every other write path (`_invalidateSearchCache()`).
- **Undo is per row and lives only as long as the dialog.** Afterwards the swap
  is an ordinary edit to that job; there is no cross-session undo and the design
  must not imply one.

## Out of scope

- Notifying the swapped-in person — **already handled, verified 2026-08-24.**
  `notification_policy.js` (the `before && after` update branch) diffs
  `employeeIds` and accumulates `removed` for whoever drops off and `assigned`
  for whoever joins. A swap gets both pushes for free. No new notification work,
  and nothing to add — but don't "fix" that diff while touching swap writes.
- Any "best replacement" suggestion or ranking. The crew strip is a plain list
  of who is free.
- Employees booking their own time off. `main_calendar_screen.dart:452` gates the
  add affordance on `isAdmin`, so only admins reach this flow at all.

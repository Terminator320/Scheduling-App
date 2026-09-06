# Assignee picker — who can't take the job

**Date:** 2026-08-24
**Status:** BUILT 2026-08-24. See the assignee-picker bullets in `CLAUDE.md`
and `.claude/rules/appointments.md` for the invariants this shipped with.
**Mockup:** https://claude.ai/code/artifact/aaca67d5-ddd6-4056-b37e-d8d4f77779c1

Design for what the assignee picker does when someone can't take the job on the
chosen date. Today it offers every assignable crew member regardless of date,
and a clash surfaces only at Save, through `findBusyEmployees` →
`AddEventBusyEmployees` → a force-through prompt.

This document is the DESIGN RECORD; the behaviour it describes now ships.

## Two owner calls that framed it

Asked and answered before the mockup (2026-08-24):

1. **Unavailable crew stay VISIBLE, dimmed — not hidden.** The original ask was
   "make them not show up". Hiding was rejected: the roster silently shrinks and
   an admin looking for Marc has nothing on screen explaining where he went.
2. **ANY conflict dims, not just a day off.** A booked job counts the same as
   time off. See the consequence under "Known cost" — this is the one decision
   here that removes an existing capability.

## Chosen: Option C, "short chips, reasons underneath", with two changes

Three options were rendered — A put the reason on the chip as a tag, B split the
panel into Available / Not free groups, C dimmed the chip and explained
underneath. **C was picked**, with two changes made during the refinement:

- **The per-chip glyphs are dropped.** C originally marked an off chip and a
  booked chip with two different symbols. They did no work the reason lines
  weren't doing better, and an undecodable symbol is worse than none. Dimming
  now means only "can't pick this"; the line says why.
- **The reason list collapses past two.** Originally one line per clash, which
  buries Save on a holiday Monday. Now: two lines, then
  "{count} more aren't free", tapping to expand.

### The chip

One unavailable treatment, identical for off and booked: dashed outline, no
fill, avatar at ~42% opacity, name in `ink40`. It should read as an empty slot,
not a button. Not tappable.

### The lines

Below a hairline divider, `ink60` at 12.5px, the person's name in `ink80`
semibold, and a right-aligned mono figure:

- a day off gets the **date range** (`26–28 Aug`) — it has no clock, and
  rendering `00:00–23:59` would be noise dressed as precision;
- a booked job gets the **window** (`08:00–12:00`), which is the actionable
  half: it shows that starting at noon would free them.

Chips keep shortening to the first name as they do now, and the lines use the
same short name so a chip and its line are obviously one person. Two Marcs take
a last initial in both places.

## The states

| State | Behaviour |
|---|---|
| Ordinary clash | Dim chips, one line each |
| More than two clashes | Two lines, then "N more aren't free" (expandable) |
| Already assigned, then books time off | Chip stays SELECTED and tappable; line reads "{name} is off — still on this job" |
| Already assigned, then the DATE moves onto a booking | Same: chip stays selected and tappable, line reads "{name} is on another job — still on this one". The copy table originally had only the time-off variant, so this case reused the refusal sentence and read as though the person had been rejected. It is not an edge case — the add flow seeds the date from the tapped day, so picking crew and then moving the job is ordinary, and it is the main way a real clash still reaches the Save-time prompt |
| Nobody free | Per-person lines give way to one amber sentence naming what to do next |
| No date picked yet | No dimming, no divider — everyone offered |

## Copy

Every new key needs an EN + FR pair and a `@key` block in EN.

| Key | English |
|---|---|
| `calendar_dayOffIsOff` | `{name} is off` — **already exists**, reused |
| `calendar_assigneeOnAnotherJob` | `{name} is on another job` |
| `calendar_assigneeOffStillOnJob` | `{name} is off — still on this job` |
| `calendar_assigneeBookedStillOnJob` | `{name} is on another job — still on this one` — added at build time; see below |
| `calendar_assigneesMoreNotFree` | `{count, plural, =1{1 more isn't free} other{{count} more aren't free}}` |
| `calendar_nobodyFreeThen` | `Nobody is free {when}. Try another time, or book the job and assign someone later.` |

## Constraints the build must honour

These aren't visual choices — each would be a bug if it went the other way.

- **An already-assigned employee is NEVER dimmed**, even when off. Dimming makes
  them unremovable, and worse: `mergeRetainedAssignees`
  (`calendar/domain/assignee_resolver.dart`) re-appends every original assignee
  missing from the ACTIVE set, so a person who is active but merely hidden from
  the picker is NOT retained — they'd be silently unassigned instead. The
  already-assigned test therefore wins over the unavailable test, exactly as
  `offerableAssignees` already narrows rather than unions. Route the rule
  through that same file.
- **The edit sheet must exclude the appointment being edited** from the conflict
  scan, or its own assignees read as clashing with themselves.
  `findBusyEmployees` already takes `excludeAppointmentId`.
- **Availability must be date-DERIVED and live**, re-resolving as the date, the
  end date, the times and the all-day flag change.
- **A day off makes someone busy on purpose.** `AppointmentRecord.isTimeOff` is
  deliberately NOT filtered out of `findBusyEmployees` — booking time off is
  exactly how a person is made to read as unavailable. Don't "fix" that while
  wiring this up.
- **Cancelled and terminal-status jobs are not a clash** — `findBusyEmployees`
  already skips them via `isTerminalStatusRaw`.
- **A PERSONAL block must dim NOBODY** (added at build time, after review —
  this document did not anticipate it and the omission was a bug in the shipped
  build until it was caught). Dimming means untappable, and the person a day
  off is FOR is the one most likely to have jobs that day: dimming them made
  the absence unbookable, and made the sibling doc's clash alert — which exists
  precisely to clean up afterwards — unreachable. `watchAssigneeAvailability`
  takes `isPersonal` and answers `AssigneeAvailability.none`. Same carve-out,
  same reason, as both controllers skipping the Save-time busy prompt for a
  personal save.

## Where the availability data comes from — DECIDED 2026-08-24

**The picker stays LIVE** (owner call). The one-shot read was recommended and
rejected; build it live.

Live must not mean a second listener. `appointmentsInRangeProvider` keyed by a
span-derived range is a near-subset of the `forCalendar` range the calendar
already holds open, and forking one is exactly what `forWeekBucketOf` and
`forMirrors` carry long comments against. So:

- **Watch the range the calendar already has open** and re-scope to the span in
  Dart, the way `employeeJobsTodayProvider` reduces a range it does not own.
  The add sheet is opened FROM that screen, so the chosen day is almost always
  inside it. Zero extra reads, genuinely live.
- **Fall back to a one-shot read when the span falls outside that window.**
  This is not optional: without it, picking a date past the open range makes
  every clash invisible and the picker silently reports everyone as free, which
  is worse than not dimming at all. The fallback is not live — dimming there
  re-resolves when the date or time changes.

The sibling doc (`2026-08-24-timeoff-clash-alert.md`) uses the one-shot read at
save time regardless, so the repository method is shared; only the picker adds
the live path on top.

## Known cost

**Deliberate double-booking stops being reachable from the picker.** Today a
clash warns at Save and can be forced through; once booked crew are un-tappable
that route is gone for any clash the picker already knew about. Flagged to the
owner at decision time and accepted. If putting two people on one big job turns
out to matter, the fix is to keep BOOKED chips tappable with a warning look and
dim only time off — the original Option-1 scope.

**The Save-time check is NOT the rare backstop this section first called it.**
It was written up as firing only on races, which underrates the ordinary case:
the picker only gates the moment of TAPPING, and an assignee already selected
is never dimmed. The add flow seeds the date from the tapped day, so
"pick the crew, then move the job" is a normal edit — and it lands a genuine
clash on Save every time, where the prompt is the only thing that catches it.
The cost above is therefore narrower than stated: it bites only when you try
to ADD someone to a job whose date is already set. Two consequences to keep:
the prompt must stay for client jobs, and the already-on-the-job line has to
read as an explanation rather than a refusal
(`calendar_assigneeBookedStillOnJob`).

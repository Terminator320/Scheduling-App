# Day-off strip: render the typed title

**Status:** BUILT 2026-08-25 — strip AND opened view, verified on an iOS 26.5
simulator. `flutter analyze` clean, 716 tests green across every surface that
renders the card.
**Mockup:** https://claude.ai/code/artifact/362b344f-adbd-4cd4-bf2e-b7391a7b1c2f
**Surface:** `_DayOffStrip` in `lib/features/calendar/widgets/cards/appointment_card.dart`

## Problem

A day-off block can carry a typed title — the form offers the field, optional, for
any personal block (`appointment_form_fields.dart`, the "Service title" row). The
strip on the agenda throws it away: `_DayOffStrip` reads `appointment.title` only
as a *fallback* for when nobody is assigned, so "Vacation" and an untitled block
render identically and the reason is reachable only by opening the block.

Two secondary findings from the same read:

- **In light mode the strip has no container.** Its fill is
  `statusColors.neutralContainer`, which resolves to `AppColors.paper` — the same
  value as `scaffoldBackgroundColor`. The chip is invisible against the page, and
  two stacked days off run together. Dark mode is a 7% white wash and does show.
- The trailing `DAY OFF` caption restates the sentence beside it, spending the one
  slot a reason could have used.

## Chosen direction — Option C, "reason leads"

Picked from three (A: reason on a second line; B: reason inline after a middot;
C: reason as the headline). No grafts from A or B.

The typed reason becomes the primary line, the person drops to the caption
beneath it, and a dashed crew rail replaces the job card's solid bar.

### One layout, both cases

Owner call during review: **a plain day off renders through the same strip, not a
second branch beside it.** The widget resolves one `headline` and one nullable
`caption` up front — title if typed, else the "is off" sentence; the sentence
below only when it was not already used as the headline — then builds a single
row.

Accepted consequence: an untitled block's sentence moves from `bodyMedium` / 400
to `titleSmall` / 600, so it renders slightly heavier and darker than today. That
is the price of one shape instead of two that drift, and it was chosen knowingly.

### Anatomy

| Part | Spec |
|---|---|
| Container | `neutralContainer` fill, `colorScheme.outline` hairline, `r12`, min-height 44 |
| Rail | 3px, dashed 4-on 4-off, `crewColorOf(theme, lead.color)`, inset 8px top/bottom, 9px left |
| Avatar | `AvatarSize.xs` (20px), lead assignee, 0.55 opacity once past |
| Headline | `titleSmall` on `palette.textBody` |
| Caption | `bodySmall` on `palette.textTertiary`; omitted when the sentence is the headline |
| Trailing | `monoType.groupLabel` DAY OFF, or `StatusChip` once the last day has passed |
| Padding | 9px vertical, 12px right, 10px between rail and avatar |

Titled height ~55px; untitled floors at the existing 44.

## Decisions baked in

- **The `colorScheme.outline` hairline is part of the change**, not a follow-up —
  it is what gives the strip an edge in light mode, and it is most of why the row
  reads as unfinished today.
- **The crew rail reverses a documented call — raised and approved.**
  `_DayOffStrip`'s doc comment argues the opposite today: "the crew colour
  survives only as the avatar, which is identity; the BAR is what says *a crew is
  on this job*, and a day off has no job to be on." The reversal was flagged in
  review and the owner approved keeping the rail. The reasoning that replaces it:
  a **dashed** rail reads as the negative of the bar rather than a quieter version
  of it, and it is what lets two stacked absences be told apart before any text is
  read. **Building this includes rewriting that comment** to record the new
  reasoning — the old one must not be left standing beside code that contradicts
  it.
- **No new strings.** `calendar_dayOffIsOff`, `calendar_dayOffWasOff` and
  `calendar_dayOff` cover every line; the title is user text, not a localized
  string. Nothing to add to either ARB.
- **Nothing stored changes.** The title already saves. Every change is inside
  `_DayOffStrip`, so the employee picker, the availability dimming and the
  personal-block clash carve-out are untouched.

## Left open

- **Multi-day runs still render identically each day.** A three-day vacation is
  three strips reading the same thing, with no "day 2 of 3" counter — job cards
  get one from `AppointmentDaySlice`, this does not. Out of scope; its own pass
  if it proves annoying.
- ~~**The 2× text-scale case wants a widget test.**~~ Done — plus coverage for
  the placeholder-title trap, the no-crew case and the rail's presence.

## Found while building

**An untitled day off is not blank on disk.** `add_appointment_sheet.dart`
stores the localized `calendar_personal` placeholder when the title field is
left empty, so `appointment.title` is the literal "Personal" for every unnamed
block. The old strip dodged this by never reading the title; reading it means
`_reason` has to reject that placeholder explicitly, or the headline reads
"Personal" on every untitled day off — the exact outcome the sentence-names-the-crew
rule exists to prevent. Pinned by a test.

## Follow-on: the opened view (same day, user request)

Tapping a strip that read "Vacation" opened a detail screen that had dropped
the word — `_DayOffBody` led with the joined crew names and used the title only
as a fallback, the exact bug the strip had, for the exact same reason.

It now leads with the reason and puts the person beneath it in
`palette.textTertiary`, falling back to the person as the headline when nothing
was typed. Because that made the rule live in two widgets, it was given one
owner: `dayOffReason` (`calendar/domain/day_off_reason.dart`), pure and
directly tested — the blank case, the localized "Personal" placeholder, and the
no-subject case where the title is already the sentence's subject.

# Calendar holidays — Québec statutory, Greek Orthodox, construction

**Status:** BUILT 2026-08-29. Mockup signed off the same day.
**Mockup:** https://claude.ai/code/artifact/97403f25-03e8-4a98-9ab8-5d1e77f0f8ed

Display-only holiday markers on the calendar. Nothing is blocked, warned or
dimmed — an emergency call on Saint-Jean saves exactly as it does today.

## Decisions

| Decision | Choice | Why |
|---|---|---|
| Holiday set | Québec statutory + Greek Orthodox Easter + CCQ construction holiday | Owner call. The business is Montréal-based; the Orthodox pair is a personal/staffing observance, not a legal one. |
| Data source | **Computed in Dart**, zero dependencies, zero I/O | Every date is a fixed day, an nth-weekday rule, or Easter-derived. Rejected a bundled JSON (goes stale silently — ship 2026–2030 and the markers vanish in 2031 with no error) and an API (breaks the app's offline posture for data that never changes). |
| Behaviour | Display only | Owner call. No picker dimming, no Save-time prompt. |
| Easter | **Both** Good Friday and Easter Monday for Québec; the Greek set adds **Πάσχα itself** (Friday, Sunday, Monday) | Owner call. QC law makes it the employer's pick between the two; this shop takes both. Easter Sunday is not statutory but is the central Orthodox day. |
| Grid marker | A 2px rule under the day number | Survives all four token states with no added element. |
| Marker hue | **Teal** statutory, **purple** Orthodox, **ochre** construction | Owner call: one colour per set. See *Why these three hues* below — the obvious picks were all taken. |
| Number colour | **Untouched** | Owner call. The rule alone carries the marker; the number keeps `onSurface` / `onPrimary` / faint as it would have. |
| Agenda | A row in the existing day-off vocabulary | The app already has a "this day isn't work" card. Reuse beats inventing a new one. |

## The marker

A 2px rule, 15px wide, centred 4px above the bottom of the 32px day token —
**inside** the circle, so it paints over whatever the token's background is.

That placement is the whole point, and it is what a corner glyph could not do:

- **Plain** — coloured rule, `onSurface` number.
- **Today** — the rule sits clear of the 1.5px `onSurface` ring.
- **Selected** — the rule paints *on top of* the blue selection fill. This is
  the state that kills any marker living in the token's `fill`, because
  selection wins the fill by rule (`calendarDayCircleDecoration`). A marker
  that disappears when you tap the day is a marker that is absent exactly when
  it is being read. **On this state the rule renders `onPrimary` white** — any
  hue muddies against the primary blue, and the agenda row is open right below
  carrying the colour and the name. **EXCEPT in the picker**, which has no
  agenda row beneath it (owner call, 2026-08-29, after the release code review
  caught the gap): there the hue is LIFTED toward `onPrimary` rather than
  replaced by it, so the day still says which kind of holiday it is at the
  moment the date is chosen. `keepHueWhenSelected` is the flag, the lift clears
  3:1 against the selection fill for all three sets, and a test pins both that
  and the fact the three stay distinguishable from each other.
- **Off-month** — the rule drops to ~45% opacity so it fades with the faint
  number, rather than shouting from a cell that is deliberately recessed.

The number's colour is **not** changed in any state. An earlier draft coloured
it too; the owner cut that — the rule is enough, and leaving the number alone
keeps selection and off-month reading exactly as they do now.

### Why these three hues

| Set | Light | Dark |
|---|---|---|
| Québec statutory | teal `#0F766E` | `#3FBFB0` |
| Greek Orthodox | purple `#8E3DAE` | `#C482E8` |
| Construction holiday | ochre `#B45309` | `#EA802E` |

The obvious picks were all taken, and each for a reason that matters:

- **Blue is the selection fill.** This is what ruled out Greek flag blue
  (`#0D5EAF`) — near-identical in luminance to the primary `#005CC8`, so the
  marker would vanish on the very day you tapped.
- **Red means *cancelled*** on the status chart (and is the Day-route nav hue
  and a crew colour). A red-underlined day risks reading as "something is
  wrong with this day".
- **`crewPalette`'s ten hues blanket most of the remaining wheel**, and they
  are painted as round dots ~3px below this rule. A marker sharing a crew
  hue can twin with the dot beneath it.

So the three sit in the gaps: teal falls between the crew green (`#0E9B6E`)
and cyan (`#00A5C4`) but deeper and more muted than either; purple is well
clear of teal and is the liturgical colour of Holy Week, which is what the
Orthodox days are; and ochre is the only warm hue of the three, so the
shutdown separates from both cool markers at a glance.

If a hue does collide in practice, the cheaper fix is to distinguish the sets
by **rule style** instead — solid for statutory, doubled for Orthodox. That
needs no free hue and survives colourblindness outright.

### It must land on all three surfaces

`calendarDayCircleDecoration` has **three** call sites, and the marker belongs
on all of them or the app contradicts itself:

- `calendar_month_grid.dart` — `CalendarDayCell`
- `calendar_week_strip.dart` — the collapsed strip
- `inline_month_calendar.dart` — **the appointment form's date picker**

The third is the one that matters most and the easiest to forget: it is where
someone picks a date while booking, so it is the only surface where the marker
can actually prevent a mis-booking rather than just report one. It is also the
one that needs `keepHueWhenSelected` — the other two sit above an agenda row
that names the holiday, and it does not.

### Semantics

The day cell's semantics label gains the holiday name, so the marker is never
colour-only. `CalendarDayCell` already composes `dateLabel` +
`calendar_appointmentCount`; the holiday name joins that string.

**It must not touch `dottedJobsOn`.** A holiday is not an appointment — it
produces no dot and does not enter the semantics *count*. Only the label.

## The agenda row

Reuses `_DayOffStrip`'s vocabulary from `appointment_card.dart` — the app
already has a card for non-working time, and a holiday is exactly that:

- ground `theme.statusColors.neutralContainer`, border `colorScheme.outline`,
  radius `AppRadius.r12`, `minHeight: 44`
- headline = holiday name, caption = the source line
- right-side mono all-caps tag (`theme.monoType.groupLabel`)
- **no avatar** — a holiday belongs to nobody in particular, which is the one
  structural difference from a day off. The **rail slot is reused**, painted
  in the set's marker hue rather than a crew colour, which ties the row to the
  grid marker that led you to it.

Caption and tag distinguish the two sets, since only one of them is law:

| Set | Caption | Tag |
|---|---|---|
| Québec statutory | `Québec statutory holiday` | `HOLIDAY` |
| Greek Orthodox | `Greek Orthodox` | `OBSERVANCE` |
| Construction holiday | *(none)* | `HOLIDAY` |

**The construction row carries no caption** (owner call, 2026-08-29): the
headline `Construction holiday` says everything, so an earlier
`CCQ shutdown · day 4 of 14` progress line was cut. It still takes a rail, in
ochre, like the other two.

The tag matters most on a **selected** day, because that is exactly where the
grid rule has gone white and the hue is carried here instead.

## The set — 12 days and one 14-day run, all computed

| Holiday | Rule | 2026 | Source |
|---|---|---|---|
| Jour de l'An | January 1 | Thu Jan 1 | Statutory |
| Vendredi saint | Gregorian Easter − 2 | Fri Apr 3 | Statutory |
| Lundi de Pâques | Gregorian Easter + 1 | Mon Apr 6 | Statutory |
| Orthodox Good Friday | Julian Easter − 2 | Fri Apr 10 | Greek Orthodox |
| Πάσχα · Orthodox Easter | Julian Easter | Sun Apr 12 | Greek Orthodox |
| Orthodox Easter Monday | Julian Easter + 1 | Mon Apr 13 | Greek Orthodox |
| Journée nationale des patriotes | Monday **before** May 25 | Mon May 18 | Statutory |
| Fête nationale | June 24 (→ Jun 25 if Sunday) | Wed Jun 24 | Statutory |
| Fête du Canada | July 1 (→ Jul 2 if Sunday) | Wed Jul 1 | Statutory |
| Vacances de la construction | Sunday before July's last Saturday, 14 d | Jul 19 – Aug 1 | CCQ · **run** |
| Fête du travail | 1st Monday of September | Mon Sep 7 | Statutory |
| Action de grâces | 2nd Monday of October | Mon Oct 12 | Statutory |
| Noël | December 25 | Fri Dec 25 | Statutory |

Four rules carry a trap worth pinning in tests:

- **Patriotes is strictly *before* May 25.** When May 25 is itself a Monday —
  as in 2026 — the holiday is May **18**, not the 25th. An implementation that
  reads "the Monday on or before May 25" is wrong one year in seven.
- **Canada Day shifts to July 2 when July 1 is a Sunday** (LNT), **and Fête
  nationale shifts to June 25 on the same rule** (Loi sur la fête nationale,
  art. 3). Neither applies in 2026, so a test has to pick a year where they do.
  The shift on June 24 was MISSED in the first build and caught by the release
  code review: 2029 has June 24 and July 1 both on a Sunday, so shifting one
  and not the other answered the same legal question two ways in one year.
  This app marks the day actually taken off, not the nominal date — reverse
  both together if that ever changes, never just one.
- **Easter swings across six weeks.** Good Friday ranges from **Mar 23** to
  **May 2** over 2026–2035. Any test that assumes "Easter is in April" is
  wrong: 2027, 2032 and 2035 put Orthodox Pascha in **May**, and 2035 puts
  Québec's Good Friday in **March**.
- **The CCQ rule is not the third Saturday.** See the construction-holiday
  section below — the common formulation is wrong for 2022 and 2023, and
  right for the years you would spot-check.
- **Two different computus algorithms.** The statutory pair uses the
  Gregorian (anonymous) computus; the Orthodox trio uses the Julian computus
  **plus 13 days** to convert to the Gregorian calendar. That +13 offset holds
  for 1900–2099 only. In 2026 the two Easters land a week apart (Apr 5 vs
  Apr 12); in other years they coincide, which is a case the tests should
  cover so the calendar does not render one day marked twice.

Both computus implementations get pinned by a **table test of known dates**
across a range of years. They are the only non-trivial arithmetic here and the
only part that can drift silently.

## Explicitly out of scope

- No Firestore collection, no seeding, no admin editing, no yearly maintenance.
- No API and no bundled dataset.
- No picker dimming, no Save-time prompt, no effect on `findBusyEmployees`.
- No province setting — Québec only.
- Any **custom / one-off company closure**. Everything here is computed from a
  rule; there is no admin-editable list. (The construction holiday was
  initially deferred for this reason, then added on 2026-08-29 once its rule
  turned out to be fully computable — it needs no editable path.)

## The construction holiday — a RUN, not a day

`Vacances de la construction`, the CCQ industry shutdown. Commercially the
most significant entry on the list for a plumbing shop, and structurally the
odd one out: it is **14 consecutive days**, not a date.

### The rule

**The Sunday PRECEDING the last Saturday of July, running 14 days** (ending
the Saturday a fortnight later).

**It is NOT "the Sunday after the third Saturday of July"** — the formulation
repeated on most summary sites. That version is right for 2024–2026 and
**wrong for 2022 and 2023**, which is exactly the kind of rule that looks
verified when you spot-check the current year. Verified against published CCQ
dates:

| Year | Published | Rule gives |
|---|---|---|
| 2022 | Jul 24 – Aug 6 | Jul 24 – Aug 6 |
| 2023 | Jul 23 – Aug 5 | Jul 23 – Aug 5 |
| 2024 | Jul 21 – Aug 3 | Jul 21 – Aug 3 |
| 2025 | Jul 20 – Aug 2 | Jul 20 – Aug 2 |
| 2026 | Jul 19 – Aug 1 | Jul 19 – Aug 1 |

### Rendering: the same rule, in ochre

**No band, no highlight** (owner call, 2026-08-29). An earlier draft gave the
run a tinted cell background on the reasoning that duration should be encoded
as form. That was cut: everything uses the **same 2px rule under the day
number**, and only the hue changes.

It works because the fourteen days are **contiguous** — fourteen adjacent
ochre rules read as a run on their own, without a background asserting it. The
system stays one form and three colours, which is simpler to describe, simpler
to build, and leaves the cell's paint layers untouched.

Two consequences that still need handling:

- **It ALWAYS crosses the July/August boundary** — every year from 2022 to
  2035 without exception. So the tail always falls on **off-month** cells,
  where the rule drops to ~45% opacity with the faint number. That is the
  normal case here, not an edge one: the last day of the run is faint in the
  July view, and the first days are faint in August.
- **Row count is locale-dependent.** At a Sunday week start the run is exactly
  two complete grid rows. At a Monday week start (fr_CA) it spans three, with
  ragged ends. Nothing in the rendering depends on this now that the band is
  gone — but a test that asserts "two rows" would be wrong in French.

The agenda row reads simply **`Construction holiday`** with no caption, and
takes the ordinary `HOLIDAY` tag. Emergency calls still book during it, which
is the whole point of display-only.

### No statutory collision

The window is always late July / early August, and Québec has no statutory
holiday in that range (Canada Day, Jul 1, always falls before the run starts).
So a shutdown day can never also carry a statutory rule, and no cell ever
needs to show two hues at once.

## Coincidence years — one day, both sets

**The two Easters land on the SAME date roughly one year in three** — 2028,
2031 and 2034 in the next decade. In 2028, April 14 is both Québec Good
Friday and Orthodox Good Friday, and April 17 is both Easter Mondays. The
gap cycles 0 / 7 / 35 days and is not intuitive, which is precisely why this
case has to be handled rather than discovered in production.

The rule:

- **The statutory hue wins the grid marker.** It is the legally binding one,
  and a day cannot carry two rules without becoming a stack of stripes.
- **The agenda lists BOTH rows**, each with its own rail colour, caption and
  tag. Nothing is lost — the collision is resolved in the grid, where there is
  no room, and expanded in the agenda, where there is.
- **Πάσχα is unaffected.** It stays purple in every year, because Québec does
  not mark Easter Sunday at all, so it can never collide.

A holiday lookup must therefore return a **list** for a given day, not a
single value, and the marker resolves the hue from it. Returning the first
match would make the grid's colour depend on the order the sets happen to be
concatenated in.

## On Easter moving every year

Raised and settled during design: nothing is "sliced" per year and nothing is
stored. `easterFor(year)` is a pure function, so the whole set is derived from
the year of whatever month the calendar is rendering. 2027's dates fall out of
the same call with no maintenance, no migration and no yearly release — which
is the entire reason a bundled dataset was rejected up front.

The only per-year work is the **test table**, which pins known Easter dates
across a span of years for both algorithms.

## What shipped

| File | Role |
|---|---|
| `lib/features/calendar/domain/holidays.dart` | The computation and the l10n label resolvers. No I/O, year-cached. |
| `lib/features/calendar/widgets/views/calendar_day_circle.dart` | `holidayRuleColorFor` + `calendarDayTokenWithRule` — the marker's one owner. |
| `lib/features/calendar/widgets/views/holiday_agenda_row.dart` | The agenda row, in the day-off vocabulary. |
| `lib/core/theme/extensions/app_palette.dart` | The three hues, per theme. |
| `lib/l10n/app_{en,fr}.arb` | 17 keys: 13 names, 2 captions, 2 tags. |

Wired into all three `calendarDayCircleDecoration` call sites (month grid, week
strip, `InlineMonthCalendar`) and into `AgendaSliverList`, which now takes an
optional `day` so the portrait calendar and the split-layout `EventList` cannot
disagree.

Tests: `test/features/calendar/domain/holidays_test.dart` (54),
`.../widgets/holiday_marker_test.dart` (12),
`.../widgets/holiday_agenda_row_test.dart` (6).

Shipped in **1.54.0+83**.

**Two design decisions were revised during the build**, both to satisfy rules
this repo already had:

1. `holidayRuleColorFor` first branched on `theme.brightness`. `frontend.md`
   forbids that for styling, so the hues moved onto `AppPalette` — the same
   shape as `crewColorOf` reading `palette.crewOverride`. They are three plain
   fields rather than a `HolidaySet`-keyed map because `core/` must not import
   a feature type.
2. `markerSetFrom(List<Holiday>)` was added beside `markerSetOn(DateTime)` so
   `CalendarDayCell` resolves `holidaysOn` once and feeds both the semantics
   label and the marker hue, rather than looking up twice per cell.

A third landed in the release's simplify pass: `calendarDayTokenWithRule` now
takes the SET and the two states and resolves the colour itself, instead of
taking a pre-resolved `Color?`. All three surfaces spelled the same
resolve-then-wrap pair, and a fourth could have wrapped a token with no marker
— code that compiles clean and simply shows nothing, which is the exact drift
`calendarDayCircleDecoration` was extracted to end. `holidayHueFor` is the bare
palette lookup split out for the agenda row's rail, which wants the hue with no
state applied. Also in that pass: the private `_shift` gave way to the existing
`addCalendarDays`, the day-floor to `.dateOnly`, the redundant `_yearCache` was
dropped (the per-year date index is the only path any surface takes), and
`AgendaSliverList.day` became REQUIRED — the screen was passing the raw
`_selectedDay` where its jobs came from `_selectedDay ?? _focusedDay`, so the
holiday row could in principle have described a different day from the list
beneath it.

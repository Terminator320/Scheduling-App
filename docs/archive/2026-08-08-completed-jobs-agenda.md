# Closed jobs in the day agenda — sink, tint, collapse

**Status:** BUILT 2026-08-08. `flutter analyze` clean, 1663 flutter / 814 jest green.
**Mockup:** https://claude.ai/code/artifact/d6871059-0e01-4fa6-a35d-b7212d37aed7

## The problem

A day's agenda answers *what was booked*, not *what's left to do*. A job
completed at 7 AM keeps its clock slot above the 8 AM job that hasn't started,
and its card is indistinguishable from a live one apart from the status chip.

## Decision

Closed jobs — `done` **and** `cancelled` — sink below the day's open work, take
the green success tint, and render in a **collapsed** row under a labelled rule.

Owner picked **Option C** of three treatments (A: green fill only; B: quiet
cards under a rule, no fill; C: both, plus a density change), then added one
requirement: *"make sure it's still clickable."*

### Scope

The **main calendar agenda only**. The day route, dashboard, employee TODAY
panel and client job history each own their own sort and keep plain cards.

### Ordering

One new tier on the agenda comparator: **open before closed**. Everything below
it is unchanged — all-day first, then window start — so within the closed block
the existing rules still apply. The tier reads the **stored** status, never
`displayStatus`, so the comparator stays clock-free.

### The collapsed row

- **Kept:** crew colour bar, title, status chip, time, client name.
- **Dropped:** the avatar stack. The bar still carries crew colour, so *who* is
  not lost — only the faces are.
- Time moves up beside the client on one line.

**One deviation from the mockup, taken at build time: the multi-day counter
stays.** The mockup dropped it with the avatars. But a closed job still renders
on *every* day of its run, so without "Day 3 of 5" those rows are
indistinguishable from one another — a 5-day job marked done reads as five
identical closed rows. It costs nothing (same mono line) and is pinned by a
test.
- Fill is the app's existing `statusColors.successContainer` for `done`;
  `cancelled` keeps its current dim + strikethrough and gains no tint.

### Tappability — the owner's added requirement

The whole card stays one `InkWell` opening the same appointment sheet a live
card opens. Nothing is gated on status. Three signals prove it:

- **Press** — the existing `TapScale` (0.97) is unchanged.
- **Hover / ripple** — the `InkWell` overlay tints *over* the green fill rather
  than replacing it.
- **Focus** — the visible focus ring survives for keyboard and switch control.

**`minHeight: 48` is pinned on the compact body.** A collapsed row measures
~56 px at default text size — above Material's minimum, but close enough that
the OS's smallest text scale could drop it under. The floor is structural, not
incidental. Growing the other way is free: the row is a `Column`, so 2× text
makes it taller rather than clipping.

**No chevron, deliberately.** A "›" on closed rows only would imply they behave
differently from the open cards above, which carry none. Consistency is the
affordance; the press state is what demonstrates it.

### Colour is never the only cue

Four independent signals say "closed", in this order of reliability: position
below the rule, the chip text ("Complete" / "Cancelled"), the shorter row, and
the tint. That ordering is what keeps it readable in dark — where
`successContainer` is `#2BC48E` at **16% alpha painted onto the page ground**,
not over a white card, so it reads far subtler than in light.

### The "Closed · N" rule

The sliver list emits one divider at the boundary between the last open job and
the first closed one. Nothing renders on a day with no closed work.

## What must not change

The **crew bar keeps encoding identity, not status.** That is why `overdue` has
its own amber glyph rather than a coloured bar, and it is the reason none of the
three options recoloured it. Do not "improve" this by tinting the bar green.

## What shipped

| Seam | File |
|---|---|
| Terminal test, pure | `appointment_record.dart` — `isClosed`, lifted out of `displayStatusAt`, which already spelled the `done`/`completed`/`cancelled` triple and now calls it. Deliberately not `AppointmentStatus.isTerminal`, whose enum lives in a Material-importing widget file. |
| Sort | `appointment_day_slice.dart` — `_agendaOrder` (was `_byAllDayThenWindowStart`). `expandToDays` is its only caller and `main_calendar_screen.dart` its only consumer, so the change is inherently calendar-scoped. |
| Card | `appointment_card.dart` — `collapseWhenClosed`, sibling of `dimWhenCancelled` / `emphasizeToday`; `_kClosedMinHeight = 48`; the body split into `_body(...)`; `_ClosedMetaRow`. Colour + layout only, so the card's `IntrinsicHeight` ban on `LayoutBuilder` / `AutoSizeText` / `FittedBox` still holds. |
| Divider | `agenda_sliver_list.dart` — `_firstClosedIndex` + `_ClosedRule`, and the one call site passing `collapseWhenClosed: true` and `dimWhenCancelled: true`. |
| Copy | `calendar_closedCount` in both ARBs — "Closed · {count}" / "Clôturés · {count}". |

Tests: `appointment_day_slice_test.dart` (4 sort cases incl. the legacy
`completed` spelling and the in-progress-is-open guard),
`appointment_card_test.dart` (a 7-case `collapseWhenClosed` group incl. the 48px
floor), and a new `agenda_sliver_list_test.dart` for the rule.

## The other half of the request

The **one-time client phone backfill** shipped alongside this but shares no
code: `functions/scripts/backfill-client-phone-from-name.js`, with its two pure
rules (`extractPhone`, `patchFor`) exported behind a `require.main === module`
guard and covered by `functions/__tests__/backfill_client_phone.test.js`.

**Dry-run against prod 2026-08-08: 684 scanned, 347 patched.** The real shape
turned out to be safer than planned for — `name` is not "person + number", it
*is* the bare 10-digit number, so nothing in it is worth preserving.

Two owner calls came out of that dry run:

- **The rename takes ONE half when that is all there is.** Requiring both left
  39 of the 347 still displayed as a phone number. Safe because of the
  found-a-number gate: a doc with no number in its name is skipped entirely, so
  a Wave business client can never be renamed to its contact person.
- **The ambiguous docs are printed by id and raw name**, not just counted.

**Those 14 were reviewed 2026-08-08 and deliberately left alone** — they are not
a to-do list, and every future run will report the same set. Twelve are
legitimate names the 10-digit guard correctly refused to touch: SDC street-number
ranges (`SDC 3161-3163 de la gare tour 8`, `SDC 12170-72-74-76-78`) and Quebec
numbered companies (`9332-9928 Québec inc`, `3101-5696 qc inc`). Two are real but
unrecoverable from here and the owner chose to skip them: `8y0wL2xp…`
(`"971 58 579 7252"`, a UAE mobile the NANP formatter must not mangle) and
`qpB72TPt…` (`"548625261"`, nine digits — truncated at entry).

Search does not regress: `ClientSearchPolicy.index` folds `client.phone` into a
digits blob that `entryMatches` substring-matches, so a client stays findable by
typing their number — through the phone index instead of the name text.

**The real run has NOT been done.** See the script header for the command and
the two triggers it fires (`propagateClientEdits`, `waveUpsertCustomer`).

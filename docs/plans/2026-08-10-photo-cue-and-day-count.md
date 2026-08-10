# Photo cue on the appointment card + the agenda's day count

**Decided 2026-08-10** · branch `redesgin` · mockup:
<https://claude.ai/code/artifact/f7f2372f-c5dc-403c-afb3-ba30045b72e3>

Two small signals on the calendar's day list: a job that carries pictures
should say so without being opened, and the day's count should say how much of
the day is behind you. Three options were rendered in the app's own tokens and
bundled faces. **Chosen: A's day count with B's photo placement** — the two
moves were always independent, and they were decided independently.

## Chosen

| | |
|---|---|
| **Photo cue** | *(Option B)* A 15px `Icons.photo_outlined` glyph at the **end of the title line**, just before the status chip. Presence only — no count, no thumbnail. |
| **Day count** | *(Option A)* The agenda header's mono count grows a second clause: `4 JOBS · 1 DONE`, and drops back to a bare `4 JOBS` when nothing on the day is closed. |

The day count was already implemented before the mockup was drawn (same
session) and did not change. The photo cue moved off the time line and onto the
title line — a `_TitleRow` change, since that row is shared by the full and
collapsed card bodies.

### What the move bought, and what it cost

Two things improved. The glyph now reaches the eye on the first line rather
than the third, and — because `_TitleRow` is shared — it survives the agenda's
collapsed treatment on the same line as the title, instead of being wedged
between the time and the client name on a 48px row.

The cost is the one the mockup flagged and it stands: under `isCompact`
(< 360px, or text scale > 1.4) the status chip drops to its own line below the
title. The glyph deliberately **stays with the title** rather than following
the chip down — it is a property of the job, not of its status, and keeping it
anchored means its position doesn't move as text scale crosses 1.4.

## Decisions worth keeping

- **Presence, not quantity.** The glyph never carries a photo count. Owner call
  during implementation ("just show an icon, no need for number of pictures").
  The count lives in the detail sheet; the card answers *is there anything to
  look at here*, not *how much*.
- **The count is one predicate used twice.** The header counts `isClosed` —
  finished **and** cancelled — because that is exactly the set the `DONE · N`
  rule below it draws over. Counting only completed jobs would let two numbers
  on the same screen disagree the first time someone cancels a visit. Pinned in
  `CLAUDE.md` beside the closed-jobs-sink rule.
- **The collapsed row is where the cue matters most.** A finished job sinks to
  the bottom of the day and loses its crew avatars, so the glyph is the only
  thing left on that row saying there is something to look at. Putting it in
  `_TitleRow` means the collapse carries it for free rather than needing its
  own branch; a test pins it.
- **The glyph is spoken.** `AppointmentCard` excludes its subtree's semantics
  and composes one label, so an icon-only cue would be silent to a screen
  reader. `calendar_hasPhotos` ("Has photos" / "Contient des photos") is
  appended to that label.
- **One card, every surface.** `AppointmentCard` is the only appointment card,
  so the glyph appears in the calendar agenda, the day route, history, the
  dashboard and client job history at once. That was accepted, not overlooked.

## Rejected, and why

**Option B's header — `3 LEFT` leading, `OF 4` trailing muted.** "What's left"
is arguably the number an admin acts on mid-morning. Rejected in favour of A's
`4 JOBS · 1 DONE`: the total is the stable figure, and the header sits directly
above a list whose own rule counts the closed jobs — two different framings of
the same day, six lines apart, would read as two different numbers.
(B's photo placement was taken; only its count was declined.)

**Option C — 44px thumbnail on the trailing edge, segmented day meter.**
Strongest possible signal — you see whether the photo is a burst pipe or a
parking spot. Rejected on cost and on a known hazard: photos render from
`storagePath`, never the stored `url`, so every visible card would take a
Storage round-trip on scroll, and `AppointmentImageUrlResolver` resolves
**positionally** — a half-resolved list puts thumbnails on the wrong cards,
which is the same class of bug `PhotoPickerSection`'s `_resolvedFor` guard
exists to prevent. It also eats ~56px of a 360px card, where the title already
wraps to two lines, and does not fit the 48px collapsed row without regrowing
it.

## Where it lives

- `lib/features/calendar/widgets/cards/appointment_card.dart` — `_PhotoGlyph`,
  and the `hasPhotos` thread through `_body` into `_TitleRow`, which composes
  the warning glyph and the photo glyph around the title in one `Row`.
- `lib/features/calendar/screens/main_calendar_screen.dart` — `_jobLabel`.
- `lib/l10n/app_en.arb` / `app_fr.arb` — `calendar_hasPhotos`,
  `calendar_jobsDoneCount`.
- Tests: `test/features/calendar/appointment_card_test.dart` (glyph present /
  absent, and survives the collapse),
  `test/features/calendar/screens/main_calendar_screen_test.dart` (header with
  and without closed work).

## Open

Not device-verified. The glyph's 15px size and its `sp8` gap before the status
chip were chosen on a rendered mockup, not on glass — worth an eyeball on a
real phone, particularly at 1.4×+ text where the chip drops below the title and
the glyph stays put.

# Clients — address filter dropdown

**Date:** 2026-08-29
**Status:** BUILT 2026-08-29 (chip + panel). Search field deferred — see below.
**SUPERSEDED 2026-09-04** by `docs/plans/2026-09-04-clients-page-search-first.md`,
which deletes this chip-menu entirely and moves shared addresses into a filter
sheet. The deferred search field below is now never built. Everything here still
describes what SHIPPED, so it remains the reference for the current code — just
not for the next change.
**Mockup:** https://claude.ai/code/artifact/ed5abdf5-ded2-491d-9a31-7ed4569bf813
**File:** `lib/features/clients/widgets/sections/client_address_filter_menu.dart`

## Why

The Address filter at the end of the clients chip row works, but reads badly:

1. **The panel is the page.** `MenuAnchor` defaults its surface to
   `colorScheme.surfaceContainer`, which this theme maps to `AppColors.paper`
   (`#F1F4F9`) — the exact `scaffoldBackgroundColor` — and `surfaceTint` is
   deliberately `transparent` to kill M3 elevation tinting. So the open menu has
   no tint, no border, and the same colour as the ground behind it. This is the
   headline defect and it is invisible in code review; it only shows on screen.
2. **It doesn't read as a menu.** Same pill, size and weight as the four filter
   chips beside it, but it opens rather than toggles. No chevron.
3. **It's last in a row that scrolls.** Five controls in a horizontal scroller;
   at large text scale the Address chip starts off the right edge.
4. **No "all".** Clearing means re-tapping the selected row — a gesture with no
   on-screen cue, since a closed menu doesn't show its selected state.
5. **A picked street blows out the chip.** The label is replaced by the street,
   so "1200 Rue Sherbrooke Ouest" pushes the type chips off-screen.

## Decision — Option A, "stay a chip, act like a menu"

Keep the control in the chip row. Fix the affordance and the panel. B's search
was designed into the panel and then **deferred** — the roster has three shared
addresses, well under the threshold at which the field would render.

### The chip and the panel

| Element | Change |
|---|---|
| Chip position | First in the row, ahead of the type chips — so the address control is never what scrolls away |
| Chip affordance | Leading `Icons.apartment_outlined` (18) + trailing `Icons.keyboard_arrow_down` (18) |
| Chip active fill | `palette.primaryAccent` on `blueTint` — **not** the default `secondaryContainer` green, so an active address never reads as a type chip |
| Chip label | Still the picked street, now width-capped: `ConstrainedBox(maxWidth: 140)` + `TextOverflow.ellipsis` |
| Menu surface | Explicit `MenuStyle`: `backgroundColor: surface`, `side: BorderSide(hairline, 1)`, `shape` at `AppRadius.r16`, elevation 3 |
| Menu header | Small uppercase `SectionLabel` reusing `clients_filterByAddress` ("Address") so the panel names itself |
| Clear row | "All addresses" first, above a divider, in the accent colour. Hidden while a query is typed — the `×` in the field is what clears then |
| Row layout | Street on line 1, city alone on line 2, unit count right-aligned in `monoType` with tabular figures — the count stops being buried inside a `"city · N units"` sentence |

### The search field — designed, DEFERRED, do not build yet

**The current roster has 3 shared addresses** (owner, 2026-08-29). The field
renders only above 8, so building it now ships code that never appears on
screen. It stays specified here, and drawn in the mockup as states 02–04, so
that turning it on later is a switch rather than a redesign. Do not lower the
threshold to make it visible — a search box over three rows is the thing the
threshold exists to prevent.

Renders **only above 8 shared addresses** (`_searchThreshold`, a named constant
beside the widget). The panel holds about six rows before it scrolls, so eight
is where someone can no longer see the whole vocabulary at once; below it the
field is a box that only ever costs a tap. Same instinct as the widget's
existing "render nothing when no street is shared" rule, one level up.

| Concern | How |
|---|---|
| Data source | The `List<ClientBuilding>` the bar already passes in, reduced from the loaded client window. Typing touches no repository and spends **no read** |
| Debounce | **None.** `kSearchDebounce` exists for DB-backed search; this filters an in-memory list synchronously, so no `Debouncer` and no `tagged` logger |
| Matching | `ClientSearchPolicy.normalize` on both sides + `String.contains` — accent-folded and unanchored, so "cure" finds Curé-Labelle *and* Curé-Poirier, and "sherbrooke" matches mid-string. Verified: `normalize` lowercases, accent-folds and collapses non-alphanumerics to single spaces |
| Civic numbers | Fall out of the same substring pass ("4450" → "4450 Prom. Paton"). **No `digitsOnly` pass** — that primitive is for phones, and stripping non-digits here would let "90" match "1200 Rue…" through its unit numbers |
| Panel height | `MenuStyle.maximumSize`, subtracting `MediaQuery.viewInsetsOf(context).bottom` while the field has focus, so the panel can't run under the keyboard |
| Rows rendered | Bounded at `_maxRendered = 50`, mirroring `ClientJobHistorySection` — a menu's children build eagerly inside a scroll view. Past the cap, search is how you reach the rest |
| Widget state | Becomes a `StatefulWidget`: a `TextEditingController` + query, disposed in `dispose`. Query resets on `onClose`, or reopening shows the last filtered list |
| Not a menu item | The field goes in `menuChildren` as a plain padded `TextField`, **never** wrapped in `MenuItemButton` — a menu item closes the menu when tapped, dismissing the panel on the first tap into the field |
| Escape / outside tap | Unchanged; dismissal clears the query. Arrow-key traversal still walks the rows, since focus sits in the field only while typing |
| No match | Two centred lines inside the panel — *not* `AppEmptyState`, which is built for a screen |
| Match count | A mono footer ("2 of 14 addresses") while a query is active, so it's clear whether anything is hidden |

Every visual value is an existing token. Nothing new joins `design_tokens.dart`.

### Localization

One new key for the build, both ARBs in lockstep, `@key` block in EN:

- `clients_filterAllAddresses` — "All addresses" / "Toutes les adresses"

Three more belong to the deferred search and should land **with** it, not now —
an unused ARB key is drift, and EN/FR pairs that nothing renders go stale:

- `clients_searchAddressesHint` — "Search addresses" / "Rechercher une adresse"
- `clients_noAddressMatch` — takes the query as a placeholder
- `clients_addressMatchCount` — "{matched} of {total} addresses", plural-aware

`clients_buildingUnits` stays (it is now the right-hand count only), and
`clients_filterByAddress` gains a second use as the panel header.

## Unchanged on purpose

- Renders nothing when no street is shared — an empty menu is a control that
  looks broken, and on a small roster that is the normal state.
- Busiest address first; the reduction that builds `List<ClientBuilding>` is
  untouched.
- Still one sealed `ClientsFilter` — picking an address clears whichever chip
  was on.
- Re-picking the active address still clears it, so `toggledFilter` keeps its
  existing caller shape. The clear row is an addition, not a replacement.

## Calls made along the way

- **The chip keeps showing the street**, rather than reverting to a static
  "Address". The current widget does that deliberately (its comment: the active
  filter should be readable without opening the menu) — the width cap fixes the
  blow-out without giving that up.
- **A clear row instead of only the re-tap.** The re-tap still works; it stops
  being the only way.
- **Search in the panel, not in a sheet.** The graft is B's answer to a long
  list without B's modal cost — then held back, because at 3 shared addresses
  there is no long list to answer.

## Worth watching

- A `TextField` inside a `MenuAnchor` is unusual for this app. If it fights the
  keyboard on a small phone in landscape, that is the signal to fall back to
  option B's sheet — which is why B stays written up below.
- `_searchThreshold = 8` is a guess at where scrolling starts, not a
  measurement. The roster is at 3, so the guess is untested and does not need to
  be right yet — settle it by looking at a real panel when the count approaches
  it.
- The trigger to revisit is the shared-address count crossing 8, which grows on
  its own as clients are added. Nothing watches for that; it will have to be
  noticed.

## Rejected

- **B — picker bottom sheet** (`showModalBottomSheet` with a search field over
  the same rows). The only option that survives an unbounded list, and the scrim
  makes the "panel is the page" defect impossible to reintroduce. Rejected as a
  heavy modal gesture for a filter its four neighbours apply in one tap; it also
  steps outside `showAdaptiveActionSheet`, which cannot hold a search field.
  **Kept on file as the fallback** if the in-panel field proves awkward, and as
  the answer if the shared-address list ever outgrows one panel.
- **C — its own full-width select field** below the chip row. Impossible to miss
  and states the active address without opening anything. Rejected for spending
  ~54px above the list permanently on a filter most sessions never touch, and
  for breaking the "one row of peer filters" model — address would stop looking
  mutually exclusive with the chips, which it is.

## Built

2026-08-29. `flutter analyze` clean, 3030 tests pass.

- `client_address_filter_menu.dart` — rewritten: `_menuStyle` (surface, outline,
  `r16`, elevation 3), `_AddressMenuItem` (street / city / mono count column),
  `_AddressChip` (apartment avatar, chevron, capped label, `primaryContainer`
  fill with the accent foreground), and the conditional clear row.
- `client_type_filter_bar.dart` — the menu moved to the head of the row.
- `app_en.arb` / `app_fr.arb` — `clients_filterAllAddresses` added;
  `clients_buildingUnits`'s description corrected (it is now the row pill plus
  the screen-reader label on the menu count, no longer a rendered subtitle).
- `client_address_filter_menu_test.dart` — two tests updated for the split
  city/count layout, five added: the clear row's conditional offer, that it
  clears, that a stale selection can still be escaped, the label cap, and that
  the menu background is `surface` and not `scaffoldBackgroundColor`.

The search field is NOT built. Nothing in the shipped widget references it.

## Not redundant with the Clients search bar

The top search bar **already** matches addresses — `ClientSearchPolicy.index`
folds `address`, `city`, `province` and `postalCode` into the searchable text
(`client_search_policy.dart:108-111`), so typing a street there finds everyone
on it today. The two do different jobs and both stay:

- **Search bar** — finds *clients* by street. A flat list of matching people;
  the filter chips clear.
- **Address menu search** — picks a *filter*. Every client at one building, with
  the chip left active so the list keeps that shape while you work.

The in-menu field is therefore not a second way to search addresses; it is how
you find the right entry in a long menu of buildings. That is the whole reason
it only renders above `_searchThreshold`.

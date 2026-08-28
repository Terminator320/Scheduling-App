# Grouping clients by building

**Date:** 2026-08-28
**Status:** IMPLEMENTED
**Depends on:** [Address street/locality split](2026-08-28-address-street-locality-split.md)

## Why now

The address backfill's prod dry run made the case the design could only guess
at earlier in the day: **32 clients across 7 Prom. Paton buildings, 18 of them
in 4450 alone**, plus 3 at 10200 Bd de l'Acadie. The clients list orders by
name, so those 18 are scattered through a 714-client roster with no way to see
them as a group.

Two risks the same dry run retired:

- **Spelling drift.** The worry was `4450 Prom. Paton` vs
  `4450 Promenade Paton` splitting one building. Across all 112 reduced
  addresses the street spelling is perfectly consistent — Places autocomplete
  does that work.
- **The key was expensive to derive.** After the split, `address` *is* the
  street line, so the building key is one further `splitApt` to drop the unit.

## Design

**Derived, never stored** — the same discipline as the display-only `overdue`
status. No migration, no field, nothing the console can corrupt.

`clients/domain/policies/client_building.dart`:

| | |
|---|---|
| `buildingKeyFor(client)` | `streetOnly` → drop the unit → accent-fold, plus the city |
| `buildingsIn(clients)` | addresses shared by 2+, busiest first |
| `buildingCountsIn(clients)` | `key → count`, one reduction the list shares |

Three decisions worth keeping:

- **The city is in the key.** Two towns hold the same civic number; without it
  a Laval client appears under a Montréal address with nothing explaining why.
- **It reduces through `streetOnly` first**, so a legacy full-address doc and a
  normalized one land on the same key. Without it the grouping would break on
  exactly the buildings with the most history.
- **The floor is two clients.** An entry per address is the client list under
  another name.

### UI

**A menu, not a chip per address.** This is the one place the filter bar
departs from its own documented rule, and deliberately: the type options are
the fixed `ClientType.pickable` set with no vocabulary to discover, while
addresses are discovered from the data and there can be dozens, which a
horizontally-scrolling chip row cannot hold. It stays a peer of the chips — one
sealed `ClientsFilterBuilding(key)` — so selecting one clears whichever chip was
on, and picking the selected one clears back to `ClientsFilterAll`.

It renders **nothing** when no address is shared. An empty menu is a control
that looks broken, and on a small roster that is the normal state.

**The row pill** reads `18 units`, in the badge `Wrap` beside the type chip.
Neutral rather than accented — a fact about the site, not a status. Not
tappable: the whole row is one `InkWell`, so a pill inside it is a nested
gesture on a 48px target.

The count is **passed in**, from one `clientBuildingCountsProvider` reduction —
never a provider watch per row, the same rule `employeeJobsTodayProvider`
keeps. `ClientTile` is reused by the booking flow's client picker, which passes
nothing and shows no pill.

### Naming

The filter is labelled **Address / Adresse**, not Building. `Building /
Immeuble` is now a client *type* chip in the same row, and one word meaning two
things a few pixels apart is a defect worth avoiding for free. "Address" is
also more accurate — it groups duplexes, which nobody calls a building.

## Cost

Nothing. `fetchClientsByBuilding` and `fetchBuildings` reduce the **same bounded
cached scan window** the type and Archived chips already use, so no extra
Firestore read inside the TTL, no composite index, no migration. It inherits
that window's bound: past the 5000-doc cap the menu sees a prefix of the roster,
exactly like search and the chips.

Refactoring note: `fetchClientsByType` and `fetchArchivedClients` now route
through the same `_windowRecords` / `_byDisplayName` helpers the new methods
use, rather than each carrying its own copy of the sort.

## Verification

2913 Flutter tests pass; analyzer clean on every touched file. 14 domain tests,
4 repository tests, 4 tile tests (including the small-phone 2× sweep — the pill
is a third child of the badge `Wrap`) and 6 menu tests.

## Known limits

- **88 clients have an address but no locality fields.** `streetOnly` won't
  reduce them, so they group unreliably — a real second-class citizen in this
  view, invisible in a building they may well belong to. Worth a data pass.
- **Three docs carry doubled apt prefixes** (`210-210-4450 Prom. Paton`), which
  read as their own building. `AddressParser.canonicalFrom` now heals one on
  its next ordinary save, so opening and saving each fixes it; before that
  change re-saving did *not* repair them.
- The window bound above.

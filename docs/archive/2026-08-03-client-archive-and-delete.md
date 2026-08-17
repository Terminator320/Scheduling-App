# Client archive + delete (swipe actions)

Design, 2026-08-03. Status: **SHIPPED.** Built and committed on `redesgin`;
backend deployed 2026-08-03 (`1c6a949`, `deleteClient`, 25 → 26 functions, the
`(archived, name, __name__)` index), and the prod backfill ran **before** that
deploy as required — 674 clients patched, confirmed by a follow-up dry run
reporting 0. `allow delete` on `/clients` was withdrawn later, on 2026-08-08,
when the `#compat-1.37.1` shim retired. Kept for its rationale only.

## What this changes and why

This reverses the 2026-08-01 decision recorded in `CLAUDE.md` that "a client is
never removed — no delete, no archive". Owner call, 2026-08-03: admins may
delete clients, and archive ships alongside as the non-destructive option.

The 2026-08-01 decision had two distinct reasons, and this design answers them
separately rather than overriding them:

- **Delete orphaned appointment history.** Deleting a client left its past
  visits holding the denormalized `clientName` with a dead `clientId`, so
  history silently detached. → **Delete is gated on `jobCount == 0`.** A client
  with history cannot be deleted at all, so the orphaning path is unreachable
  rather than merely discouraged.
- **Archive would have broken the paginated list.** Filtering a server page in
  Dart makes `pages.last.length < pageSize` fire early, permanently truncating
  the list below the first archived client. → **The filter runs server-side**,
  so the problem does not arise: the server returns a full page of non-archived
  docs, `items.last` is genuinely the last doc, and the existing end-of-list
  test stays valid.

A client-side variant was designed first (a `ClientPage` object carrying the
raw page size and a raw cursor — the shape `CLAUDE.md` predicted archive would
require). It was **rejected in favour of the server-side filter** on
2026-08-03: it avoided a migration, but left a subtle invariant in the code
permanently, where the raw-vs-filtered cursor distinction fails as *duplicate
rows* and invites being "simplified" away later. Moving the filter to the
server removes the invariant instead of documenting it. The cost that choice
buys is the standing `archived`-on-every-doc obligation in §1, and the
three-step deploy in §6.

## Non-goals

- No archive for employees, appointments, or any other entity.
- No undo toast. Archive is reversible from the Archived filter chip; a second
  affordance is not worth the surface.
- No bulk archive/delete.

## 1. Data model

`ClientRecord` gains one field:

```dart
@Default(false) bool archived,
```

- `fromMap`: `archived: (data['archived'] as bool?) ?? false`. A doc missing
  the field still *parses* as not archived — but see the migration below, since
  a doc missing the field is **excluded from the list query entirely**, which
  parsing cannot rescue.
- `toMap()` emits `archived`. It is user-owned, unlike `jobCount` / `wave` /
  `waveCustomerId`, which `toMap` must still never emit.

`firestore.rules`, in `isValidClientData`:

```
&& (!('archived' in data) || data.archived is bool)
```

Per the deploy runbook's cap rule, this is a type check with no width, so it
cannot be tighter than any shipped write path.

### Every client doc must carry `archived`

This is the price of the server-side filter and the one genuinely new
long-lived invariant this feature introduces. **Firestore excludes documents
missing the field a query filters on**, so a client without `archived` is
invisible in the list — while still appearing in search, which scans an
unfiltered window. That asymmetry is what makes the failure confusing rather
than obvious.

Three obligations, all required:

1. **One-time backfill** — `functions/scripts/backfill-clients-archived.js`,
   modelled on `backfill-emergency.js`: set `archived: false` on every client
   doc that lacks it.
2. **Strict deploy ordering** — run the backfill **before** the filtered query
   ships. Reversed, every un-backfilled client disappears from the list until
   the backfill finishes.
3. **Every create path writes it** — `_normalizedMap` in
   `firebase_clients_repository.dart` (which covers `addClient`, and makes
   `updateClient` self-heal any doc that is subsequently edited) and Wave's
   `importCustomers` in `functions/wave/customers.js`. A missed path fails
   silently with no compile error.

The backfill plus the self-heal on edit make drift converge rather than
accumulate, which is why this is preferred over the client-side alternative.

## 2. Repository contract

`fetchClientsPage` keeps returning a plain `List<ClientRecord>` and
`ClientsListView` is **untouched**. The query gains one clause:

```dart
_clients
    .where('archived', isEqualTo: false)
    .orderBy('name')
    .orderBy(FieldPath.documentId)
```

Because the server returns a full page of non-archived docs, `items.last` is
genuinely the last doc of the page, so the existing cursor and the existing
`pages.last.length < _pageSize` end-of-list test both stay correct with no
change. This is the entire reason for choosing the server-side filter.

**New composite index**, added to `firestore.indexes.json`:

```
clients: (archived ASC, name ASC, __name__ ASC)
```

So this feature's deploy **must include the `firestore:indexes` target**. A
missing index fails the list query with `FAILED_PRECONDITION`.

Everywhere else, archive filtering stays in Dart — those paths already match
over the cached ~1000-doc `_clientScanWindow()` and have no pagination
contract, so they need no index and no query change:

| Path | Behaviour |
|---|---|
| `searchClients` | **Includes** archived; the tile badges them |
| `fetchClientsByType` | **Excludes** archived |
| `fetchArchivedClients()` (new) | Archived only, name-sorted; reuses the same window |

New write method:

```dart
Future<void> setClientArchived(String id, {required bool archived});
```

`update({'archived': archived, 'updatedAt': serverTimestamp()})` followed by
`_patchWindow(id, data: {'archived': archived})`. The patch **merges** over the
stored doc — a plain substitution would drop the function-owned `jobCount` and
`createdAt` and blank the job count on every search result until the TTL
expires.

`deleteClient` no longer writes to Firestore directly — it calls the new
callable in §3 and keeps its existing `_patchWindow(id)` drop on success.

## 3. Delete — server-enforced

Delete is gated in **two layers with different jobs**. The UI layer decides
what to offer; the server decides what is allowed.

### Layer 1 — UI affordance (fast, local, advisory)

```dart
bool canDeleteClient(ClientRecord client) => client.jobCount == 0;
```

`jobCount` is `int?` with a null default and is **lazily backfilled** — it
self-heals on the client's next appointment write and renders nothing until the
field exists. So a client with real history can legitimately have no
`jobCount`, and `null == 0` is `false`, which withholds the action. That is the
intended reading: **missing means unknown, and unknown withholds.** Treating
null as zero would offer delete in exactly the case the gate exists to prevent.

Its only job is to avoid offering an action the server will refuse. It is not
a boundary and must not be described as one.

### Layer 2 — `deleteClient` callable (authoritative)

New callable in `functions/clients.js`, following the standard guard order
(auth → `assertAdmin` → `assertPayloadShape` / `requireString` →
`enforceDurableRateLimit` → work), with `enforceAppCheck: true`:

```
deleteClient({ clientId })
```

It runs a **live `count()` aggregate** over
`appointments where clientId == <id>` and refuses with
`failed-precondition / client-has-history` when the count is non-zero, then
deletes the doc.

The live count is the point: `jobCount` is denormalized and lazily backfilled,
so it can be stale, missing, or (on a client whose appointments were reassigned
out-of-band) simply wrong. The server must not trust it, and neither should the
rules. `recountClientJobs` already uses a `count()` aggregate for the same
reason — this mirrors it.

The client repository's `deleteClient` calls this and maps
`failed-precondition` to a typed failure so the UI can say *why* rather than
"Something went wrong".

### Rules

**`allow delete` on `/clients` is withdrawn entirely.** Deletion becomes
Admin-SDK-only, through the callable. This is a strict improvement over
retaining the rule: the `kShowTestingDeleteClient` pre-ship hole is *closed*
rather than legitimized, and the history guarantee becomes real instead of
advisory. Rules cannot express "only when this client has no appointments" —
a callable is the only place that check can actually live.

## 4. UI

Adds `flutter_slidable`. The app currently has no swipe package — one built-in
`Dismissible` in `notice_listener.dart`, which is dismiss-on-threshold and
cannot model reveal-then-tap.

**The `Slidable` wrapper lives in `ClientsListView`'s item builder, never
inside `ClientTile`.** The tile is reused by the booking-flow client picker,
which must not gain destructive swipe actions.

- Swipe left reveals `[Delete?] [Archive]`. Archive sits at the edge.
- **A full swipe commits Archive only.** Delete is never gesture-committed — it
  requires a deliberate tap, then `showConfirmDialog(destructive: true)`.
- The Delete action is built only when `canDeleteClient(client)`.
- Archived rows carry a muted `StatusPill` (already imported by
  `client_tile.dart`), including in search results.
- The client detail sheet / view swaps its debug-gated Delete for a real
  Archive / Unarchive action plus the gated Delete.

The filter row's selection becomes a small sealed family so that "archived
**and** commercial" is unexpressible rather than merely unhandled:

```dart
sealed class ClientsFilter {}      // All | Type(ClientType) | Archived
```

Rendering: an **Archived** chip is appended to the existing
`ClientType.pickable` row. There is no explicit "All" chip today and this adds
none — `All` is the state you get by re-tapping the selected chip, matching
`ClientTypeFilterBar`'s current tap-selected-to-clear behaviour. The chips stay
mutually exclusive.

Feedback follows the existing rules: success through
`noticeServiceProvider`, failures through `composeErrorNotice` with a new
`CLI-ARCH` tag (delete reuses `CLI-DEL`), each with a matching capitalized
`error_intro*` key. Every new string lands in `app_en.arb` **and**
`app_fr.arb` in lockstep with an `@key` block in EN.

## 5. What this retires

- `lib/core/testing_flags.dart` — deleted.
- `kShowTestingDeleteClient` and every `#pre-ship` TODO in the clients feature.
- **`allow delete` on `/clients` — withdrawn.** Deletion moves behind the
  callable in §3, so the pre-ship rules hole is closed outright rather than
  legitimized. This resolves the outstanding `#pre-ship` item instead of
  deferring it.

## 6. Deploy order

This feature is **ordering-sensitive in three steps** and must not be collapsed
into one:

1. **Backfill first** — run `backfill-clients-archived.js` against prod. Until
   every client doc carries `archived`, the filtered query in step 3 hides the
   ones that don't.
2. **Backend** — `firebase deploy --only functions,firestore:rules,firestore:indexes`.
   The `firestore:indexes` target is **required** here (new composite index);
   never pass `--force`. This adds the `deleteClient` callable and withdraws
   `allow delete` on `/clients`.
3. **App build** — only after the index has finished building and the callable
   is live, per the "backend before the app build" rule in `docs/DEPLOYMENT.md`.

Withdrawing `allow delete` in step 2 breaks any older build whose client-side
delete path writes directly to Firestore. At the time of writing that is the
debug-only `kShowTestingDeleteClient` affordance, which never shipped in a
release build — so no store build is affected. Re-verify before deploying.

## 7. Testing

| Level | Coverage |
|---|---|
| Pure | `canDeleteClient` at `0`, `null`, `>0`; the `ClientsFilter` family |
| Repository | `fetchClientsPage` sends the `archived == false` clause; `setClientArchived` merges rather than replaces the window entry; `deleteClient` maps `failed-precondition` to the typed failure |
| Functions (jest) | `deleteClient` refuses a client with appointments and deletes one without; guard order (non-admin, bad payload, rate limit) |
| Widget | Swipe always offers Archive; offers Delete only at `jobCount == 0`; a full swipe archives and never deletes; the Archived chip shows only archived; type chips exclude archived; search includes archived |
| Scale | `_scaledHarness` sweep on the swipe action row (260×640, textScaler 2.0) |

## 8. Accepted risks

- **Every client doc must carry `archived` forever.** A create path that
  forgets it produces a client that is invisible in the list but present in
  search, with no compile error. Mitigated by the backfill, by `updateClient`
  self-healing any edited doc, and by there being only two create paths
  (`_normalizedMap`, Wave `importCustomers`) — but it is the standing hazard
  this design introduces. See §1.
- **Delete costs one `count()` aggregate per attempt.** Aggregates bill far
  below a full read and delete is rare; acceptable.
- The UI's `canDeleteClient` can disagree with the server when `jobCount` is
  stale — it may withhold delete on a client that is genuinely empty. Failing
  toward *not offering* is the correct direction, and the client self-heals on
  its next appointment write.

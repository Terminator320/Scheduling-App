---
paths:
  - "lib/features/clients/**"
  - "functions/clients.js"
  - "functions/client_*.js"
  - "functions/wave/**"
  - "functions/scripts/backfill-client*"
  - "test/features/clients/**"
---

# Clients (and appointment history)

Loaded when working on clients, the Wave sync, or the History screen.
Root context: `../../CLAUDE.md`.

- **ClientRecord legacy back-compat:** pre-Wave-reshape "business-only" client
  docs stored their name under `businessName` with an empty `name`.
  `ClientRecord.fromMap` handles it in **two** halves, and both are load-bearing:
  `name` falls back to `businessName` when blank (the documented legacy shape),
  AND the raw value is carried through onto `ClientRecord.businessName`, which
  `ClientSearchPolicy.index` indexes. The fallback alone is not enough — it only
  fires when `name` is empty, so a legacy doc holding a name AND a *different*
  business name was unfindable by the business. The one-time
  `backfillLegacyClientNames` function was removed, so these reads are the only
  thing keeping legacy business docs visible/searchable — keep them
  indefinitely; never strip either. **`businessName` is READ-ONLY**: no UI edits
  it and `toMap` must never emit it (pinned by a test), or every save would
  persist a field the app no longer owns. Don't instead add a second matcher
  over the raw map beside the policy — that is what had drifted before, matching
  in the instant local filter and then vanishing when the debounced read landed. (A doc missing
  `name` entirely is excluded by the list/search `orderBy('name')`; the fallback
  only rescues docs whose `name` is present-but-empty.) `toMap` must NEVER emit
  `waveCustomerId`/`wave`/`jobCount`; those are function-owned and
  `firestore.rules` rejects any client write that touches them. Every field
  `toMap` DOES emit is type/length-capped by `isValidClientData` in
  `firestore.rules` (name/business/first/last/phone/mobile/email plus the
  address family, a bounded `contacts` array, and the P3 additions
  `type`/`accessNotes`/`onSiteManager`/`billingTerms`/`autoInvoice`) —
  add the matching rule cap when you add a new client field, or the write passes
  the app but a rules tightening later rejects it.
- **A client is ARCHIVED, not deleted** (owner decision 2026-08-03, which
  REVERSED the 2026-08-01 "never removed — no delete, no archive" rule and
  retired the `kShowTestingDeleteClient` `#pre-ship` hole with it —
  `lib/core/testing_flags.dart` is deleted).
  Archiving hides a client from the paginated list and the type filter but
  keeps it **searchable and bookable**: its `clientId` links on existing
  appointments are untouched, which is the whole point — deleting one orphaned
  its past visits, which keep the denormalized `clientName` but lose the link,
  so history silently detached.
  **`archived` must be on EVERY client doc, forever.** The list filters
  `where('archived', isEqualTo: false)` **server-side**, and Firestore excludes
  docs missing a filtered field — so a doc without it is invisible in the list
  while still turning up in search: a partial disappearance with no error
  anywhere. There are exactly two create paths and both stamp it: `_normalizedMap`
  (`firebase_clients_repository.dart`, via `ClientRecord.toMap`) and Wave
  `importCustomers` (`functions/wave/customers_import.js`). **The Wave UPDATE
  branch must never write it**, or every scheduled import un-archives
  everything; a test pins that half. Existing docs were backfilled by
  `functions/scripts/backfill-clients-archived.js` (idempotent, `--dry-run`),
  which must run against prod BEFORE the filtered query deploys.
  The filter is server-side **specifically so `fetchClientsPage` keeps returning
  a plain `List`**: the server still fills a whole page, so `items.last` stays
  the true cursor and the list's `pages.last.length < pageSize` end-of-list test
  stays valid. A Dart post-query filter would shorten a page the server actually
  filled and truncate the list permanently at the first archived client — never
  reintroduce one. Needs the `(archived, name, __name__)` composite index.
  **Delete survives only for junk data, and only through the `deleteClient`
  callable** (`functions/clients.js`), which refuses with
  `failed-precondition / client-has-history` when a **live `count()` aggregate**
  finds any appointment — deliberately NOT the denormalized `jobCount`, which is
  lazily backfilled and can be stale, missing or wrong. Rules cannot express
  "only when this client has no appointments" (no cheap foreign-collection
  count), so the callable is the only place that guarantee can live and
  **nothing deletes a client directly**.
  **`allow delete` on `/clients` is now WITHDRAWN** (2026-08-08). It had
  survived as a `#compat-1.37.1` shim entry for that build's ungated Delete
  button, and while it did the hole was real — an admin on the old build could
  orphan a client's job history, the very thing the callable's `count()` gate
  prevents. That is closed: the callable is the only delete path, in rules as
  well as in code. Never re-add the grant.
  `canDeleteClient`
  (`domain/policies/client_delete_policy.dart`) is **advisory UI only** — it
  keeps the swipe and the detail footer from offering what the server would
  refuse, and treats a null `jobCount` as unknown, which withholds. The Admin
  SDK bypasses rules, so console/support cleanup is unaffected.
  UI: `flutter_slidable` in `ClientsListView`'s item builder — **never inside
  `ClientTile`**, which the booking-flow client picker reuses and must not gain
  destructive actions. A full swipe commits **Archive only**; delete is never
  gesture-committed. Both surfaces route through the one `ClientActionsHost`
  mixin (`clients/widgets/views/client_actions_host.dart`) so the notices, the
  CLI-ARCH/CLI-DEL tags and the confirm copy can't drift; its two hooks are
  separate because the detail view must STAY OPEN after archiving (to offer
  Unarchive) and dismiss after deleting.
- **The clients type filter is a SEPARATE bounded read, never a filter over the
  paginated list.** `fetchClientsByType` scans the same cached 5000-doc window
  `searchClients` uses, so the chip row and its results cost no extra Firestore
  read inside the 2-minute TTL and need no composite index. `fetchArchivedClients`
  (the Archived chip) is the same shape over the same window, and the chips are
  ONE sealed `ClientsFilter` — "archived AND commercial" is unexpressible, not
  merely unhandled. The type filter **excludes archived clients** (the Archived
  chip is where they live); `searchClients` deliberately does **not** — archived
  clients stay findable and bookable, which is why the row badges them.
  Routing it through `fetchClientsPage` instead would filter a server page in
  Dart, shortening a page the server actually filled — which is exactly what
  stops `ClientsListView` paging early and hides every client below the first
  non-matching one. The window bound is the same one search already lives with:
  past ~5000 clients the filter sees a prefix, not the whole roster. The chips
  offer the fixed `ClientType.pickable` set, so there is no vocabulary to
  discover and no spelling to reconcile — searching *within* an active filter
  runs in Dart over that same bounded list via `ClientSearchPolicy`, indexed
  once per result set rather than per keystroke.
  **A write patches that cached window by MERGING over the stored doc, never
  replacing it** (`_patchWindow`): `ClientRecord.toMap()` emits user-owned
  fields only, so a plain substitution drops the function-owned `jobCount` and
  `createdAt` and blanks the count on every search and type-filter result until
  the TTL expires. Any new field `toMap()` doesn't emit inherits this.
- **Clients are GROUPED BY BUILDING, and the key is DERIVED, never stored**
  (2026-08-28). `buildingKeyFor` / `buildingsIn` / `buildingCountsIn`
  (`clients/domain/policies/client_building.dart`) reduce the street line down
  to the address without its unit — "914-4450 Prom. Paton" and
  "1207-4450 Prom. Paton" are two units of one building. Same discipline as the
  display-only `overdue` status: nothing is written, so there is no field to
  backfill and no field the console can corrupt.
  **The CITY is part of the key.** Two towns hold the same civic number, and
  without it a Laval client turns up under a Montréal address with nothing on
  screen explaining why.
  **It reduces through `AddressParser.streetOnly` first**, so a legacy doc
  whose `address` still carries the locality lands on the same key as one the
  backfill has normalized. Skip that and the grouping breaks on exactly the
  buildings with the most history. `noFixedAddress` and a blank address answer
  null — a client with nowhere to go is not a building of one.
  **The floor is TWO clients.** An entry per address is the client list under
  another name, and the menu has to stay readable.
  **It is a MENU, not a chip** (`ClientAddressFilterMenu`), and that is the one
  place the clients filter bar departs from its own rule: the type options are
  the fixed `ClientType.pickable` set with no vocabulary to discover, while
  addresses are discovered from the data and there can be dozens, which a
  horizontally-scrolling chip row cannot hold. It is still a peer — one sealed
  `ClientsFilterBuilding(key)`, so selecting one clears whichever chip was on,
  and picking the selected one clears back to `ClientsFilterAll`. It renders
  NOTHING when no address is shared; an empty menu is a control that looks
  broken, and on a small roster that is the normal state.
  **The per-row "18 units" pill is ONE reduction the list shares**
  (`clientBuildingCountsProvider`), passed into `ClientTile` as
  `buildingCount` — never a provider watch per row, the same rule
  `employeeJobsTodayProvider` keeps. It is deliberately NOT tappable: the whole
  row is one `InkWell`, so a tappable pill inside it is a nested gesture on a
  48px target, and the menu is where filtering belongs. `ClientTile` is reused
  by the booking flow's client picker, which passes nothing and shows no pill.
  **`fetchClientsByBuilding` / `fetchBuildings` read the SAME bounded cached
  window as the type filter**, so the whole feature costs no extra Firestore
  read inside the TTL and needs no index. It inherits that window's bound: past
  the cap the menu sees a prefix of the roster. Archived clients are excluded,
  the same rule the type filter keeps.
- **The Wave sync badge needs a LIVE doc read, and `ClientDetailView` is the one
  surface that has one** (2026-08-07). Every other client surface is a one-shot
  read — a paginated page, or the repository's cached scan window — and
  `wave.syncState` is function-owned: the `waveUpsertCustomer` trigger stamps
  `pending` *after* the save has already returned, and — as of 2026-08-13 —
  enqueues AND drains that job inline, in the same invocation, so it usually
  reaches Wave and flips to `synced` within seconds rather than on a poll (the
  `waveSyncWorker` scheduler that used to own this drain is deleted; see
  `functions/CLAUDE.md`). So the record a screen holds always
  predates the state the badge is trying to show, and the edit sheet pops back
  a `copyWith` of that same record, which carries the PRE-EDIT sync state
  through by design (it must — `waveSyncState` is not the form's to write).
  The badge therefore could never move in response to an edit: it sat on
  "Synced with Wave" while the push was still queued, and Settings ›
  "Sync with Wave" — correctly — reported nothing left to send, because the
  inline drain had already sent it within seconds of the save.
  `clientStreamProvider`
  (`clients_providers.dart`, an `autoDispose.family` over
  `ClientsRepository.watchClient`) is the fix; the view keeps the handed-in
  record as a **fallback**, so an offline or refused read leaves the detail on
  screen instead of blanking it. Don't "simplify" the badge back onto a
  passed-in record, and don't try to fix it by writing an optimistic `pending`
  client-side — that would fork `mappedFieldsHash`'s projection into Dart, and
  only the server knows whether an edit touched a Wave-mapped field.
  This listener deliberately does **not** patch the search/scan cache:
  `_patchWindow` merges `toMap()`, which omits `wave`, so the cached copy keeps
  a stale sync state on purpose.
- **A no-op push must HEAL the client's sync state, or the badge sticks
  forever.** `upsertCustomer`'s already-synced short-circuit
  (`functions/wave/customers.js`) returns `noop` without touching Wave — and it
  now clears a stale `pending`/`error` via `healSyncState` before it does. That
  state is reachable from an ordinary pair of edits: the first marks the doc
  `pending` and enqueues, the second puts the mapped fields BACK, and
  `shouldEnqueueClientWrite`'s rule 2 skips that write entirely — so the job the
  first edit left behind arrives with nothing to push, and nothing else ever
  clears the flag. `healSyncState` re-reads and re-hashes **inside the
  transaction** rather than trusting the caller's hash: an edit landing in that
  window must not be marked synced, or the badge claims Wave has data still
  sitting in the outbox — the exact lie it exists to remove. It writes
  `syncState`/`syncError` only, never `lastSyncedAt` (nothing reached Wave just
  now), and the write re-fires the trigger harmlessly — unchanged mapped fields
  return at rule 1. `tallyUpsert` still counts `noop` as nothing: no Wave
  mutation was made, and the admin must not be told a client was pushed.
- **`jobCount` is recomputed absolutely, never incremented.** `recountClientJobs`
  (`functions/client_job_count.js`) runs `retry: true`, so a retried event would
  double-count a `FieldValue.increment`; it runs a `count()` aggregate and SETS
  the value. It fires only when `clientId` actually changes (create, delete,
  reassignment) — an ordinary title or time edit costs zero reads — and writes
  with `update()`, not `set({merge: true})`, so a client removed out-of-band is
  never resurrected as a count-only stub. Backfill is lazy: a client's count
  self-heals on its next appointment write, and a row renders nothing (never
  `0`) until the field exists.
- **`mobile` is no longer editable and self-heals into `phone`.** The edit sheet
  dropped the second phone field (owner change 5), so `EditClientSheet._save`
  promotes a stored `mobile` into `phone` when `phone` is empty and clears
  `mobile` either way, on every save. Without that, a stored number would sit on
  the doc forever — invisible, uneditable, still matched by `matchClientDocs`
  (which reads `mobile`) and still in the Wave payload. There is no migration
  script and none is needed; the fleet heals as clients are edited.
  **The Wave IMPORT folds the same way, and it has to**
  (`importedPhone`, `functions/wave/mappers.js`, 2026-08-19): it resolves ONE
  phone — Wave's `phone`, else Wave's `mobile`, else a number lifted out of the
  customer NAME — and always writes `mobile: ''`. Each leg closes a way the
  number reached the doc but not the field anything dials (the Call button, the
  `clientPhone` denormalized onto every appointment, the next push back to
  Wave). The `mobile` leg additionally stops the import UN-healing a doc the app
  had already folded: the app never clears Wave's copy (`toWaveCustomerInput`
  omits an empty field rather than blanking it), so the next run read the value
  still sitting there and put it back. The NAME leg is the same rule
  `liftPhoneFromName` applies at the keyboard, and it is the one that matters
  most here — this business names a person by their phone number in Wave, so a
  customer added THERE routinely arrives called "5145551234" with the phone box
  empty, and no in-app save ever repaired it (`composeStored` reads a name made
  of digits as a business and leaves it alone). **Only the phone half of the
  lift is taken** — `name` is Wave's customer identity, mirrored verbatim, and
  rewriting it locally would push a rename to Wave on that client's next edit.
  The resolved number is rendered "(514) 555-1234" when it is NANP, the shape
  `PhoneInputFormatter` gives anything typed in the app; that is the durable
  form of what `backfill-client-phone-formatting.js` did once by hand, and
  `formatNanpNumber` moved to `client_name_utils.js` so the two share it.
  Because the caller hashes these resolved fields into `wave.lastSyncedHash`,
  a reshaped number does NOT enqueue a push — Wave keeps its own spelling until
  that client is next edited in-app. Don't "fix" that by hashing Wave's raw
  values instead: every import would then re-enter the whole roster into the
  outbox.
- **`clients/{id}.name` IS WAVE'S CUSTOMER NAME, and what it holds depends on
  who the client is** (owner call 2026-08-14). `toWaveCustomerInput` syncs it
  VERBATIM, and it is what shows on Wave's customer list and on an invoice —
  Wave gets `phone` as its own field too, but the name is what people read.
  **A PERSON is named by their phone number, BARE** — "5145551234", NOT the
  "(514) 555-1234" the `phone` field itself stores (owner call 2026-08-16,
  which narrowed the 2026-08-14 rule) — because the invoicing workflow there
  identifies people by number and wants it unpunctuated; their real name is in
  `firstName`/`lastName`, so nothing is lost. **Only the NAME is reduced: the
  `phone` field stays formatted** and `PhoneInputFormatter` still masks it as
  it is typed, so nothing about the phone-storage rule below changed. The
  reduction is the shared **`bareNumber`** (`core/validators/phone_format.dart`,
  hand-mirrored in `client_name_utils.js`) — digits only, keeping a leading
  `+` so an international number survives, falling back to the raw text when
  there is nothing to strip. It is the same primitive `dialableUri` uses, and
  it is **NOT** `ClientNamePolicy._digits`/`digitsOf`, which additionally sheds
  the leading 1 of an 11-digit NANP number: that is right for COMPARING two
  spellings and wrong for a value that gets stored and pushed to Wave. The
  branch stays idempotent across the change because `stripPhone` digit-matches
  rather than only suffix-matching, so a name already in either shape reduces
  to `''`. Data half: `functions/scripts/backfill-client-name-digits.js`
  (idempotent, `--dry-run`, deliberately **no `--since`** — this is a reformat,
  not a rename, so age is no reason to leave a doc inconsistent). It patches a
  doc **only when `stripPhone(name)` comes back EMPTY**, i.e. the name already
  IS that client's own number and there is no human name in it to lose, which
  is what makes it structurally incapable of renaming anybody — strictly
  narrower than re-running `backfill-client-name-with-phone.js`, and it must
  stay that way. **A BUSINESS keeps its name** —
  "3101-5696 qc inc.", "1505 Village de Bergerac" — because that name IS its
  identity in Wave, a number in its place is unrecognisable on an invoice, and
  unlike a person there is usually no first/last to fall back on.
  **`ClientNamePolicy.looksLikeBusinessName` is what catches the Wave-imported
  ones, and it is a HEURISTIC deliberately BIASED toward "business"**: ANY
  digit left in the name once the client's own number is stripped ("Condo 706",
  "1505 Village de Bergerac", "3101-5696 qc inc."), or a company/property token
  like `inc`/`ltée`/`group`/`syndicat`/`copropriété`, matched accent-folded and
  bounded by non-letters so "Vincent" and "Enrico" stay people. The import sets
  no `type`, so the name is the only evidence there is, and the two mistakes
  are not symmetrical: a false positive leaves a client named exactly as it
  already was, while a false negative renames a real company on live Wave
  invoices. Expect to ADD tokens as the dry run turns up names it missed — that
  list is the one part of this rule that can only be learned from the data. A false positive merely leaves a client named as
  it already was; a false negative renames a real company on live invoices,
  which is why the backfill lists every doc it matched.
  **The app never renders a person's `name`.** Every in-app surface reads
  `ClientRecord.displayName`, which strips any trailing number and branches:
  **a BUSINESS shows its business name, a PERSON shows their `firstName` +
  `lastName`.** That branch is the whole point — those two halves mean
  different things on the two kinds of client (on a person they ARE the client,
  on a business they are only its contact person), so preferring them
  everywhere renders "Vogas Plumbing" as "Marc Tremblay" on the card for a
  commercial job. `ClientNamePolicy.isBusiness` owns the test: the
  `commercial`/`building` types, **plus any doc carrying the legacy
  `businessName`** — those predate the `type` field, so they arrive `unset` and
  would otherwise be read as people. Every branch ends at the same three
  fallbacks in a different order, so a client missing the field its own branch
  prefers still renders something.
  This REVERSED `backfill-client-phone-from-name.js`, which ran against prod
  2026-08-08: it lifted the number out of `name` into `phone` and renamed
  `name` to "First Last" — correct for the app, but it renamed every one of
  those customers in Wave too. `backfill-client-name-with-phone.js` is the
  data half of the current rule (idempotent, `--dry-run`, `--since` so it
  skips recently-added clients). **Its dry run prints two lists in FULL and
  both must be read before going live**: every client it treated as a BUSINESS
  and therefore left alone (check for a person the heuristic caught), and
  every client it renames that has no first/last on file — for those the
  stored `name` is the ONLY copy, so `patchFor` splits it into the halves in
  the same write, and the list is where a mis-split gets caught.
  **The 2026-08-14 prod run predated that split and DESTROYED those names**
  (504 renamed). The only surviving copy is `clientName` on the client's
  SETTLED appointments — `propagateClientEdits` gates on `hasWorkLeft`, so a
  visit that had already ended still carries the pre-rename name.
  `restore-client-name-halves.js` writes those back into the halves and
  **never touches `name`**, which is Wave's customer identity; it reports, and
  leaves alone, anything reading as a business.
  `docs/audits/audit-renamed-client-names.js` is its read-only twin and the two
  are kept deliberately in step — an operator reading one rule's report and
  running another rule's repair is the failure mode. Both scan the client's
  appointments **ordered `startTime` DESC on the existing
  `(clientId, startTime DESC)` composite**: with no `orderBy` the limit takes
  an ARBITRARY slice, so a busy client's whole window can be future visits and
  the report calls a recoverable name unrecoverable.
  The one owner is **`ClientNamePolicy`** (`clients/domain/policies/`),
  hand-mirrored as **`functions/client_name_utils.js`**; their tests share
  worked examples, so a divergence fails a test. Consequences that must stay in
  sync:
  **`composeStored` is idempotent on BOTH branches** — a person's number
  recomposes to itself, a business's name comes back stripped and unchanged —
  which is what makes the backfill re-runnable and every ordinary save safe.
  **But NO SAVE PATH MAY CALL `composeStored` DIRECTLY — they compose through
  `ClientNamePolicy.composeSave`, which returns the stored name AND the two
  halves** (2026-08-15). For a person `composeStored` REPLACES the typed name
  with the phone number, so on a doc whose `firstName`/`lastName` are empty
  that name is the only copy of it and the save destroys it in place, with no
  Firestore history to recover from. That is not theoretical: the Name field is
  `required` on both sheets while both halves are `optional`, so the ordinary
  add-a-client flow reproduced it, the client then rendered as a bare number
  everywhere, and re-typing the name in the edit sheet did it again —
  `baseNameFor` returns `''` for such a doc, so the required field opens blank.
  `composeSave` splits the base name into the halves instead. It passes through
  untouched in exactly three cases, and each matters: the stored name came back
  UNCHANGED (a business, or a person with no number — nothing was replaced, so
  nothing is at risk), a half is ALREADY populated (never clobber a name that
  is there — and on a business the halves are the CONTACT PERSON, not the
  client), or there is no base name. `splitPersonName` is the mechanical split
  (last whitespace token is the surname), hand-mirrored ONCE on the JS side, as
  `splitName` in `functions/scripts/backfill-client-name-with-phone.js` — whose
  `patchFor` carries the halves in the same patch for the same reason.
  **There are TWO implementations, not three:**
  `restore-client-name-halves.js` **imports** it
  (`const {splitName} = require("./backfill-client-name-with-phone");`) and
  re-exports it, so it is a caller, not a twin. Keep it that way — a second JS
  copy is what the Dart↔JS pair already costs, and a third would drift silently.
  Both client sheets compose on save, and **both must pass `type` (and the
  edit sheet the stored `businessName`), or an ordinary save renames a
  business to its phone number on the invoices it appears on.** The edit sheet
  seeds its name field from `baseNameFor`, never `displayName`: on anything
  read as a person the latter returns the first/last halves, and the Wave
  import sets no `type`, so seeding a contact person and saving would rename
  the customer in Wave.
  **`propagateClientEdits` must strip too** — it fans `clientName` onto future
  appointments, and the app writes the DISPLAY name at booking, so without
  `clientDisplayName` the two disagree and cards start showing the number.
  **The backfill's base name is the STORED `name`, never `displayName`** — a
  business carries the business in `name` and a CONTACT PERSON in first/last,
  and a doc whose `type` was never picked reads as a person, so writing the
  display name back would rename "Vogas Plumbing" to "Marc Tremblay" on real
  Wave invoices, unrecoverably from the doc. **The backfill stops there** — it
  hands `composeStored` the raw stored `name` and never consults the halves.
  The first/last fallback belongs to `ClientNamePolicy.baseNameFor`, which is
  **Dart-only and has no JS twin**: only the EDIT SHEET needs it, because a
  form cannot seed a required field with nothing, where the backfill can just
  compose a doc whose name is junk to its number. (This bullet used to describe
  the fallback as the backfill's, and `baseNameFor` carried a pointer to a
  `functions/` function that has never existed.)
  **The rules cap on `name` is 225, not 200** — it was sized to the old
  "<typed name> <phone>" shape, `TextLimits.personName` (200) + a space +
  `TextLimits.phone` (24). The current rule can't reach that (a business name
  caps at 200, a number at 24), but the cap STAYS: docs written under the old
  shape are still in the collection, and a cap under a stored value makes that
  doc permanently un-updatable with an opaque `permission-denied`. `text_limits_test.dart` pins the sum against the rules
  text; the two are exactly equal, so a bump on either side breaks it loudly.
  **A number typed or pasted into the NAME field is lifted into the phone
  field** (`liftPhoneFromNameField`, wired to both sheets' name `onChanged`) —
  the interactive form of the 2026-08-08 backfill, so the collection cannot
  drift back into holding undialable numbers. It is quiet unless the phone
  field is EMPTY and the name holds a clean 10-digit number, and a name that is
  nothing but the number keeps it (the field is required — emptying it reads as
  the paste having vanished).
  **`onChanged` is NOT the only entry point — `AddClientSheet.initState` calls
  it on the SEEDED name too, and must keep doing so.** The seed is a
  programmatic `controller.text =` write, which fires no `onChanged`, and the
  inline "add client while booking" flow seeds it from the client-search query
  — which in this business is routinely the phone number, since people are
  identified by one. For as long as that call was missing, the most common way
  a client got added stored a doc whose `name` was a bare number and whose
  `phone` was EMPTY: nothing could dial it, not the Call button, not the
  `clientPhone` denormalized onto every appointment, not the Wave payload. A
  new entry point that seeds the name needs the same call.
  **The lift trims the number's own brackets at the SEAM it cut, via
  `_openSeam`/`_closeSeam`** — NOT by widening `_edgeSeparators`, which
  `stripPhone` shares and where a trailing bracket is usually the name's own
  ("Depanneur (Nord)"). The candidate run starts and ends on a digit, so
  "Marc Tremblay (514) 555-1234" — the shape the app itself renders, and the
  shape a number is pasted in — used to leave "Marc Tremblay (" behind, which
  `composeSave` then split into a lastName of "(" that every card rendered.
  Mirrored by `OPEN_SEAM`/`CLOSE_SEAM` in `functions/client_name_utils.js`;
  the Wave import takes only the phone half, so that mirror is parity, not
  behaviour.
- **The street + apt precedence rule has ONE owner: `AddressParser.canonicalFrom`.**
  Both client save paths resolve their stored address through it — the explicit
  apt field wins over an apt embedded in the street text, and a blank one keeps
  the embedded value. It was a verbatim copy in each sheet, which is two owners
  for a rule whose two answers must agree on the same typed input.
- **`clients/{id}.address` is the STREET LINE, and every read composes the rest
  back on** (2026-08-28). `city`/`province`/`postalCode`/`country` are their own
  fields, so an `address` that also carries them stores each one twice and lets
  the two copies drift. The pair that owns this is
  `AddressParser.streetOnly` / `composeFull`, and `ClientRecord` exposes them as
  `streetLine` / `fullAddress` so the five-field call cannot be spelled wrong at
  one of its six sites. **`composeFull` reduces through `streetOnly` FIRST, and
  that is not defensive tidying** — the collection holds BOTH shapes and always
  will: the Wave import writes a street line, the app wrote the whole picked
  string until this change, and the console can write either. Skip the reduce
  and a legacy doc renders its city twice. `streetOnly` strips from the TAIL, so
  `100 Main St, Building A` keeps its second segment, and it never strips the
  last one — a street that IS the city name must not reduce to nothing. It
  hand-mirrors `streetFromAddress` (`functions/wave/mappers.js`), which the Wave
  push has needed all along for the same reason; keep the two in step.
  **Booking must compose, not copy.** `AppointmentRecord.address` is a lone
  string with no locality fields of its own, denormalized once and kept forever,
  so handing it `streetLine` costs every job on the calendar its city — and with
  it the directions and the day route. Same for anything handed to
  `AddressMapLauncher`.
  Wave is unaffected by the shape: `mappedFieldsHash` hashes the OUTPUT of
  `toWaveCustomerInput`, which already ran `streetFromAddress`, so both shapes
  produce the same `addressLine1` and the same hash —
  `shouldEnqueueClientWrite` Rule 1 refuses the write. A backfill normalizing
  the field therefore pushes NOTHING to Wave. Don't re-derive that conclusion
  from the raw field; it holds because of where the hash is taken.
  The stored field still drifts back without the source fix:
  `fillAddressControllersFromText` writes the reduced street, because
  `ParsedAddressFields.street` is `null` on an address with no apt and the
  controller was left holding whatever Places returned. That null was the root
  cause — don't reintroduce a `fields.street != null` guard around the write.
  **The JS half is `functions/client_address_utils.js`**
  (`streetFromAddress` / `composeFullAddress`), and **`propagateClientEdits`
  compares the COMPOSED address, never the raw field.** That is the rule the
  whole migration hangs off, in both directions: an appointment carries ONE
  address string and no locality fields of its own, so fanning a stored street
  line onto it destroys the city on a live job unrecoverably — and because both
  shapes compose to the same string, normalizing the client field propagates
  NOTHING. `functions/scripts/backfill-client-address-street.js` is safe to run
  only while that holds; if the comparison ever regresses to the raw field,
  that script becomes destructive. Pinned by "normalizing `address` to the
  street line propagates NOTHING" in `client_propagation.test.js`. The composed
  comparison also fixed a bug that predated the split: the app books the
  composed address while the doc stores the canonical `4-1234 …`, so an
  apt-bearing client never matched `from` and its appointments silently never
  took an address correction — nor did a city-only edit, which never touches
  `address` at all.
  The backfill is HYGIENE, not a fix — every read already composes, so nothing
  user-visible changes. It **cannot lose information**: it only removes
  trailing segments that match fields still on the same doc, so the old string
  is rebuildable from the doc exactly. It skips a doc with NO locality fields
  rather than guessing (there `streetFromAddress` falls back to the first
  segment, which is right for the Wave push and wrong for a write), and it
  never writes an empty address. Wave gets nothing: `mappedFieldsHash` hashes
  `toWaveCustomerInput`'s OUTPUT, which already ran `streetFromAddress`.
- **Inline add-client while booking:** `ClientsRepository.addClient` returns the
  created `ClientRecord` with its generated Firestore doc id (NOT `void`) — the
  appointment form's "Add new client" flow links the appointment to that id.
  Don't revert it to `void`. All add-client sheet opens go through
  `showAddClientSheet` (`clients/widgets/sheets/add_client_sheet.dart`), which
  pops the created client and gates its result on `context.mounted`; pass
  `settleFocus: true` when opening from a search field (the appointment client
  picker). The affordance lives in the shared `ClientSearchField` (`onAddNew`
  callback, injected null when unused) and is admin-only only because the
  appointment forms are admin-only surfaces — gate it explicitly if it's ever
  reused somewhere non-admin. Both appointment hosts guard the open via the
  shared `InlineAddClientHost` mixin (`requestAddClient`, in
  `calendar/widgets/sheets/inline_add_client_host.dart`) — an in-flight flag,
  because the settle delays the modal barrier so an unguarded double-tap stacks
  two sheets → duplicate client. Mix it into any new inline-add host rather than
  re-copying the flag.

- **History carries its date on a LEFT RAIL, under a sticky month bar, and it
  builds its own slivers** (P7 Phase D, 2026-08-11 —
  `docs/archive/2026-08-11-history-restyle.md`). The rail is what leaves
  `AppointmentCard` untouched: the two rejected layouts both had to restyle the
  one shared card. Consequences, each of which was a real failure:
  **Each month is a `SliverMainAxisGroup`, not a bare
  `SliverPersistentHeader(pinned: true)` beside its list.** Repeated pinned
  headers **stack** — a year of history parks twelve bars across the top of the
  screen. A pinned header bounded by its own group scrolls away with its rows
  instead. Pinned by a test that reads the bars actually PAINTED in the
  viewport; a bar pushed out stays in the tree inside the cache extent, so
  presence alone proves nothing.
  **A sticky header cannot live inside `PagedListView`, so
  `AppointmentHistoryView` re-owns what ISP used to do** — the prefetch
  trigger, the new-page spinner/retry footer, and the one that is easy to miss:
  **`PagingController.refresh()` only RESETS the state, it does not fetch.**
  `_requestFirstPage` is what notices the reset and asks again; without it both
  pull-to-refresh and the first-page Retry leave the skeleton shimmering
  forever with no request in flight. Every `fetchNextPage()` from a builder
  goes post-frame — the controller assigns its own value synchronously, so
  calling it mid-build mutates a listenable during layout.
  **The first-page indicators must NOT gain a scroll wrapper.** `AppEmptyState`
  carries its own `SingleChildScrollView`, so wrapping it in a
  `RefreshIndicator`'s `CustomScrollView` leaves two controllerless primary
  scrollables under the screen's `PrimaryScrollScope` — the Scrollbar crash
  above. ISP did not scroll those states either; pull-to-refresh on an empty
  history is not a regression to "restore".
  **SEARCH renders FLAT and the rail changes shape there.** Search spans every
  appointment, so hits are not a contiguous run of days and month bars over
  them are noise — the rail therefore shows the **month** instead of the
  weekday, plus the **year** when the hit is not from the current one (read
  from `currentDayProvider`, never `DateTime.now()`). A chip filter alone keeps
  the month bars: only a text query goes flat.
  **There is ONE count, `18 JOBS · 2 CANCELLED`, and no per-month counts ever.**
  History is paginated, so a per-month figure could only report what had loaded
  and would climb while you read it. The cancelled clause is a SUBSET of the
  total, the same shape as the agenda's `4 JOBS · 1 DONE`, and search keeps the
  clause (`5 RESULTS · 1 CANCELLED`) — dropping it on one state reads as a
  different metric. The grouping, the tally and the two quick filters are the
  pure `clients/domain/history_grouping.dart`; the cancelled-vs-complete
  vocabulary lives with the rest of it in `appointment_status_values.dart`
  (`isCancelledStatusRaw` / `isCompletedStatusRaw`), never re-spelled as a
  `== 'cancelled'` at a call site. The quick-filter chips bind to the existing
  `statusLabel` ("Complete"/"Cancelled") — don't add history-specific status
  wording beside it. The **bold year separator is deleted**: the month bar
  already carries the year.
  **Both O(N) passes over the rows — `tallyOf` and `monthSectionsOf` — are
  memoized on the IDENTITY of the row list, so every list handed down must be
  a STABLE INSTANCE, and that has one owner: `_RowCache` in
  `appointment_history_view.dart`.** Memoizing at the consumer alone is a
  no-op here and silently was one: `PagingState.items` re-flattens every
  loaded page on each access, and both filter passes build a new list, so the
  memos compared two freshly-allocated lists and re-ran on every rebuild — per
  keystroke while searching, and on every `employeeColorMapProvider` /
  `currentDayProvider` emission, over a history that grows with scroll depth.
  Cache at the SOURCE, keyed on a record (`List` members compare by identity,
  which is what tracks a new page or a new search result; the query and chips
  compare by value). A new row-producing path needs its own cache entry, not a
  second memo at the far end.

# Client Archive + Delete Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let an admin archive any client (hidden from the list, still searchable and bookable) and delete a client that has no appointment history, both reachable by swiping a row in the clients list.

**Architecture:** `archived` is a real boolean on the client doc, filtered **server-side** so the paginated list's cursor and end-of-list logic stay untouched. Delete moves behind a new `deleteClient` callable that runs a live `count()` aggregate over the client's appointments and refuses when non-zero; `allow delete` on `/clients` is withdrawn so deletion is Admin-SDK-only.

**Tech Stack:** Flutter / Riverpod / freezed, Firestore, Cloud Functions (Node 24), `flutter_slidable`, `infinite_scroll_pagination`.

**Spec:** `docs/plans/2026-08-03-client-archive-and-delete.md`

---

## Read first

- `docs/plans/2026-08-03-client-archive-and-delete.md` — the approved design, including why each decision was made.
- `CLAUDE.md` → "A client is never removed" invariant. **This plan reverses it.** Update that bullet in Task 19.
- `.claude/rules/error-handling.md` — typed failures, cause+tag notices, `logger.warn` label must match the tag.
- `.claude/rules/frontend.md` — design tokens, `showConfirmDialog`, notices.

## Ordering constraints (do not reorder)

1. **Tasks 1–4 must ship before Task 5.** Task 5 adds the server-side filter; until every doc carries `archived`, a filtered query hides the docs that don't. Task 4 is the backfill.
2. **Task 12 must ship after Task 11.** The rules withdraw `allow delete`; the Dart delete path must already be calling the callable.

## File structure

| File | Responsibility |
|---|---|
| `lib/features/clients/domain/models/client_record.dart` | + `archived` field |
| `lib/features/clients/domain/clients_failure.dart` | **new** — sealed `ClientsFailure` family |
| `lib/features/clients/domain/policies/client_delete_policy.dart` | **new** — `canDeleteClient` |
| `lib/features/clients/domain/models/clients_filter.dart` | **new** — sealed `ClientsFilter` |
| `lib/features/clients/domain/clients_repository.dart` | + archive/unarchive, + archived fetch |
| `lib/features/clients/data/firebase_clients_repository.dart` | server filter, archive write, callable delete |
| `lib/features/clients/application/client_form_controller.dart` | archive outcome, delete outcome |
| `lib/features/clients/widgets/views/clients_list_view.dart` | `Slidable` wrapper, filter wiring |
| `lib/features/clients/widgets/sections/client_type_filter_bar.dart` | + Archived chip |
| `lib/features/clients/widgets/cards/client_tile.dart` | archived badge |
| `lib/features/clients/widgets/views/client_detail_view.dart` | archive / gated delete |
| `functions/clients.js` | **new** — `deleteClient` callable |
| `functions/scripts/backfill-clients-archived.js` | **new** — one-off backfill |
| `firestore.rules` | `archived is bool`; withdraw `allow delete` |
| `firestore.indexes.json` | `(archived, name, __name__)` composite |
| `lib/core/testing_flags.dart` | **deleted** (Task 18) |

---

## Task 1: `archived` on ClientRecord

**Files:**
- Modify: `lib/features/clients/domain/models/client_record.dart`
- Test: `test/features/clients/client_record_test.dart`

- [ ] **Step 1: Write the failing tests**

Add to `test/features/clients/client_record_test.dart`:

```dart
test('archived defaults to false when the field is absent', () {
  final record = ClientRecord.fromMap('c1', {'name': 'Acme'});
  expect(record.archived, isFalse);
});

test('archived round-trips through fromMap and toMap', () {
  final record = ClientRecord.fromMap('c1', {'name': 'Acme', 'archived': true});
  expect(record.archived, isTrue);
  expect(record.toMap()['archived'], isTrue);
});

test('toMap still never emits function-owned fields', () {
  final map = ClientRecord.fromMap('c1', {
    'name': 'Acme',
    'jobCount': 7,
    'waveCustomerId': 'w1',
  }).toMap();
  expect(map.containsKey('jobCount'), isFalse);
  expect(map.containsKey('waveCustomerId'), isFalse);
  expect(map.containsKey('archived'), isTrue);
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/features/clients/client_record_test.dart`
Expected: FAIL — `archived` isn't defined on `ClientRecord`.

- [ ] **Step 3: Add the field**

In the `@freezed` factory, beside `noFixedAddress`:

```dart
    @Default(false) bool archived,
```

In `fromMap`, beside the other bools:

```dart
      archived: (data['archived'] as bool?) ?? false,
```

In `toMap()`, beside `noFixedAddress`:

```dart
    'archived': archived,
```

- [ ] **Step 4: Regenerate freezed and run**

Run: `dart run build_runner build --delete-conflicting-outputs`
Run: `flutter test test/features/clients/client_record_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/features/clients/domain/models/client_record.dart lib/features/clients/domain/models/client_record.freezed.dart test/features/clients/client_record_test.dart
git commit -m 'feat(clients): add archived to ClientRecord'
```

---

## Task 2: Rules accept `archived`

**Files:**
- Modify: `firestore.rules` (`isValidClientData`)

- [ ] **Step 1: Add the type check**

In `isValidClientData`, after the `noFixedAddress` line:

```
        && (!('archived' in data) || data.archived is bool);
```

Move the `;` off `noFixedAddress` onto this new final line.

- [ ] **Step 2: Validate**

Use Firebase MCP `firebase_validate_security_rules` with `type: firestore`, `source_file: firestore.rules`.
Expected: only the 3 known `isAvailabilityOnlyChange` warnings. Any other error is yours.

- [ ] **Step 3: Commit**

```bash
git add firestore.rules
git commit -m 'feat(clients): allow archived on client writes'
```

---

## Task 3: Wave import writes `archived`

**Files:**
- Modify: `functions/wave/customers.js`
- Test: `functions/__tests__/wave_customers.test.js`

**Why:** `importCustomers` creates client docs outside the Dart repository. A doc it creates without `archived` is invisible to the filtered list query from Task 5.

- [ ] **Step 1: Write the failing test**

**Read `functions/__tests__/wave_customers.test.js` first** and reuse whatever
db/fetch fakes it already defines — do not introduce new ones. The assertion to
add, expressed against that file's existing harness, is:

> Import one page containing a customer that does not yet exist as a client.
> Assert the created client doc carries `archived: false`.
> Then import a page whose customer DOES already exist as an archived client,
> and assert the update branch leaves `archived` as `true`.

The second half is the one that matters: setting `archived` on the update
branch would silently un-archive a client on every scheduled import.

- [ ] **Step 2: Run to verify it fails**

Run: `cd functions && npx jest __tests__/wave_customers.test.js`
Expected: FAIL — `archived` is `undefined`.

- [ ] **Step 3: Set the field on create only**

In `importCustomers`, on the branch that creates a new client doc, add `archived: false` to the written object. **Do not add it to the update branch** — that would un-archive a client on every import.

- [ ] **Step 4: Run**

Run: `cd functions && npx jest __tests__/wave_customers.test.js`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add functions/wave/customers.js functions/__tests__/wave_customers.test.js
git commit -m 'feat(clients): wave import stamps archived on new clients'
```

---

## Task 4: Backfill script

**Files:**
- Create: `functions/scripts/backfill-clients-archived.js`

**This must run against prod BEFORE Task 5 deploys.**

- [ ] **Step 1: Write the script**

```js
#!/usr/bin/env node
// One-off: sets `archived: false` on every /clients doc that lacks the field.
//
// WHY this exists: the clients list query filters `where('archived','==',false)`,
// and Firestore EXCLUDES documents missing the field a query filters on. Any
// client without `archived` is therefore invisible in the list while still
// appearing in search (which scans an unfiltered window) — a confusing partial
// disappearance rather than an obvious failure.
//
// RUN THIS BEFORE deploying the filtered query. Reversed, every un-backfilled
// client vanishes from the list until this finishes.
//
// Idempotent: a doc that already has the field is skipped.
//
// Usage:
//   For prod:
//     $env:GOOGLE_APPLICATION_CREDENTIALS = "C:\path\to\prod-service-account.json"
//     node functions/scripts/backfill-clients-archived.js
//
//   For the local emulator:
//     $env:FIRESTORE_EMULATOR_HOST = "localhost:8080"
//     $env:GCLOUD_PROJECT = "schedulingapp-88727"
//     node functions/scripts/backfill-clients-archived.js
//
// Pass --dry-run to report what it would do without writing.

const {initializeApp, applicationDefault} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");

const DRY_RUN = process.argv.includes("--dry-run");
const BATCH_SIZE = 400;

async function main() {
  initializeApp({credential: applicationDefault()});
  const db = getFirestore();
  const snap = await db.collection("clients").get();

  let patched = 0;
  let skipped = 0;
  let batch = db.batch();
  let pending = 0;

  for (const doc of snap.docs) {
    if (typeof doc.data().archived === "boolean") {
      skipped += 1;
      continue;
    }
    patched += 1;
    if (DRY_RUN) continue;
    batch.update(doc.ref, {archived: false});
    pending += 1;
    if (pending >= BATCH_SIZE) {
      await batch.commit();
      batch = db.batch();
      pending = 0;
    }
  }
  if (!DRY_RUN && pending > 0) await batch.commit();

  console.log(
      `${DRY_RUN ? "[dry-run] " : ""}clients: ${patched} patched, ` +
      `${skipped} already had the field`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
```

- [ ] **Step 2: Lint**

Run: `cd functions && npm run lint`
Expected: no output.

- [ ] **Step 3: Dry-run against the emulator**

Run the emulator invocation from the header with `--dry-run`.
Expected: a count line, no writes.

- [ ] **Step 4: Commit**

```bash
git add functions/scripts/backfill-clients-archived.js
git commit -m 'chore(clients): add archived backfill script'
```

---

## Task 5: Server-side archived filter + index

**Files:**
- Modify: `lib/features/clients/data/firebase_clients_repository.dart:83-102`
- Modify: `firestore.indexes.json`
- Test: `test/features/clients/data/firebase_clients_repository_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
test('fetchClientsPage filters archived server-side', () async {
  final repo = FirebaseClientsRepository(firestore: fake);
  await fake.collection('clients').add({'name': 'Acme', 'archived': false});
  await fake.collection('clients').add({'name': 'Bell', 'archived': true});

  final page = await repo.fetchClientsPage(limit: 50);

  expect(page.map((c) => c.name), ['Acme']);
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/features/clients/data/firebase_clients_repository_test.dart`
Expected: FAIL — both clients returned.

- [ ] **Step 3: Add the where clause**

In `fetchClientsPage`, change the query construction:

```dart
    var query = _clients
        .where('archived', isEqualTo: false)
        .orderBy('name')
        .orderBy(FieldPath.documentId);
```

Everything below it — the `startAfter`, `_pageBoundaryNames`, the return — is **unchanged**. The server returns a full page of non-archived docs, so `items.last` is genuinely the page's last doc and the existing cursor stays correct.

- [ ] **Step 4: Add the composite index**

In `firestore.indexes.json`, in the `indexes` array:

```json
    {
      "collectionGroup": "clients",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "archived", "order": "ASCENDING" },
        { "fieldPath": "name", "order": "ASCENDING" },
        { "fieldPath": "__name__", "order": "ASCENDING" }
      ]
    },
```

- [ ] **Step 5: Run**

Run: `flutter test test/features/clients/data/firebase_clients_repository_test.dart`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add lib/features/clients/data/firebase_clients_repository.dart firestore.indexes.json test/features/clients/data/firebase_clients_repository_test.dart
git commit -m 'feat(clients): filter archived out of the paginated list server-side'
```

---

## Task 6: Archive write + archived/type reads

**Files:**
- Modify: `lib/features/clients/domain/clients_repository.dart`
- Modify: `lib/features/clients/data/firebase_clients_repository.dart`
- Test: `test/features/clients/data/firebase_clients_repository_test.dart`

- [ ] **Step 1: Write the failing tests**

```dart
test('setClientArchived merges and does not blank jobCount', () async {
  final doc = await fake.collection('clients')
      .add({'name': 'Acme', 'archived': false, 'jobCount': 7});

  await repo.setClientArchived(doc.id, archived: true);

  final stored = (await doc.get()).data()!;
  expect(stored['archived'], isTrue);
  expect(stored['jobCount'], 7);
});

test('fetchArchivedClients returns only archived, name-sorted', () async {
  await fake.collection('clients').add({'name': 'Zeta', 'archived': true});
  await fake.collection('clients').add({'name': 'Acme', 'archived': true});
  await fake.collection('clients').add({'name': 'Bell', 'archived': false});

  final result = await repo.fetchArchivedClients();

  expect(result.map((c) => c.name), ['Acme', 'Zeta']);
});

test('fetchClientsByType excludes archived', () async {
  await fake.collection('clients')
      .add({'name': 'Acme', 'type': 'commercial', 'archived': false});
  await fake.collection('clients')
      .add({'name': 'Bell', 'type': 'commercial', 'archived': true});

  final result = await repo.fetchClientsByType(ClientType.commercial);

  expect(result.map((c) => c.name), ['Acme']);
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/features/clients/data/firebase_clients_repository_test.dart`
Expected: FAIL — `setClientArchived` and `fetchArchivedClients` don't exist.

- [ ] **Step 3: Add to the interface**

In `lib/features/clients/domain/clients_repository.dart`:

```dart
  /// Archives or un-archives a client. Archived clients drop out of the
  /// paginated list but stay searchable and stay bookable — their `clientId`
  /// links on existing appointments are untouched.
  Future<void> setClientArchived(String id, {required bool archived});

  /// Archived clients, name-sorted, from the same bounded cached window
  /// `searchClients` scans — so the Archived chip costs no extra read inside
  /// the TTL and needs no composite index.
  Future<List<ClientRecord>> fetchArchivedClients();
```

- [ ] **Step 4: Implement**

In `firebase_clients_repository.dart`:

```dart
  @override
  Future<void> setClientArchived(String id, {required bool archived}) async {
    await _clients.doc(id).update({
      'archived': archived,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    // Merges over the stored doc — a plain substitution would drop the
    // function-owned jobCount/createdAt and blank the job count on every
    // search result until the TTL expires.
    _patchWindow(id, data: {'archived': archived});
  }

  @override
  Future<List<ClientRecord>> fetchArchivedClients() async {
    final window = await _clientScanWindow();
    if (window == null) return const [];
    final matches = [
      for (final doc in window.docs)
        if (doc.data['archived'] == true)
          ClientRecord.fromMap(doc.id, doc.data),
    ];
    final keyed = [
      for (final record in matches)
        (sortKey: record.displayName.toLowerCase(), record: record),
    ]..sort((a, b) => a.sortKey.compareTo(b.sortKey));
    return [for (final entry in keyed) entry.record];
  }
```

In `fetchClientsByType`, add the archived exclusion to the comprehension's `if`:

```dart
        if (doc.data['archived'] != true &&
            ClientType.fromRaw(doc.data['type']?.toString()) == type)
```

Leave `searchClients` alone — archived clients stay in search results by design.

- [ ] **Step 5: Run**

Run: `flutter test test/features/clients/data/firebase_clients_repository_test.dart`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add lib/features/clients/domain/clients_repository.dart lib/features/clients/data/firebase_clients_repository.dart test/features/clients/data/firebase_clients_repository_test.dart
git commit -m 'feat(clients): archive write plus archived and type reads'
```

---

## Task 7: `deleteClient` callable

**Files:**
- Create: `functions/clients.js`
- Test: `functions/__tests__/clients.test.js`

- [ ] **Step 1: Write the failing tests**

Create `functions/__tests__/clients.test.js`:

```js
const {performDeleteClient} = require("../clients");

function fakeDb({count, exists = true}) {
  const deleted = [];
  return {
    deleted,
    collection: (name) => ({
      doc: (id) => ({
        get: async () => ({exists, id}),
        delete: async () => {
          deleted.push({collection: name, id});
        },
      }),
      where: () => ({
        count: () => ({get: async () => ({data: () => ({count})})}),
      }),
    }),
  };
}

test("refuses a client that has appointments", async () => {
  const db = fakeDb({count: 3});
  await expect(performDeleteClient(db, "c1"))
      .rejects.toThrow(/client-has-history/);
  expect(db.deleted).toHaveLength(0);
});

test("deletes a client with no appointments", async () => {
  const db = fakeDb({count: 0});
  await performDeleteClient(db, "c1");
  expect(db.deleted).toEqual([{collection: "clients", id: "c1"}]);
});

test("refuses a client that does not exist", async () => {
  const db = fakeDb({count: 0, exists: false});
  await expect(performDeleteClient(db, "c1"))
      .rejects.toThrow(/client-not-found/);
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd functions && npx jest __tests__/clients.test.js`
Expected: FAIL — cannot find module `../clients`.

- [ ] **Step 3: Write the module**

Create `functions/clients.js`:

```js
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const logger = require("firebase-functions/logger");
const {getFirestore} = require("firebase-admin/firestore");

const {
  assertPayloadShape,
  requireString,
  assertAdmin,
  enforceDurableRateLimit,
} = require("./security");

const DELETE_RATE_MAX = 20;
const DELETE_RATE_WINDOW_MS = 60 * 60 * 1000;

/**
 * Deletes a client, refusing when it still has appointments.
 *
 * The count is a LIVE count() aggregate, deliberately not the denormalized
 * `jobCount` on the client doc: that field is lazily backfilled by
 * recountClientJobs, so it can be stale, missing, or wrong on a client whose
 * appointments were reassigned out-of-band. Deleting on a stale zero is
 * exactly the orphaned-history bug this gate exists to prevent.
 *
 * Pure-ish and exported for unit tests — takes an injected db.
 * @param {*} db Firestore instance.
 * @param {string} clientId Client doc id.
 * @return {Promise<void>}
 */
async function performDeleteClient(db, clientId) {
  const ref = db.collection("clients").doc(clientId);
  const snap = await ref.get();
  if (!snap.exists) {
    throw new HttpsError("not-found", "client-not-found");
  }

  const agg = await db
      .collection("appointments")
      .where("clientId", "==", clientId)
      .count()
      .get();
  const jobs = agg.data().count;
  if (jobs > 0) {
    throw new HttpsError("failed-precondition", "client-has-history");
  }

  await ref.delete();
}

// Guard order per .claude/rules/security.md: auth -> assertAdmin ->
// payload -> rate limit -> work. The payload is validated before a limiter
// slot is consumed so malformed bursts can't exhaust a real caller's window.
const deleteClient = onCall(
    {enforceAppCheck: true},
    async (req) => {
      if (!req.auth || !req.auth.uid) {
        throw new HttpsError("unauthenticated", "auth-required");
      }
      await assertAdmin(req);
      assertPayloadShape(req.data, new Set(["clientId"]));
      const clientId = requireString(req.data, "clientId", 128);
      if (clientId.includes("/")) {
        throw new HttpsError("invalid-argument", "invalid-clientId");
      }
      await enforceDurableRateLimit(
          "client-delete",
          req.auth.uid,
          DELETE_RATE_MAX,
          DELETE_RATE_WINDOW_MS,
      );

      await performDeleteClient(getFirestore(), clientId);
      logger.info("deleteClient: deleted", {uid: req.auth.uid, clientId});
    },
);

module.exports = {deleteClient, performDeleteClient};
```

- [ ] **Step 4: Run**

Run: `cd functions && npx jest __tests__/clients.test.js`
Expected: PASS, 3 tests.

- [ ] **Step 5: Lint**

Run: `cd functions && npm run lint`
Expected: no output.

- [ ] **Step 6: Commit**

```bash
git add functions/clients.js functions/__tests__/clients.test.js
git commit -m 'feat(clients): add deleteClient callable gated on live job count'
```

---

## Task 8: Export the callable

**Files:**
- Modify: `functions/index.js`

- [ ] **Step 1: Wire it up**

Beside the other requires:

```js
const clients = require("./clients");
```

Beside the other exports:

```js
exports.deleteClient = clients.deleteClient;
```

- [ ] **Step 2: Verify the export count**

Run: `cd functions && grep -c '^exports\.' index.js`
Expected: `26` (25 before this task).

- [ ] **Step 3: Run the full suite**

Run: `cd functions && npm run lint && npx jest`
Expected: lint silent; all suites pass.

- [ ] **Step 4: Commit**

```bash
git add functions/index.js
git commit -m 'feat(clients): export deleteClient'
```

---

## Task 9: `ClientsFailure` family

**Files:**
- Create: `lib/features/clients/domain/clients_failure.dart`
- Test: `test/features/clients/domain/clients_failure_test.dart`

**Why:** the callable refuses with `failed-precondition / client-has-history`. Without a typed failure the UI can only say "Something went wrong", which the user cannot act on.

- [ ] **Step 1: Write the failing test**

```dart
void main() {
  testWidgets('each failure maps to a distinct localized message', (
    tester,
  ) async {
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(builder: (c) {
        ctx = c;
        return const SizedBox();
      }),
    ));

    const hasHistory = ClientsFailureHasHistory();
    const notFound = ClientsFailureNotFound();

    expect(hasHistory.toLocalizedMessage(ctx), isNotEmpty);
    expect(
      hasHistory.toLocalizedMessage(ctx),
      isNot(notFound.toLocalizedMessage(ctx)),
    );
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/features/clients/domain/clients_failure_test.dart`
Expected: FAIL — `ClientsFailure` doesn't exist.

- [ ] **Step 3: Write the family**

```dart
import 'package:flutter/widgets.dart';

import 'package:scheduling/core/errors/failure.dart';
import 'package:scheduling/l10n/l10n.dart';

/// Typed failures for client writes. Mirrors `EmployeesFailure`.
sealed class ClientsFailure extends Failure {
  const ClientsFailure();

  String toLocalizedMessage(BuildContext context);
}

/// The client still has appointments, so deleting it would orphan that history.
class ClientsFailureHasHistory extends ClientsFailure {
  const ClientsFailureHasHistory();

  @override
  String toLocalizedMessage(BuildContext context) =>
      context.l10n.clients_deleteBlockedHasHistory;
}

/// The client doc was already gone — a concurrent delete, or a stale list.
class ClientsFailureNotFound extends ClientsFailure {
  const ClientsFailureNotFound();

  @override
  String toLocalizedMessage(BuildContext context) =>
      context.l10n.clients_deleteFailedNotFound;
}
```

- [ ] **Step 4: Add the ARB keys**

In `lib/l10n/app_en.arb`:

```json
  "clients_deleteBlockedHasHistory": "This client has job history, so it can't be deleted. Archive it instead.",
  "@clients_deleteBlockedHasHistory": {
    "description": "Shown when an admin tries to delete a client that still has appointments."
  },
  "clients_deleteFailedNotFound": "That client no longer exists.",
  "@clients_deleteFailedNotFound": {
    "description": "Shown when a delete targets a client doc that is already gone."
  },
```

Mirror both in `lib/l10n/app_fr.arb` (no `@` blocks there):

```json
  "clients_deleteBlockedHasHistory": "Ce client a un historique de travaux; il ne peut pas être supprimé. Archivez-le plutôt.",
  "clients_deleteFailedNotFound": "Ce client n'existe plus.",
```

A repo hook regenerates `gen-l10n` on ARB edits — **do not run `flutter gen-l10n` manually.**

- [ ] **Step 5: Run**

Run: `flutter test test/features/clients/domain/clients_failure_test.dart`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add lib/features/clients/domain/clients_failure.dart lib/l10n/app_en.arb lib/l10n/app_fr.arb test/features/clients/domain/clients_failure_test.dart
git commit -m 'feat(clients): add typed ClientsFailure family'
```

---

## Task 10: `canDeleteClient` policy

**Files:**
- Create: `lib/features/clients/domain/policies/client_delete_policy.dart`
- Test: `test/features/clients/domain/client_delete_policy_test.dart`

- [ ] **Step 1: Write the failing tests**

```dart
ClientRecord clientWith(int? jobCount) =>
    ClientRecord.fromMap('c1', {'name': 'Acme'}).copyWith(jobCount: jobCount);

void main() {
  test('a client with no jobs can be deleted', () {
    expect(canDeleteClient(clientWith(0)), isTrue);
  });

  test('a client with jobs cannot be deleted', () {
    expect(canDeleteClient(clientWith(3)), isFalse);
  });

  test('an unknown job count blocks deletion', () {
    // jobCount is lazily backfilled, so null means "not counted yet", NOT
    // zero. Treating it as zero would offer delete in exactly the case the
    // gate exists to prevent.
    expect(canDeleteClient(clientWith(null)), isFalse);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/features/clients/domain/client_delete_policy_test.dart`
Expected: FAIL — `canDeleteClient` undefined.

- [ ] **Step 3: Write it**

```dart
import 'package:scheduling/features/clients/domain/models/client_record.dart';

/// Whether the UI should OFFER delete for [client].
///
/// Advisory only — the `deleteClient` callable re-checks with a live count()
/// aggregate and is the real boundary. This exists so the swipe never offers
/// an action the server will refuse.
///
/// `jobCount` is lazily backfilled and renders nothing until it exists, so a
/// client with real history can legitimately carry no count. `null == 0` is
/// false, which withholds the action: missing means unknown, and unknown
/// withholds.
bool canDeleteClient(ClientRecord client) => client.jobCount == 0;
```

- [ ] **Step 4: Run**

Run: `flutter test test/features/clients/domain/client_delete_policy_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/features/clients/domain/policies/client_delete_policy.dart test/features/clients/domain/client_delete_policy_test.dart
git commit -m 'feat(clients): add canDeleteClient affordance policy'
```

---

## Task 11: Route delete through the callable

**Files:**
- Modify: `lib/features/clients/data/firebase_clients_repository.dart:146-153`
- Modify: `lib/features/clients/domain/clients_repository.dart`
- Test: `test/features/clients/data/firebase_clients_repository_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
test('deleteClient maps failed-precondition to ClientsFailureHasHistory',
    () async {
  when(() => callable.call<void>(any())).thenThrow(
    FirebaseFunctionsException(
      code: 'failed-precondition',
      message: 'client-has-history',
    ),
  );

  expect(
    () => repo.deleteClient('c1'),
    throwsA(isA<ClientsFailureHasHistory>()),
  );
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/features/clients/data/firebase_clients_repository_test.dart`
Expected: FAIL — the raw `FirebaseFunctionsException` escapes.

- [ ] **Step 3: Rewrite `deleteClient`**

Replace the body (and drop the `#pre-ship` TODO above it):

```dart
  @override
  Future<void> deleteClient(String id) async {
    try {
      await _functions.httpsCallable('deleteClient').call<void>({
        'clientId': id,
      });
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'failed-precondition') {
        throw const ClientsFailureHasHistory();
      }
      if (e.code == 'not-found') throw const ClientsFailureNotFound();
      rethrow;
    }
    // Drops the doc out of the cached window so search and the filters stop
    // returning it without paying for a fresh read.
    _patchWindow(id);
  }
```

Add a `FirebaseFunctions` constructor dependency alongside the existing `firestore` one, defaulting to `FirebaseFunctions.instance`, so tests can inject it. Update the doc comment on the interface method:

```dart
  /// Deletes a client. Refuses (throws [ClientsFailureHasHistory]) when the
  /// client still has appointments — the server re-checks with a live count().
  Future<void> deleteClient(String id);
```

- [ ] **Step 4: Run**

Run: `flutter test test/features/clients/data/firebase_clients_repository_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/features/clients/data/firebase_clients_repository.dart lib/features/clients/domain/clients_repository.dart test/features/clients/data/firebase_clients_repository_test.dart
git commit -m 'feat(clients): route client delete through the callable'
```

---

## Task 12: Withdraw `allow delete` on `/clients`

**Files:**
- Modify: `firestore.rules`

**Do this only after Task 11 is merged** — the Dart path must already call the callable.

- [ ] **Step 1: Remove the rule**

In the `/clients` match block, delete the `allow delete: if isAdmin();` line and the comment block above it that explains the `kShowTestingDeleteClient` carve-out. Replace with:

```
      // Delete is Admin-SDK-only, via the `deleteClient` callable, which
      // refuses a client that still has appointments. Rules cannot express
      // "only when this client has no appointments" — there is no cheap way to
      // count a foreign collection here — so the callable is the only place
      // that guarantee can live. Granting delete here would let an admin
      // session bypass it and orphan the client's job history.
```

- [ ] **Step 2: Validate**

Firebase MCP `firebase_validate_security_rules`, `type: firestore`, `source_file: firestore.rules`.
Expected: only the 3 known `isAvailabilityOnlyChange` warnings.

- [ ] **Step 3: Confirm no other delete grant remains on clients**

Run: `grep -n "allow delete" firestore.rules`
Expected: exactly one hit, in the `/users` block (the `#compat-1.37.1` shim). No `/clients` hit.

- [ ] **Step 4: Commit**

```bash
git add firestore.rules
git commit -m 'feat(clients): withdraw allow delete now that the callable owns it'
```

---

## Task 13: Controller archive action

**Files:**
- Modify: `lib/features/clients/application/client_form_controller.dart`
- Test: `test/features/clients/application/client_form_controller_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
test('archiveClient returns ClientArchived and bumps the refresh', () async {
  when(() => repo.setClientArchived(any(), archived: any(named: 'archived')))
      .thenAnswer((_) async {});

  final outcome = await controller.setArchived('c1', archived: true);

  expect(outcome, isA<ClientArchived>());
  verify(() => repo.setClientArchived('c1', archived: true)).called(1);
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/features/clients/application/client_form_controller_test.dart`
Expected: FAIL — `setArchived` undefined.

- [ ] **Step 3: Add the outcome family and the method**

Beside `ClientDeleteOutcome`:

```dart
/// Outcome of an archive / un-archive.
sealed class ClientArchiveOutcome {
  const ClientArchiveOutcome();
}

class ClientArchived extends ClientArchiveOutcome {
  const ClientArchived({required this.archived});
  final bool archived;
}

class ClientArchiveFailed extends ClientArchiveOutcome {
  const ClientArchiveFailed(this.error);
  final Object error;
}

/// A write the reentrancy guard skipped. Surfaces NOTHING — see
/// ClientSaveBusy for why this is a member and not a fabricated exception.
class ClientArchiveBusy extends ClientArchiveOutcome {
  const ClientArchiveBusy();
}
```

In the controller:

```dart
  /// Archives or un-archives a client. Archived clients leave the paginated
  /// list but stay searchable and bookable.
  Future<ClientArchiveOutcome> setArchived(
    String clientId, {
    required bool archived,
  }) async {
    if (state) return const ClientArchiveBusy();
    final repo = ref.read(clientsRepositoryProvider);
    final refresh = ref.read(clientsRefreshProvider.notifier);
    final logger = ref.read(loggerProvider);
    state = true;
    try {
      await repo.setClientArchived(clientId, archived: archived);
      refresh.bump();
      return ClientArchived(archived: archived);
    } catch (e, st) {
      logger.warn('CLI-ARCH setArchived failed', e, st);
      return ClientArchiveFailed(e);
    } finally {
      if (ref.mounted) state = false;
    }
  }
```

Also delete the `#pre-ship` TODO comments on `ClientDeleteOutcome` and `deleteClient`, and update the class doc comment on `ClientFormController` — it currently says shipping clients are never deleted, which is no longer true.

- [ ] **Step 4: Run**

Run: `flutter test test/features/clients/application/client_form_controller_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/features/clients/application/client_form_controller.dart test/features/clients/application/client_form_controller_test.dart
git commit -m 'feat(clients): add archive action to the client controller'
```

---

## Task 14: `ClientsFilter` sealed family + Archived chip

**Files:**
- Create: `lib/features/clients/domain/models/clients_filter.dart`
- Modify: `lib/features/clients/widgets/sections/client_type_filter_bar.dart`
- Modify: `lib/features/clients/screens/clients_screen.dart` (filter state)
- Test: `test/features/clients/domain/clients_filter_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
void main() {
  test('type and archived are mutually exclusive states', () {
    const a = ClientsFilterArchived();
    const t = ClientsFilterType(ClientType.commercial);
    expect(a, isNot(equals(t)));
    expect(const ClientsFilterAll(), isNot(equals(a)));
  });

  test('selecting the active chip clears to All', () {
    expect(
      toggledFilter(const ClientsFilterArchived(), const ClientsFilterArchived()),
      isA<ClientsFilterAll>(),
    );
    expect(
      toggledFilter(const ClientsFilterAll(), const ClientsFilterArchived()),
      isA<ClientsFilterArchived>(),
    );
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/features/clients/domain/clients_filter_test.dart`
Expected: FAIL — undefined.

- [ ] **Step 3: Write the family**

```dart
import 'package:scheduling/features/clients/domain/models/client_type.dart';

/// Which slice of the client roster the list is showing.
///
/// Sealed so "archived AND commercial" is unexpressible rather than merely
/// unhandled — the chips are mutually exclusive by design.
sealed class ClientsFilter {
  const ClientsFilter();
}

class ClientsFilterAll extends ClientsFilter {
  const ClientsFilterAll();
}

class ClientsFilterType extends ClientsFilter {
  const ClientsFilterType(this.type);
  final ClientType type;

  @override
  bool operator ==(Object other) =>
      other is ClientsFilterType && other.type == type;

  @override
  int get hashCode => type.hashCode;
}

class ClientsFilterArchived extends ClientsFilter {
  const ClientsFilterArchived();

  @override
  bool operator ==(Object other) => other is ClientsFilterArchived;

  @override
  int get hashCode => 0;
}

/// Tapping the already-selected chip clears back to [ClientsFilterAll],
/// mirroring the pre-existing ClientTypeFilterBar behaviour.
ClientsFilter toggledFilter(ClientsFilter current, ClientsFilter tapped) =>
    current == tapped ? const ClientsFilterAll() : tapped;
```

Add the matching `==`/`hashCode` pair to `ClientsFilterAll` too, so all three
compare by value and `toggledFilter` never depends on const canonicalization:

```dart
class ClientsFilterAll extends ClientsFilter {
  const ClientsFilterAll();

  @override
  bool operator ==(Object other) => other is ClientsFilterAll;

  @override
  int get hashCode => 1;
}
```

- [ ] **Step 4: Add the Archived chip**

In `client_type_filter_bar.dart`, change the API from `ClientType? selected` to `ClientsFilter selected` / `ValueChanged<ClientsFilter> onChanged`, render the existing `ClientType.pickable` chips as `ClientsFilterType(...)`, and append:

```dart
              FilterChip(
                label: Text(l10n.clients_filterArchived),
                selected: selected is ClientsFilterArchived,
                onSelected: (_) => onChanged(
                  toggledFilter(selected, const ClientsFilterArchived()),
                ),
              ),
```

Add to both ARBs:

```json
  "clients_filterArchived": "Archived",
  "@clients_filterArchived": {
    "description": "Filter chip above the clients list showing only archived clients."
  },
```

FR: `"clients_filterArchived": "Archivés",`

- [ ] **Step 5: Wire the archived branch into the list**

`ClientsListView` already branches: `widget.selectedType` non-null routes to
`clientsByTypeProvider(type)` (around line 273) instead of the paginated list.
The Archived filter needs the **same shape**, or the chip renders and changes
nothing.

Add a provider beside `clientsByTypeProvider` in
`lib/features/clients/application/clients_providers.dart`:

```dart
/// Archived clients, read from the same bounded cached window as search and
/// the type filter — so the chip costs no extra read inside the TTL.
final archivedClientsProvider = FutureProvider.autoDispose<List<ClientRecord>>((
  ref,
) async {
  ref.watch(clientsRefreshProvider);
  return ref.read(clientsRepositoryProvider).fetchArchivedClients();
});
```

Change `ClientsListView`'s parameter from `ClientType? selectedType` to
`ClientsFilter filter`, and make the body switch on it:

```dart
    switch (widget.filter) {
      case ClientsFilterArchived():
        return _buildFromAsync(ref.watch(archivedClientsProvider),
            onRetry: () => ref.invalidate(archivedClientsProvider));
      case ClientsFilterType(:final type):
        return _buildFromAsync(ref.watch(clientsByTypeProvider(type)),
            onRetry: () => ref.invalidate(clientsByTypeProvider(type)));
      case ClientsFilterAll():
        break; // falls through to the paginated list below
    }
```

Extract the existing type-branch rendering into `_buildFromAsync` so both
branches share it rather than duplicating the loading/error/empty handling.

- [ ] **Step 6: Run**

Run: `flutter test test/features/clients/domain/clients_filter_test.dart`
Run: `flutter analyze`
Expected: tests PASS; `No issues found!` once `clients_screen.dart` holds
`ClientsFilter` state and passes it down.

- [ ] **Step 7: Commit**

```bash
git add lib/features/clients/domain/models/clients_filter.dart lib/features/clients/application/clients_providers.dart lib/features/clients/widgets/sections/client_type_filter_bar.dart lib/features/clients/widgets/views/clients_list_view.dart lib/features/clients/screens/clients_screen.dart lib/l10n/app_en.arb lib/l10n/app_fr.arb test/features/clients/domain/clients_filter_test.dart
git commit -m 'feat(clients): add Archived filter chip on a sealed filter family'
```

---

## Task 15: Archived badge on the tile

**Files:**
- Modify: `lib/features/clients/widgets/cards/client_tile.dart`
- Test: `test/features/clients/widgets/cards/client_tile_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
testWidgets('an archived client shows the Archived pill', (tester) async {
  await tester.pumpWidget(_host(ClientTile(
    client: ClientRecord.fromMap('c1', {'name': 'Acme', 'archived': true}),
  )));
  expect(find.text('Archived'), findsOneWidget);
});

testWidgets('an active client shows no Archived pill', (tester) async {
  await tester.pumpWidget(_host(ClientTile(
    client: ClientRecord.fromMap('c1', {'name': 'Acme'}),
  )));
  expect(find.text('Archived'), findsNothing);
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/features/clients/widgets/cards/client_tile_test.dart`
Expected: FAIL — no pill.

- [ ] **Step 3: Render the pill**

`StatusPill` is already imported. In the trailing/subtitle slot, before the type pill:

```dart
    if (client.archived)
      StatusPill(label: context.l10n.clients_filterArchived),
```

Reuse `clients_filterArchived` — the chip and the badge say the same word, and two keys would let them drift.

- [ ] **Step 4: Run**

Run: `flutter test test/features/clients/widgets/cards/client_tile_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/features/clients/widgets/cards/client_tile.dart test/features/clients/widgets/cards/client_tile_test.dart
git commit -m 'feat(clients): badge archived clients in search results'
```

---

## Task 16: Swipe actions

**Files:**
- Modify: `pubspec.yaml`
- Modify: `lib/features/clients/widgets/views/clients_list_view.dart`
- Test: `test/features/clients/widgets/clients_list_swipe_test.dart`

- [ ] **Step 1: Add the dependency**

In `pubspec.yaml` under `dependencies:`:

```yaml
  flutter_slidable: ^4.0.0
```

Run: `flutter pub get`

If this fails with a plugin-symlink error, re-run with the sandbox disabled — see the `flutter_contacts 2.x` memory note.

- [ ] **Step 2: Write the failing tests**

```dart
testWidgets('swipe offers Archive for a client with history', (tester) async {
  await tester.pumpWidget(_listHosting(clientWithJobs(12)));
  await tester.drag(find.byType(ClientTile).first, const Offset(-300, 0));
  await tester.pumpAndSettle();

  expect(find.text('Archive'), findsOneWidget);
  expect(find.text('Delete'), findsNothing);
  expect(tester.takeException(), isNull);
});

testWidgets('swipe offers Delete only when there are no jobs', (tester) async {
  await tester.pumpWidget(_listHosting(clientWithJobs(0)));
  await tester.drag(find.byType(ClientTile).first, const Offset(-300, 0));
  await tester.pumpAndSettle();

  expect(find.text('Archive'), findsOneWidget);
  expect(find.text('Delete'), findsOneWidget);
  expect(tester.takeException(), isNull);
});
```

- [ ] **Step 3: Run to verify it fails**

Run: `flutter test test/features/clients/widgets/clients_list_swipe_test.dart`
Expected: FAIL — no actions rendered.

- [ ] **Step 4: Wrap the tile**

In the list's item builder — **here, not inside `ClientTile`**, which the booking-flow client picker reuses and must not gain destructive actions:

```dart
  Widget _row(ClientRecord client) {
    final l10n = context.l10n;
    return Slidable(
      key: ValueKey(client.id),
      endActionPane: ActionPane(
        motion: const DrawerMotion(),
        extentRatio: canDeleteClient(client) ? 0.5 : 0.28,
        // Full swipe commits Archive ONLY. Delete is never gesture-committed
        // — it needs a deliberate tap plus a confirm.
        dismissible: DismissiblePane(onDismissed: () => _archive(client)),
        children: [
          if (canDeleteClient(client))
            SlidableAction(
              onPressed: (_) => _confirmDelete(client),
              backgroundColor: Theme.of(context).palette.dangerFill,
              foregroundColor: Colors.white,
              icon: Icons.delete_outline,
              label: l10n.common_delete,
            ),
          SlidableAction(
            onPressed: (_) => _archive(client),
            backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
            foregroundColor:
                Theme.of(context).colorScheme.onSecondaryContainer,
            icon: Icons.archive_outlined,
            label: l10n.clients_archive,
          ),
        ],
      ),
      child: ClientTile(client: client, onOpen: () => _openClient(client)),
    );
  }
```

The action handlers:

```dart
  Future<void> _archive(ClientRecord client) async {
    if (guardedOffline(ref, context, tag: 'CLI-ARCH')) return;
    final controller = ref.read(clientFormControllerProvider.notifier);
    final outcome = await controller.setArchived(
      client.id,
      archived: !client.archived,
    );
    if (!mounted) return;
    switch (outcome) {
      case ClientArchiveBusy():
        return;
      case ClientArchived(:final archived):
        ref.read(noticeServiceProvider).success(
          archived
              ? context.l10n.clients_archivedNotice(client.displayName)
              : context.l10n.clients_unarchivedNotice(client.displayName),
        );
        _pagingController.refresh();
      case ClientArchiveFailed(:final error):
        composeErrorNotice(
          context,
          intro: context.l10n.error_introArchiveClient,
          tag: 'CLI-ARCH',
          error: error,
        );
    }
  }

  Future<void> _confirmDelete(ClientRecord client) async {
    final ok = await showConfirmDialog(
      context,
      title: context.l10n.clients_deleteTitle,
      message: context.l10n.clients_deleteMessage(client.displayName),
      destructive: true,
    );
    if (ok != true || !mounted) return;
    if (guardedOffline(ref, context, tag: 'CLI-DEL')) return;

    final outcome = await ref
        .read(clientFormControllerProvider.notifier)
        .deleteClient(client.id);
    if (!mounted) return;
    switch (outcome) {
      case ClientDeleted():
        ref.read(noticeServiceProvider)
            .success(context.l10n.clients_deletedNotice(client.displayName));
        _pagingController.refresh();
      case ClientDeleteFailed(:final error):
        if (error is ClientsFailure) {
          ref.read(noticeServiceProvider)
              .error(error.toLocalizedMessage(context));
          return;
        }
        composeErrorNotice(
          context,
          intro: context.l10n.error_introDeleteClient,
          tag: 'CLI-DEL',
          error: error,
        );
    }
  }
```

- [ ] **Step 5: Add the ARB keys**

EN (with `@` blocks describing each, and `{name}` typed as `String` on the three placeholder keys):

```json
  "clients_archive": "Archive",
  "clients_unarchive": "Unarchive",
  "clients_archivedNotice": "Archived {name}",
  "clients_unarchivedNotice": "Restored {name}",
  "clients_deletedNotice": "Deleted {name}",
  "clients_deleteTitle": "Delete client?",
  "clients_deleteMessage": "{name} will be removed permanently. This can't be undone.",
  "error_introArchiveClient": "Couldn't archive the client",
  "error_introDeleteClient": "Couldn't delete the client",
```

Mirror all nine in FR. Note the intros are **capitalized with no trailing punctuation** — they are sentence-initial in `error_noticeWithCause`.

- [ ] **Step 6: Run**

Run: `flutter test test/features/clients/widgets/clients_list_swipe_test.dart`
Expected: PASS, exceptions null.

- [ ] **Step 7: Commit**

```bash
git add pubspec.yaml pubspec.lock lib/features/clients/widgets/views/clients_list_view.dart lib/l10n/app_en.arb lib/l10n/app_fr.arb test/features/clients/widgets/clients_list_swipe_test.dart
git commit -m 'feat(clients): swipe to archive or delete a client row'
```

---

## Task 17: Detail view archive + gated delete

**Files:**
- Modify: `lib/features/clients/widgets/views/client_detail_view.dart:42-125`

- [ ] **Step 1: Extract the shared handlers**

Task 16's `_archive` and `_confirmDelete` must not be copied here — two
surfaces silently disagreeing on notice text or log tag is the exact drift the
codebase keeps calling out. Move both into a mixin beside the list view:

Create `lib/features/clients/widgets/views/client_actions_host.dart`:

```dart
/// Archive / delete handlers shared by the clients list and the client
/// detail. Both surfaces must agree on the notices, the CLI-ARCH/CLI-DEL log
/// tags and the confirm copy, so the flow lives here once.
mixin ClientActionsHost<T extends ConsumerStatefulWidget>
    on ConsumerState<T> {
  /// Called after a successful archive or delete so the host can refresh.
  void onClientMutated();

  Future<void> archiveClient(ClientRecord client) async { /* Task 16 body */ }

  Future<void> confirmDeleteClient(ClientRecord client) async { /* Task 16 body */ }
}
```

Move the two method bodies from Task 16 verbatim, replacing
`_pagingController.refresh()` with `onClientMutated()`. `ClientsListView`
implements it as `_pagingController.refresh()`; the detail view implements it
as its existing close-and-refresh.

- [ ] **Step 2: Replace the debug-gated delete**

Remove the `kShowTestingDeleteClient` import, the
`if (kShowTestingDeleteClient) ...[` guard and all three `#pre-ship` TODOs.
Mix in `ClientActionsHost` and render in the footer:

```dart
        OutlinedButton.icon(
          onPressed: () => archiveClient(_client),
          icon: Icon(
            _client.archived
                ? Icons.unarchive_outlined
                : Icons.archive_outlined,
          ),
          label: Text(
            _client.archived
                ? context.l10n.clients_unarchive
                : context.l10n.clients_archive,
          ),
        ),
        if (canDeleteClient(_client)) ...[
          const SizedBox(height: AppSpacing.sp8),
          OutlinedButton.icon(
            onPressed: () => confirmDeleteClient(_client),
            style: destructiveOutlinedButtonStyle(context),
            icon: const Icon(Icons.delete_outline),
            label: Text(context.l10n.common_delete),
          ),
        ],
```

- [ ] **Step 2: Verify no debug flag remains**

Run: `grep -rn "kShowTestingDeleteClient" lib/`
Expected: only `lib/core/testing_flags.dart` (removed in Task 18).

- [ ] **Step 3: Run the clients suite**

Run: `flutter test test/features/clients/`
Expected: all pass.

- [ ] **Step 4: Commit**

```bash
git add lib/features/clients/widgets/views/client_detail_view.dart
git commit -m 'feat(clients): archive and gated delete on the client detail'
```

---

## Task 18: Retire the testing flag

**Files:**
- Delete: `lib/core/testing_flags.dart`

- [ ] **Step 1: Confirm nothing references it**

Run: `grep -rn "testing_flags\|kShowTestingDeleteClient" lib/ test/`
Expected: no hits outside the file itself.

- [ ] **Step 2: Delete it**

```bash
git rm lib/core/testing_flags.dart
```

- [ ] **Step 3: Confirm no `#pre-ship` markers survive in clients**

Run: `grep -rn "#pre-ship" lib/ functions/ docs/`
Expected: no hits in `lib/features/clients/`. Hits elsewhere (if any) are out of scope.

- [ ] **Step 4: Analyze**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 5: Commit**

```bash
git commit -am 'chore: retire the testing-only client delete flag'
```

---

## Task 19: Docs + full verification

**Files:**
- Modify: `CLAUDE.md`
- Modify: `docs/DEPLOYMENT.md`
- Modify: `docs/CLOUD_FUNCTIONS.md`
- Test: `test/features/clients/clients_scale_sweep_test.dart`

- [ ] **Step 1: Add the swipe row to the scale sweep**

Extend `clients_scale_sweep_test.dart` to open the swipe pane at 260×640 / textScaler 2.0 and assert `tester.takeException()` is null.

Run: `flutter test test/features/clients/clients_scale_sweep_test.dart`
Expected: PASS

- [ ] **Step 2: Rewrite the `CLAUDE.md` invariant**

Replace the "A client is never removed — no delete, no archive" bullet. The replacement must state: archive hides a client from the paginated list but keeps it searchable and bookable; **`archived` must be on every client doc** because Firestore excludes docs missing a filtered field, and the two create paths are `_normalizedMap` and Wave `importCustomers`; delete is admin-only via the `deleteClient` callable, refused when a live `count()` finds appointments; `allow delete` on `/clients` is withdrawn; `canDeleteClient` is advisory UI only.

- [ ] **Step 3: Add the deploy-log row**

In `docs/DEPLOYMENT.md`, append a pending row recording: adds `deleteClient` (26 functions), withdraws `allow delete` on `/clients`, adds the `(archived, name, __name__)` index — **so `firestore:indexes` IS required** — and that the backfill must run first.

- [ ] **Step 4: Document the callable**

Add `deleteClient` to `docs/CLOUD_FUNCTIONS.md` and to the module map in `functions/CLAUDE.md`.

- [ ] **Step 5: Full verification**

```bash
flutter analyze
flutter test
cd functions && npm run lint && npx jest
```

Expected: `No issues found!`; all Flutter tests pass; lint silent; all jest suites pass.

- [ ] **Step 6: Commit**

```bash
git add CLAUDE.md docs/DEPLOYMENT.md docs/CLOUD_FUNCTIONS.md functions/CLAUDE.md test/features/clients/clients_scale_sweep_test.dart
git commit -m 'docs(clients): record the archive and delete invariants'
```

---

## Deploy (after all tasks)

Per `docs/DEPLOYMENT.md` and §6 of the spec — **three ordered steps, do not collapse:**

1. `node functions/scripts/backfill-clients-archived.js` against prod (dry-run first).
2. `cd functions && npm run lint && firebase deploy --only functions,firestore:rules,firestore:indexes` — indexes **required**; never `--force`.
3. Wait for the index to finish building, verify `functions:list` shows 26, then cut the app build.

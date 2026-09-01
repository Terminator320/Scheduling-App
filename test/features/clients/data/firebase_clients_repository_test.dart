// Mocktail fakes must subclass cloud_firestore's sealed query/snapshot types.
// ignore_for_file: subtype_of_sealed_class

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/features/clients/data/firebase_clients_repository.dart';
import 'package:scheduling/features/clients/domain/clients_failure.dart';
import 'package:scheduling/features/clients/domain/models/client_record.dart';
import 'package:scheduling/features/clients/domain/models/client_type.dart';

class _RecordingLogger extends AppLogger {
  final warnings = <String>[];

  @override
  void warn(String message, [Object? error, StackTrace? stack]) {
    warnings.add(message);
  }
}

/// A plain fake rather than a `Mock`: the cap test builds a thousand of them,
/// and only `id` and `data()` are ever read.
class _FakeDoc extends Fake
    implements QueryDocumentSnapshot<Map<String, dynamic>> {
  _FakeDoc(this.id, this._data);

  @override
  final String id;

  final Map<String, dynamic> _data;

  @override
  Map<String, dynamic> data() => _data;
}

class _MockFirestore extends Mock implements FirebaseFirestore {}

class _MockCollection extends Mock
    implements CollectionReference<Map<String, dynamic>> {}

class _MockQuery extends Mock implements Query<Map<String, dynamic>> {}

class _MockQuerySnapshot extends Mock
    implements QuerySnapshot<Map<String, dynamic>> {}

class _MockQueryDocSnap extends Mock
    implements QueryDocumentSnapshot<Map<String, dynamic>> {}

class _MockDocRef extends Mock
    implements DocumentReference<Map<String, dynamic>> {}

class _FakeFieldValue extends Fake implements FieldValue {}

class _MockFunctions extends Mock implements FirebaseFunctions {}

class _MockCallable extends Mock implements HttpsCallable {}

class _MockCallableResult extends Mock implements HttpsCallableResult<void> {}

void main() {
  late _MockFirestore firestore;
  late _RecordingLogger logger;
  late _MockCollection collection;
  late _MockQuery query;
  late _MockQuerySnapshot snapshot;
  late _MockDocRef docRef;
  late _MockFunctions functions;
  late _MockCallable callable;

  setUpAll(() {
    registerFallbackValue(_FakeFieldValue());
    registerFallbackValue(<String, dynamic>{});
    registerFallbackValue(<Object?>[]);
  });

  _MockQueryDocSnap doc(String id, Map<String, dynamic> data) {
    final d = _MockQueryDocSnap();
    when(() => d.id).thenReturn(id);
    when(d.data).thenReturn(data);
    return d;
  }

  setUp(() {
    firestore = _MockFirestore();
    logger = _RecordingLogger();
    collection = _MockCollection();
    query = _MockQuery();
    snapshot = _MockQuerySnapshot();
    docRef = _MockDocRef();

    when(() => firestore.collection('clients')).thenReturn(collection);
    when(
      () => collection.where(any(), isEqualTo: any(named: 'isEqualTo')),
    ).thenReturn(query);
    when(
      () => collection.orderBy(any(), descending: any(named: 'descending')),
    ).thenReturn(query);
    when(
      () => query.orderBy(any(), descending: any(named: 'descending')),
    ).thenReturn(query);
    when(() => query.startAfter(any())).thenReturn(query);
    when(() => query.limit(any())).thenReturn(query);
    when(() => query.get()).thenAnswer((_) async => snapshot);
    when(() => snapshot.docs).thenReturn(const []);

    when(() => collection.doc(any())).thenReturn(docRef);
    when(() => docRef.id).thenReturn('new-id');
    when(() => docRef.update(any())).thenAnswer((_) async {});
    when(() => docRef.delete()).thenAnswer((_) async {});
    when(() => collection.add(any())).thenAnswer((_) async => docRef);

    functions = _MockFunctions();
    callable = _MockCallable();
    when(() => functions.httpsCallable(any())).thenReturn(callable);
    when(
      () => callable.call<void>(any<Object?>()),
    ).thenAnswer((_) async => _MockCallableResult());
  });

  FirebaseClientsRepository repo({DateTime Function()? clock}) =>
      FirebaseClientsRepository(
        firestore,
        functions: functions,
        clock: clock,
        logger: logger,
      );

  ClientRecord client({String id = 'c1', String name = 'Test Client'}) =>
      ClientRecord(
        id: id,
        name: name,
        phone: '555-0000',
        email: 'test@example.com',
        address: '1 Main St',
        city: 'Montreal',
        province: 'QC',
        country: 'Canada',
        postalCode: 'H1H 1H1',
      );

  group('addClient', () {
    test('writes normalized email with createdAt and updatedAt', () async {
      await repo().addClient(client());

      final captured =
          (verify(() => collection.add(captureAny())).captured.single as Map)
              .cast<String, dynamic>();
      expect(captured['email'], 'test@example.com');
      expect(captured.containsKey('createdAt'), isTrue);
      expect(captured.containsKey('updatedAt'), isTrue);
    });

    test('normalizes EVERY contact email, not just the top-level one', () async {
      // The loop was unhit: only the top-level address was ever asserted, so a
      // regression that normalized the client and skipped its contacts would
      // ship green. Contact emails feed the same `matchesClient` search
      // matching as the main one, where a stray space or capital means the
      // person is simply not found.
      await repo().addClient(
        client().copyWith(
          email: '  Owner@Example.COM ',
          contacts: const [
            ClientContact(name: 'Site', email: ' Site@Example.COM'),
            ClientContact(name: 'Billing', email: 'BILLING@example.com  '),
          ],
        ),
      );

      final captured =
          (verify(() => collection.add(captureAny())).captured.single as Map)
              .cast<String, dynamic>();
      expect(captured['email'], 'owner@example.com');
      final contacts = (captured['contacts'] as List)
          .map((c) => (c as Map)['email'])
          .toList();
      expect(contacts, ['site@example.com', 'billing@example.com']);
    });

    test('a contact with no email normalizes to empty, not null', () async {
      // `normalizeEmail` is fed `?? ''`, so the key must survive as a string —
      // a null here would break the Dart-side matcher that reads it.
      await repo().addClient(
        client().copyWith(
          contacts: const [ClientContact(name: 'Site')],
        ),
      );

      final captured =
          (verify(() => collection.add(captureAny())).captured.single as Map)
              .cast<String, dynamic>();
      expect(((captured['contacts'] as List).single as Map)['email'], '');
    });

    test('returns the client with the generated doc id', () async {
      // The input has an empty id (new client); the returned record carries the
      // Firestore-generated id so callers can link to it immediately.
      final saved = await repo().addClient(client(id: ''));

      expect(saved.id, 'new-id');
    });
  });

  group('updateClient', () {
    test('writes normalized email with updatedAt', () async {
      await repo().updateClient(client());

      final raw = verify(() => docRef.update(captureAny())).captured.single;
      final captured = (raw as Map).cast<String, dynamic>();
      expect(captured['email'], 'test@example.com');
      expect(captured.containsKey('updatedAt'), isTrue);
    });
  });

  group('fetchClientsPage', () {
    test('first page orders by name + doc id without a cursor', () async {
      await repo().fetchClientsPage(limit: 50);

      verify(() => query.orderBy('name')).called(1);
      verify(() => query.orderBy(FieldPath.documentId)).called(1);
      verify(() => query.limit(50)).called(1);
      verifyNever(() => query.startAfter(any()));
      // Field-value cursor pagination must never refetch a boundary doc.
      verifyNever(() => collection.doc(any()));
    });

    test('filters archived out on the server, before ordering', () async {
      await repo().fetchClientsPage(limit: 50);

      // Server-side, deliberately: filtering a server page in Dart would
      // shorten a page the server actually filled, and the list's
      // `pages.last.length < pageSize` end-of-list test would truncate.
      verify(() => collection.where('archived', isEqualTo: false)).called(1);
    });

    test(
      'next page uses a field-value cursor (no boundary-doc re-read)',
      () async {
        final r = repo();
        // Build doc mocks before stubbing `docs` — mocktail forbids calling
        // `when` (inside the doc() helper) while another stub is being defined.
        final docs = [
          doc('c1', {'name': 'Test Client'}),
        ];
        when(() => snapshot.docs).thenReturn(docs);
        final page1 = await r.fetchClientsPage(limit: 1);

        await r.fetchClientsPage(limit: 1, after: page1.last);

        final captured = verify(
          () => query.startAfter(captureAny()),
        ).captured.single;
        expect(captured, ['Test Client', 'c1']);
        verifyNever(() => collection.doc(any()));
      },
    );

    test(
      'legacy business-only boundary doc: cursor uses the stored (empty) '
      'name, not the businessName display fallback',
      () async {
        final r = repo();
        final docs = [
          doc('c9', {'name': '', 'businessName': 'Zebra Corp'}),
        ];
        when(() => snapshot.docs).thenReturn(docs);
        final page1 = await r.fetchClientsPage(limit: 1);
        // The record's display name falls back to the business name…
        expect(page1.last.name, 'Zebra Corp');

        await r.fetchClientsPage(limit: 1, after: page1.last);

        // …but the cursor must match the stored orderBy value or Firestore
        // would skip every doc sorted between '' and 'Zebra Corp'.
        final captured = verify(
          () => query.startAfter(captureAny()),
        ).captured.single;
        expect(captured, ['', 'c9']);
      },
    );
  });

  group('the client scan window warns at its cap', () {
    // This is the quietest truncation in the app. The window is ordered by
    // `name`, so at the cap it is the alphabetically FIRST 1000 clients —
    // everything past that point goes invisible to search, to the type-filter
    // chips and to the Archived chip at once, gradually, as the roster grows,
    // with no error anywhere. The warn is the entire mitigation.
    void withClients(int count) => when(() => snapshot.docs).thenReturn([
      for (var i = 0; i < count; i++)
        _FakeDoc('c$i', {'name': 'Client ${i.toString().padLeft(4, '0')}'}),
    ]);

    test('a full first page is followed by the next page', () async {
      final firstPage = [
        for (var i = 0; i < 500; i++)
          _FakeDoc('c$i', {'name': 'Client ${i.toString().padLeft(4, '0')}'}),
      ];
      // Named so it, and only it, matches the query - a doc that landed on the
      // second page has to be findable, and ranking would bury a 'Client 0500'
      // below the alphabetically-earlier first page.
      final secondPage = [
        _FakeDoc('c500', {'name': 'Zephyr Holdings'}),
      ];
      final secondSnapshot = _MockQuerySnapshot();
      when(() => snapshot.docs).thenReturn(firstPage);
      when(() => secondSnapshot.docs).thenReturn(secondPage);
      var call = 0;
      when(() => query.get()).thenAnswer((_) async {
        call++;
        return call == 1 ? snapshot : secondSnapshot;
      });

      final results = await repo().searchClients('zephyr');

      expect(results.map((c) => c.id), contains('c500'));
      verify(() => query.startAfter(['Client 0499', 'c499'])).called(1);
    });

    test('a short window stays on one page', () async {
      withClients(499);

      await repo().searchClients('client');

      verifyNever(() => query.startAfter(any()));
    });

    test('the window stops at its ceiling and warns', () async {
      withClients(500);

      await repo().searchClients('client');

      // 5000 / 500 per page, PLUS one 1-document probe past the cap — the
      // only way to tell a roster of exactly 5000 (nothing hidden) from a
      // larger one, and paid only in the cap case. It must stop there rather
      // than walk the collection.
      verify(() => query.get()).called(11);
      expect(logger.warnings, hasLength(1));
      expect(logger.warnings.single, startsWith('CLI-SEARCH'));
      expect(logger.warnings.single, contains('5000'));
    });
  });

  group('searchClients', () {
    test(
      'returns empty list without querying Firestore for a blank or '
      'punctuation-only query (search starts at the first searchable char)',
      () async {
        expect(await repo().searchClients('   '), isEmpty);
        expect(await repo().searchClients('@'), isEmpty);

        verifyNever(() => query.get());
      },
    );

    test('searches Firestore from the first character', () async {
      final results = await repo().searchClients('a');

      expect(results, isEmpty);
      verify(() => query.get()).called(1);
    });

    test('returns cached result on second call with same query', () async {
      final r = repo();
      await r.searchClients('John Smith');
      await r.searchClients('John Smith');

      // Firestore read should only fire once — second call uses cache.
      verify(() => query.get()).called(1);
    });

    test('distinct queries share one scan-window read while fresh', () async {
      final docs = [
        doc('c1', {'name': 'John Smith'}),
        doc('c2', {'name': 'Jane Doe'}),
      ];
      when(() => snapshot.docs).thenReturn(docs);

      final r = repo();
      expect((await r.searchClients('John')).map((c) => c.id), ['c1']);
      expect((await r.searchClients('Jane')).map((c) => c.id), ['c2']);

      // One window read serves both queries.
      verify(() => query.get()).called(1);
    });

    test('scan window expires after the TTL and is re-read', () async {
      var now = DateTime(2026, 7, 2, 12);
      final r = repo(clock: () => now);

      await r.searchClients('John');
      now = now.add(const Duration(minutes: 3));
      await r.searchClients('John');

      verify(() => query.get()).called(2);
    });

    test(
      'updating a client is reflected in search without re-reading the window',
      () async {
        final docs = [
          doc('c1', {'name': 'John Smith'}),
        ];
        when(() => snapshot.docs).thenReturn(docs);

        final r = repo();
        expect((await r.searchClients('John')).map((c) => c.id), ['c1']);

        await r.updateClient(client(name: 'Renamed Person'));

        expect(await r.searchClients('John'), isEmpty);
        expect((await r.searchClients('Renamed')).map((c) => c.id), ['c1']);
        verify(() => query.get()).called(1);
      },
    );

    test(
      'adding a client makes it searchable without re-reading the window',
      () async {
        final docs = [
          doc('c1', {'name': 'John Smith'}),
        ];
        when(() => snapshot.docs).thenReturn(docs);
        when(() => docRef.id).thenReturn('c2');

        final r = repo();
        expect(await r.searchClients('Zebra'), isEmpty);

        await r.addClient(client(id: 'c2', name: 'Zebra Corp'));

        expect((await r.searchClients('Zebra')).map((c) => c.id), ['c2']);
        verify(() => query.get()).called(1);
      },
    );

    // I7: `_patchWindow` MERGES the write over the cached doc rather than
    // substituting it, because `toMap()` emits user-owned fields only. Nothing
    // asserted that, so a "simplification" back to a plain replace would blank
    // every function-owned field on every search and type-filter result until
    // the TTL expired — with no test failing.
    test(
      'a local write KEEPS the function-owned fields on the cached doc',
      () async {
        // Built before the stub: `doc()` stubs internally, and mocktail
        // refuses a `when` inside a stub response.
        final docs = [
          doc('c1', {
            'name': 'John Smith',
            // Function-owned: written by recountClientJobs and the server, and
            // deliberately absent from ClientRecord.toMap().
            'jobCount': 7,
            'waveCustomerId': 'wave-123',
          }),
        ];
        when(() => snapshot.docs).thenReturn(docs);

        final r = repo();
        expect((await r.searchClients('John')).single.jobCount, 7);

        await r.updateClient(client(name: 'John Smith Jr'));

        final patched = (await r.searchClients('John')).single;
        expect(patched.name, 'John Smith Jr');
        expect(
          patched.jobCount,
          7,
          reason: 'jobCount was dropped by the patch',
        );
        expect(patched.waveCustomerId, 'wave-123');
        verify(() => query.get()).called(1);
      },
    );

    test('ranks exact/prefix matches first, then alphabetical', () async {
      final docs = [
        doc('c1', {'name': 'Aaron Johnson', 'phone': '514-555-0101'}),
        doc('c2', {'name': 'John Smith', 'phone': '514-555-0102'}),
        doc('c3', {'name': 'Johnny Cash', 'phone': '514-555-0103'}),
      ];
      when(() => snapshot.docs).thenReturn(docs);

      final results = await repo().searchClients('John');

      // Prefix matches (John Smith, Johnny Cash) rank above the substring
      // match (Aaron Johnson); ties break alphabetically.
      expect(results.map((c) => c.id), ['c2', 'c3', 'c1']);
    });
  });

  group('building filtering', () {
    List<QueryDocumentSnapshot<Map<String, dynamic>>> paton() => [
      doc('c1', {
        'name': 'Zeta',
        'address': '914-4450 Prom. Paton',
        'city': 'Laval',
        'province': 'QC',
        'postalCode': 'H7W 5J7',
        'country': 'Canada',
      }),
      doc('c2', {
        'name': 'Alpha',
        // Legacy shape — the locality is in `address` AND in its own fields,
        // which is exactly what makes it reduce to the same building.
        'address': '1207-4450 Prom. Paton, Laval, QC H7W 5J7, Canada',
        'city': 'Laval',
        'province': 'QC',
        'postalCode': 'H7W 5J7',
        'country': 'Canada',
      }),
      doc('c3', {
        'name': 'Elsewhere',
        'address': '7 Rue Seule',
        'city': 'Laval',
        'province': 'QC',
      }),
    ];

    test('fetchBuildings groups shared addresses only', () async {
      // Built before `when` — `doc()` stubs internally, and mocktail refuses a
      // `when` inside a stub response.
      final docs = paton();
      when(() => snapshot.docs).thenReturn(docs);

      final buildings = await repo().fetchBuildings();

      expect(buildings, hasLength(1));
      expect(buildings.single.street, '4450 Prom. Paton');
      expect(buildings.single.clientCount, 2);
    });

    test('fetchClientsByBuilding returns both shapes, name-sorted', () async {
      final docs = paton();
      when(() => snapshot.docs).thenReturn(docs);
      final key = (await repo().fetchBuildings()).single.key;

      final clients = await repo().fetchClientsByBuilding(key);

      expect(clients.map((c) => c.name), ['Alpha', 'Zeta']);
    });

    test('an archived client is not counted or listed', () async {
      // Same rule the type filter keeps: the Archived chip is where they live.
      final docs = [
        doc('c1', {
          'name': 'Live',
          'address': '914-4450 Prom. Paton',
          'city': 'Laval',
        }),
        doc('c2', {
          'name': 'Gone',
          'address': '1207-4450 Prom. Paton',
          'city': 'Laval',
          'archived': true,
        }),
      ];
      when(() => snapshot.docs).thenReturn(docs);

      // One live client at that address is not a building.
      expect(await repo().fetchBuildings(), isEmpty);
    });

    test('an empty key selects nothing', () async {
      final docs = paton();
      when(() => snapshot.docs).thenReturn(docs);
      expect(await repo().fetchClientsByBuilding(''), isEmpty);
    });

    test(
      'fetchBuildingKeys answers for every live client, null included',
      () async {
        // The row builder's half of the pill. An entry per client is what lets a
        // caller tell "no building" from "not in the scan window" — the archived
        // rows the list still renders fall in the second bucket and derive their
        // own key.
        final docs = [
          ...paton(),
          doc('c4', {'name': 'Nowhere'}),
        ];
        when(() => snapshot.docs).thenReturn(docs);
        final r = repo();

        final keys = await r.fetchBuildingKeys();

        expect(keys.keys, containsAll(['c1', 'c2', 'c3', 'c4']));
        expect(keys['c1'], keys['c2']); // two units of one building
        expect(keys['c3'], isNot(keys['c1']));
        expect(keys.containsKey('c4'), isTrue);
        expect(keys['c4'], isNull); // no address at all
      },
    );

    test('the keys agree with the buildings the menu offers', () async {
      // They come off one cached window and one derivation; a disagreement
      // between them would show a pill on a row the filter cannot select.
      final docs = paton();
      when(() => snapshot.docs).thenReturn(docs);
      final r = repo();

      final key = (await r.fetchBuildings()).single.key;
      final keys = await r.fetchBuildingKeys();

      expect(keys.values.where((k) => k == key), hasLength(2));
    });

    // `_patchWindow` carries the already-materialized records and building
    // keys across a local write and re-derives only the one client that
    // changed, rather than discarding the window's memos and rebuilding every
    // record and key on the UI isolate. These pin the four write shapes it
    // has to get right; the win is that they stay correct while the whole
    // window is no longer recomputed.
    group('a local write patches the derived maps in place', () {
      ClientRecord patonClient(String id, String name, String address) =>
          ClientRecord(
            id: id,
            name: name,
            address: address,
            city: 'Laval',
            province: 'QC',
            postalCode: 'H7W 5J7',
            country: 'Canada',
          );

      test(
        'an edit that moves a client INTO the building recounts it',
        () async {
          final docs = paton();
          when(() => snapshot.docs).thenReturn(docs);
          final r = repo();
          // Materialize the memos first — this is the state the patch reuses.
          expect((await r.fetchBuildings()).single.clientCount, 2);

          await r.updateClient(
            patonClient('c3', 'Elsewhere', '88-4450 Prom. Paton'),
          );

          final buildings = await r.fetchBuildings();
          expect(buildings.single.clientCount, 3);
          final keys = await r.fetchBuildingKeys();
          expect(keys['c3'], buildings.single.key);
          // The two clients that did not change keep their key.
          expect(keys['c1'], buildings.single.key);
          expect(keys['c2'], buildings.single.key);
        },
      );

      test(
        'an edit that moves a client OUT drops it from the key map',
        () async {
          final docs = paton();
          when(() => snapshot.docs).thenReturn(docs);
          final r = repo();
          final key = (await r.fetchBuildings()).single.key;

          // A street nothing else in the window shares, so moving c1 there can
          // only dissolve Paton rather than form a second building with c3.
          await r.updateClient(patonClient('c1', 'Zeta', '12 Rue Unique'));

          final keys = await r.fetchBuildingKeys();
          expect(keys['c1'], isNot(key));
          expect(keys['c2'], key);
          // One client left at Paton is below the 2-client minimum.
          expect(await r.fetchBuildings(), isEmpty);
        },
      );

      test('an untouched client is NOT rebuilt across a write', () async {
        // The point of the patch, asserted the only way it can be from
        // outside: a record the write did not touch comes back as the SAME
        // instance, which is only true if the window carried it across
        // instead of re-running `ClientRecord.fromMap` over the whole scan.
        final docs = paton();
        when(() => snapshot.docs).thenReturn(docs);
        final r = repo();
        final key = (await r.fetchBuildings()).single.key;
        final before = (await r.fetchClientsByBuilding(
          key,
        )).firstWhere((c) => c.id == 'c2');

        await r.updateClient(patonClient('c1', 'Zeta', '12 Rue Unique'));

        final after = (await r.fetchClientsByBuilding(
          key,
        )).firstWhere((c) => c.id == 'c2');
        expect(identical(before, after), isTrue);
      });

      test('archiving removes the client from the derived maps', () async {
        final docs = paton();
        when(() => snapshot.docs).thenReturn(docs);
        final r = repo();
        expect((await r.fetchBuildings()).single.clientCount, 2);

        await r.setClientArchived('c1', archived: true);

        // Archived clients are excluded from `records`, so the key map must
        // lose the entry rather than keep a stale one.
        expect(await r.fetchBuildingKeys(), isNot(contains('c1')));
        expect(await r.fetchBuildings(), isEmpty);
      });

      test('deleting removes the client from the derived maps', () async {
        final docs = paton();
        when(() => snapshot.docs).thenReturn(docs);
        final r = repo();
        expect((await r.fetchBuildings()).single.clientCount, 2);

        await r.deleteClient('c1');

        expect(await r.fetchBuildingKeys(), isNot(contains('c1')));
        expect(await r.fetchBuildings(), isEmpty);
      });
    });
  });

  group('type filtering', () {
    test('fetchClientsByType returns only that type, name-sorted', () async {
      final docs = [
        doc('c1', {'name': 'Zeta', 'type': 'commercial'}),
        doc('c2', {'name': 'Untyped'}),
        doc('c3', {'name': 'Alpha', 'type': 'commercial'}),
        doc('c4', {'name': 'Other', 'type': 'residential'}),
      ];
      when(() => snapshot.docs).thenReturn(docs);

      final typed = await repo().fetchClientsByType(ClientType.commercial);

      expect(typed.map((c) => c.name), ['Alpha', 'Zeta']);
    });

    test('a doc with no type is in no type filter', () async {
      final docs = [
        doc('c1', {'name': 'Legacy'}),
      ];
      when(() => snapshot.docs).thenReturn(docs);

      for (final type in ClientType.pickable) {
        expect(await repo().fetchClientsByType(type), isEmpty);
      }
    });

    test('an unknown stored type falls into no filter', () async {
      final docs = [
        doc('c1', {'name': 'Odd', 'type': 'industrial'}),
      ];
      when(() => snapshot.docs).thenReturn(docs);

      for (final type in ClientType.pickable) {
        expect(await repo().fetchClientsByType(type), isEmpty);
      }
    });

    test('filtering on unset reads nothing rather than everything', () async {
      final docs = [
        doc('c1', {'name': 'A', 'type': 'commercial'}),
        doc('c2', {'name': 'B'}),
      ];
      when(() => snapshot.docs).thenReturn(docs);

      expect(await repo().fetchClientsByType(ClientType.unset), isEmpty);
    });

    test('property mgmt maps from its stored raw value', () async {
      final docs = [
        doc('c1', {'name': 'Gestion', 'type': 'building'}),
      ];
      when(() => snapshot.docs).thenReturn(docs);

      final typed = await repo().fetchClientsByType(
        ClientType.building,
      );

      expect(typed.single.name, 'Gestion');
    });

    test('the type filter shares the search scan window (one read)', () async {
      final docs = [
        doc('c1', {'name': 'A', 'type': 'commercial'}),
      ];
      when(() => snapshot.docs).thenReturn(docs);

      final r = repo();
      await r.fetchClientsByType(ClientType.commercial);
      await r.fetchClientsByType(ClientType.residential);
      await r.searchClients('A');

      // The filter costs no extra Firestore read inside the cache TTL.
      verify(() => query.get()).called(1);
    });
  });

  group('archiving', () {
    test('setClientArchived writes the flag with updatedAt', () async {
      await repo().setClientArchived('c1', archived: true);

      verify(() => collection.doc('c1')).called(1);
      final captured =
          (verify(() => docRef.update(captureAny())).captured.single as Map)
              .cast<String, dynamic>();
      expect(captured['archived'], isTrue);
      expect(captured.containsKey('updatedAt'), isTrue);
    });

    test(
      'setClientArchived merges into the window, keeping jobCount',
      () async {
        final docs = [
          doc('c1', {'name': 'Acme', 'archived': false, 'jobCount': 7}),
        ];
        when(() => snapshot.docs).thenReturn(docs);

        final r = repo();
        expect((await r.searchClients('Acme')).single.jobCount, 7);

        await r.setClientArchived('c1', archived: true);

        // Merged, never substituted: a plain replace drops the function-owned
        // jobCount and blanks the count on every search result until the TTL.
        final after = (await r.searchClients('Acme')).single;
        expect(after.archived, isTrue);
        expect(after.jobCount, 7);
        verify(() => query.get()).called(1);
      },
    );

    test('fetchArchivedClients returns only archived, name-sorted', () async {
      final docs = [
        doc('c1', {'name': 'Zeta', 'archived': true}),
        doc('c2', {'name': 'Acme', 'archived': true}),
        doc('c3', {'name': 'Bell', 'archived': false}),
        doc('c4', {'name': 'Legacy'}),
      ];
      when(() => snapshot.docs).thenReturn(docs);

      final result = await repo().fetchArchivedClients();

      expect(result.map((c) => c.name), ['Acme', 'Zeta']);
    });

    test('fetchArchivedClients shares the search scan window', () async {
      final docs = [
        doc('c1', {'name': 'Acme', 'archived': true}),
      ];
      when(() => snapshot.docs).thenReturn(docs);

      final r = repo();
      await r.fetchArchivedClients();
      await r.searchClients('Acme');

      verify(() => query.get()).called(1);
    });

    test('fetchClientsByType excludes archived clients', () async {
      final docs = [
        doc('c1', {'name': 'Acme', 'type': 'commercial', 'archived': false}),
        doc('c2', {'name': 'Bell', 'type': 'commercial', 'archived': true}),
      ];
      when(() => snapshot.docs).thenReturn(docs);

      final result = await repo().fetchClientsByType(ClientType.commercial);

      expect(result.map((c) => c.name), ['Acme']);
    });

    test('searchClients still returns archived clients', () async {
      final docs = [
        doc('c1', {'name': 'Acme', 'archived': true}),
      ];
      when(() => snapshot.docs).thenReturn(docs);

      // Archived clients stay searchable and bookable by design — only the
      // paginated list and the type filter hide them.
      expect((await repo().searchClients('Acme')).single.id, 'c1');
    });
  });

  group('deleteClient', () {
    test(
      'calls the callable and drops the doc from the cached window',
      () async {
        final docs = [
          doc('c1', {'name': 'Junk'}),
        ];
        when(() => snapshot.docs).thenReturn(docs);

        final r = repo();
        expect((await r.searchClients('Junk')).map((c) => c.id), ['c1']);

        await r.deleteClient('c1');

        verify(() => functions.httpsCallable('deleteClient')).called(1);
        final sent = verify(
          () => callable.call<void>(captureAny<Object?>()),
        ).captured.single;
        expect((sent as Map).cast<String, dynamic>()['clientId'], 'c1');
        // `allow delete` is withdrawn on /clients — the client never deletes
        // the doc directly.
        verifyNever(() => docRef.delete());
        // Evicted in memory, so search stops returning it with no second read.
        expect(await r.searchClients('Junk'), isEmpty);
        verify(() => query.get()).called(1);
      },
    );

    test('maps client-has-history to ClientsFailureHasHistory', () async {
      when(() => callable.call<void>(any<Object?>())).thenThrow(
        FirebaseFunctionsException(
          code: 'failed-precondition',
          message: 'client-has-history',
        ),
      );

      await expectLater(
        repo().deleteClient('c1'),
        throwsA(isA<ClientsFailureHasHistory>()),
      );
    });

    test('maps client-not-found to ClientsFailureNotFound', () async {
      when(() => callable.call<void>(any<Object?>())).thenThrow(
        FirebaseFunctionsException(
          code: 'not-found',
          message: 'client-not-found',
        ),
      );

      await expectLater(
        repo().deleteClient('c1'),
        throwsA(isA<ClientsFailureNotFound>()),
      );
    });

    test('rethrows an unrecognized callable failure untyped', () async {
      when(() => callable.call<void>(any<Object?>())).thenThrow(
        FirebaseFunctionsException(code: 'internal', message: 'boom'),
      );

      await expectLater(
        repo().deleteClient('c1'),
        throwsA(isA<FirebaseFunctionsException>()),
      );
    });
  });
}

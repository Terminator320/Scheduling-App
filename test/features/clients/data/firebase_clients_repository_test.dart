// Mocktail fakes must subclass cloud_firestore's sealed query/snapshot types.
// ignore_for_file: subtype_of_sealed_class

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:scheduling/features/clients/data/firebase_clients_repository.dart';
import 'package:scheduling/features/clients/domain/models/client_record.dart';

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

void main() {
  late _MockFirestore firestore;
  late _MockCollection collection;
  late _MockQuery query;
  late _MockQuerySnapshot snapshot;
  late _MockDocRef docRef;

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
    collection = _MockCollection();
    query = _MockQuery();
    snapshot = _MockQuerySnapshot();
    docRef = _MockDocRef();

    when(() => firestore.collection('clients')).thenReturn(collection);
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
  });

  FirebaseClientsRepository repo({DateTime Function()? clock}) =>
      FirebaseClientsRepository(firestore, clock: clock);

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

      verify(() => collection.orderBy('name')).called(1);
      verify(() => query.orderBy(FieldPath.documentId)).called(1);
      verify(() => query.limit(50)).called(1);
      verifyNever(() => query.startAfter(any()));
      // Field-value cursor pagination must never refetch a boundary doc.
      verifyNever(() => collection.doc(any()));
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

  group('tag filtering', () {
    test('fetchClientTags returns distinct tags, case-insensitively sorted',
        () async {
      final docs = [
        doc('c1', {'name': 'A', 'tags': ['vip', 'net30']}),
        doc('c2', {'name': 'B', 'tags': ['Net30', 'vip']}),
        doc('c3', {'name': 'C'}),
      ];
      when(() => snapshot.docs).thenReturn(docs);

      final tags = await repo().fetchClientTags();

      // 'Net30' and 'net30' are distinct stored values; both survive, ordered
      // case-insensitively so the chip row reads alphabetically.
      expect(tags, ['Net30', 'net30', 'vip']);
    });

    test('fetchClientTags ignores blank and non-string entries', () async {
      final docs = [
        doc('c1', {'name': 'A', 'tags': ['vip', '', '  ', 42, null]}),
      ];
      when(() => snapshot.docs).thenReturn(docs);

      expect(await repo().fetchClientTags(), ['vip']);
    });

    test('fetchClientTags is empty when nobody is tagged', () async {
      final docs = [
        doc('c1', {'name': 'A'}),
      ];
      when(() => snapshot.docs).thenReturn(docs);

      expect(await repo().fetchClientTags(), isEmpty);
    });

    test('fetchClientsByTag returns only that tag, name-sorted', () async {
      final docs = [
        doc('c1', {'name': 'Zeta', 'tags': ['vip']}),
        doc('c2', {'name': 'Untagged'}),
        doc('c3', {'name': 'Alpha', 'tags': ['vip', 'net30']}),
        doc('c4', {'name': 'Other', 'tags': ['net30']}),
      ];
      when(() => snapshot.docs).thenReturn(docs);

      final tagged = await repo().fetchClientsByTag('vip');

      expect(tagged.map((c) => c.name), ['Alpha', 'Zeta']);
    });

    test('fetchClientsByTag matches the stored spelling exactly', () async {
      final docs = [
        doc('c1', {'name': 'A', 'tags': ['VIP']}),
      ];
      when(() => snapshot.docs).thenReturn(docs);

      // The chip row only ever offers stored spellings, so an exact match is
      // what keeps 'VIP' and 'vip' the two separate labels the admin typed.
      expect(await repo().fetchClientsByTag('vip'), isEmpty);
      expect((await repo().fetchClientsByTag('VIP')).single.name, 'A');
    });

    test('a blank tag reads nothing rather than everything', () async {
      final docs = [
        doc('c1', {'name': 'A', 'tags': ['vip']}),
      ];
      when(() => snapshot.docs).thenReturn(docs);

      expect(await repo().fetchClientsByTag('  '), isEmpty);
    });

    test('tags and by-tag share the search scan window (one read)', () async {
      final docs = [
        doc('c1', {'name': 'A', 'tags': ['vip']}),
      ];
      when(() => snapshot.docs).thenReturn(docs);

      final r = repo();
      await r.fetchClientTags();
      await r.fetchClientsByTag('vip');
      await r.searchClients('A');

      // The filter row costs no extra Firestore read inside the cache TTL.
      verify(() => query.get()).called(1);
    });
  });
}

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
  });

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
    when(() => query.limit(any())).thenReturn(query);
    when(() => query.get()).thenAnswer((_) async => snapshot);
    when(() => snapshot.docs).thenReturn(const []);

    when(() => collection.doc(any())).thenReturn(docRef);
    when(() => docRef.update(any())).thenAnswer((_) async {});
    when(() => docRef.delete()).thenAnswer((_) async {});
    when(() => collection.add(any())).thenAnswer((_) async => docRef);
  });

  FirebaseClientsRepository repo() => FirebaseClientsRepository(firestore);

  ClientRecord client({String id = 'c1'}) => ClientRecord(
    id: id,
    name: 'Test Client',
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

  group('deleteClient', () {
    test('deletes the correct document', () async {
      await repo().deleteClient('c42');

      verify(() => collection.doc('c42')).called(1);
      verify(() => docRef.delete()).called(1);
    });
  });

  group('searchClients', () {
    test(
      'returns empty list without querying Firestore when query too short',
      () async {
        final results = await repo().searchClients('a');

        expect(results, isEmpty);
        verifyNever(() => query.get());
      },
    );

    test('returns cached result on second call with same query', () async {
      when(() => snapshot.docs).thenReturn(const []);

      final r = repo();
      await r.searchClients('John Smith');
      await r.searchClients('John Smith');

      // Firestore read should only fire once — second call uses cache.
      verify(() => query.get()).called(1);
    });
  });
}

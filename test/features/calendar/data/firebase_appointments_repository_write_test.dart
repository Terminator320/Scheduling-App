// Mocktail fakes must subclass cloud_firestore's sealed types.
// ignore_for_file: subtype_of_sealed_class

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:scheduling/features/calendar/data/firebase_appointments_repository.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';

class _MockFirestore extends Mock implements FirebaseFirestore {}

class _MockCollection extends Mock
    implements CollectionReference<Map<String, dynamic>> {}

class _MockDoc extends Mock
    implements DocumentReference<Map<String, dynamic>> {}

class _MockBatch extends Mock implements WriteBatch {}

class _MockTransaction extends Mock implements Transaction {}

class _MockDocSnap extends Mock
    implements DocumentSnapshot<Map<String, dynamic>> {}

class _FakeDoc extends Fake
    implements DocumentReference<Map<String, dynamic>> {}

AppointmentRecord _record({
  String? id = 'a1',
  String status = 'confirmed',
}) => AppointmentRecord(
  id: id,
  title: 'Leak',
  startTime: DateTime(2026, 6, 24, 9),
  endTime: DateTime(2026, 6, 24, 10),
  status: status,
);

// Declared (not a closure) so its runtime type is exactly
// `Future<Null> Function(Transaction)` — the reified type of the repo's
// no-return async transaction handler, which mocktail's `any()` must match.
Future<Null> _fallbackHandler(Transaction _) async => null;

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeDoc());
    registerFallbackValue(<String, dynamic>{});
    // The repo's transaction handler is a no-return async closure, which
    // reifies its type argument as Null; the fallback + stub match that.
    registerFallbackValue(_fallbackHandler);
  });

  late _MockFirestore firestore;
  late _MockCollection collection;

  setUp(() {
    firestore = _MockFirestore();
    collection = _MockCollection();
    when(() => firestore.collection('appointments')).thenReturn(collection);
    when(() => collection.firestore).thenReturn(firestore);
  });

  FirebaseAppointmentsRepository repo() =>
      FirebaseAppointmentsRepository(firestore);

  group('_toFirestoreMap (via updateAppointment)', () {
    test('writes status, Timestamp times, and a server updatedAt', () async {
      final doc = _MockDoc();
      when(() => collection.doc('a1')).thenReturn(doc);
      when(() => doc.update(any())).thenAnswer((_) async {});

      await repo().updateAppointment(_record(status: 'in_progress'));

      final payload =
          (verify(() => doc.update(captureAny())).captured.single as Map)
              .cast<String, dynamic>();
      expect(payload['status'], 'in_progress');
      expect(payload['startTime'], isA<Timestamp>());
      expect(payload['endTime'], isA<Timestamp>());
      expect(payload['updatedAt'], isA<FieldValue>());
      // update must NOT stamp createdAt (only inserts do), or a re-save would
      // reset the original creation time.
      expect(payload.containsKey('createdAt'), isFalse);
    });

    test('is a no-op when the record has no id', () async {
      final doc = _MockDoc();
      when(() => collection.doc(any())).thenReturn(doc);
      when(() => doc.update(any())).thenAnswer((_) async {});

      await repo().updateAppointment(_record(id: null));

      verifyNever(() => doc.update(any()));
    });
  });

  group('addAppointment', () {
    test('stamps both createdAt and updatedAt server timestamps', () async {
      final doc = _MockDoc();
      final batch = _MockBatch();
      when(() => collection.doc('a1')).thenReturn(doc);
      when(() => firestore.batch()).thenReturn(batch);
      when(
        () => batch.set<Map<String, dynamic>>(any(), any()),
      ).thenReturn(null);
      when(() => batch.commit()).thenAnswer((_) async {});

      await repo().addAppointment(_record());

      final payload =
          (verify(
                    () => batch.set<Map<String, dynamic>>(any(), captureAny()),
                  ).captured.single
                  as Map)
              .cast<String, dynamic>();
      expect(payload['status'], 'confirmed');
      expect(payload['createdAt'], isA<FieldValue>());
      expect(payload['updatedAt'], isA<FieldValue>());
    });
  });

  group('updateAppointments (transaction)', () {
    test(
      'skips a concurrently-deleted sibling and updates the survivor',
      () async {
        final refA = _MockDoc();
        final refB = _MockDoc();
        final snapA = _MockDocSnap();
        final snapB = _MockDocSnap();
        final txn = _MockTransaction();

        when(() => collection.doc('a1')).thenReturn(refA);
        when(() => collection.doc('a2')).thenReturn(refB);
        when(() => snapA.exists).thenReturn(true); // survivor
        when(() => snapB.exists).thenReturn(false); // deleted mid-save
        when(() => txn.get(refA)).thenAnswer((_) async => snapA);
        when(() => txn.get(refB)).thenAnswer((_) async => snapB);
        when(() => txn.update(any(), any())).thenReturn(txn);
        when(() => firestore.runTransaction<Null>(any())).thenAnswer((
          invocation,
        ) async {
          final handler =
              invocation.positionalArguments.first
                  as Future<void> Function(Transaction);
          await handler(txn);
        });

        await repo().updateAppointments([
          _record(id: 'a1'),
          _record(id: 'a2'),
        ]);

        verify(() => txn.update(refA, any())).called(1);
        verifyNever(() => txn.update(refB, any()));
      },
    );

    test('is a no-op (no transaction) when no record has an id', () async {
      await repo().updateAppointments([_record(id: null)]);
      verifyNever(() => firestore.runTransaction<Null>(any()));
    });
  });
}

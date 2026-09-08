// Mocktail stubs of sealed Firestore types; the allowlist check throws before
// any Firestore call, so stubs only need to satisfy the constructor.
// ignore_for_file: subtype_of_sealed_class

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:scheduling/features/calendar/data/firebase_appointments_repository.dart';

/// S6: `updateAppointmentStatus` must reject non-allowlisted status values
/// before reaching Firestore, giving a clearer error than the rules' `permission-denied`.

class _MockFirestore extends Mock implements FirebaseFirestore {}

class _MockCollection extends Mock
    implements CollectionReference<Map<String, dynamic>> {}

class _MockDoc extends Mock
    implements DocumentReference<Map<String, dynamic>> {}

class _MockBatch extends Mock implements WriteBatch {}

void main() {
  late _MockFirestore firestore;
  late _MockCollection collection;
  late _MockDoc doc;
  late _MockBatch batch;

  // `batch.update` takes a DocumentReference, and mocktail needs a fallback
  // before `any()`/`captureAny()` can stand in for one.
  setUpAll(() => registerFallbackValue(_MockDoc()));

  setUp(() {
    firestore = _MockFirestore();
    collection = _MockCollection();
    doc = _MockDoc();
    batch = _MockBatch();
    when(() => firestore.collection('appointments')).thenReturn(collection);
    when(() => collection.doc(any())).thenReturn(doc);
    when(() => doc.update(any())).thenAnswer((_) async {});
    when(() => collection.firestore).thenReturn(firestore);
    when(firestore.batch).thenReturn(batch);
    when(
      () => batch.update(
        any<DocumentReference<Map<String, dynamic>>>(),
        any<Map<String, dynamic>>(),
      ),
    ).thenReturn(null);
    when(batch.commit).thenAnswer((_) async {});
  });

  test('rejects unknown status', () async {
    final repo = FirebaseAppointmentsRepository(firestore);
    expect(
      () => repo.updateAppointmentStatus(id: 'a1', status: 'archived'),
      throwsArgumentError,
    );
    verifyNever(() => doc.update(any()));
  });

  test('rejects empty status', () async {
    final repo = FirebaseAppointmentsRepository(firestore);
    expect(
      () => repo.updateAppointmentStatus(id: 'a1', status: ''),
      throwsArgumentError,
    );
  });

  test('accepts each allowlisted status', () async {
    final repo = FirebaseAppointmentsRepository(firestore);
    for (final s in const ['pending', 'in_progress', 'done', 'cancelled']) {
      await repo.updateAppointmentStatus(id: 'a1', status: s);
    }
    verify(() => doc.update(any())).called(4);
  });

  test('rejects retired confirmed status', () async {
    final repo = FirebaseAppointmentsRepository(firestore);
    expect(
      () => repo.updateAppointmentStatus(id: 'a1', status: 'confirmed'),
      throwsArgumentError,
    );
    verifyNever(() => doc.update(any()));
  });

  test('cancel stamps a fresh seriesOpId', () async {
    final repo = FirebaseAppointmentsRepository(firestore);
    await repo.updateAppointmentStatus(id: 'a1', status: 'cancelled');
    final payload =
        (verify(() => doc.update(captureAny())).captured.single as Map)
            .cast<String, dynamic>();
    expect(payload['status'], 'cancelled');
    expect(payload['seriesOpId'], isA<String>());
    expect(payload['seriesOpId'] as String, isNotEmpty);
  });

  test(
    'mark-done writes only status + updatedAt (employee hasOnly rule)',
    () async {
      // The employee mark-done rule is affectedKeys().hasOnly(['status',
      // 'updatedAt']); a seriesOpId here would be rejected with permission-denied.
      final repo = FirebaseAppointmentsRepository(firestore);
      await repo.updateAppointmentStatus(id: 'a1', status: 'done');
      final payload =
          (verify(() => doc.update(captureAny())).captured.single as Map)
              .cast<String, dynamic>();
      expect(payload.keys, unorderedEquals(['status', 'updatedAt']));
      expect(payload.containsKey('seriesOpId'), isFalse);
    },
  );

  group('updateAppointmentStatuses', () {
    test('writes the status to every id in ONE batch', () async {
      final repo = FirebaseAppointmentsRepository(firestore);
      await repo.updateAppointmentStatuses(
        ids: ['d1', 'd2', 'd3'],
        status: 'cancelled',
      );
      verify(
        () => batch.update(
          any<DocumentReference<Map<String, dynamic>>>(),
          any<Map<String, dynamic>>(),
        ),
      ).called(3);
      verify(batch.commit).called(1);
      verifyNever(() => doc.update(any()));
    });

    test('one shared seriesOpId, so a run cancels with ONE push', () async {
      final repo = FirebaseAppointmentsRepository(firestore);
      await repo.updateAppointmentStatuses(
        ids: ['d1', 'd2', 'd3'],
        status: 'cancelled',
      );
      final payloads = verify(
        () => batch.update(
          any<DocumentReference<Map<String, dynamic>>>(),
          captureAny<Map<String, dynamic>>(),
        ),
      ).captured.map((p) => (p as Map).cast<String, dynamic>()).toList();

      expect(payloads, hasLength(3));
      expect(payloads.every((p) => p['status'] == 'cancelled'), isTrue);
      final opIds = payloads.map((p) => p['seriesOpId']).toSet();
      expect(opIds, hasLength(1));
      expect(opIds.single, isA<String>());
      expect(opIds.single as String, isNotEmpty);
    });

    test('rejects a status off the allowlist before writing', () {
      final repo = FirebaseAppointmentsRepository(firestore);
      expect(
        () => repo.updateAppointmentStatuses(ids: ['d1'], status: 'overdue'),
        throwsArgumentError,
      );
      verifyNever(
        () => batch.update(
          any<DocumentReference<Map<String, dynamic>>>(),
          any<Map<String, dynamic>>(),
        ),
      );
    });

    test('an empty id list commits nothing', () async {
      final repo = FirebaseAppointmentsRepository(firestore);
      await repo.updateAppointmentStatuses(ids: [], status: 'cancelled');
      verifyNever(batch.commit);
    });
  });
}

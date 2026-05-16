// Mocktail-style stubs of sealed Firestore types — the canonical workaround
// for testing repos without pulling in fake_cloud_firestore. The status
// allowlist check throws before any Firestore call would happen so the
// stubs only need to satisfy the constructor.
// ignore_for_file: subtype_of_sealed_class

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:scheduling/features/calendar/data/firebase_appointments_repository.dart';

/// S6: `updateAppointmentStatus` must reject non-allowlisted status values
/// before the write reaches Firestore. The rules also enforce this, but
/// failing fast on the client gives a clearer error than `permission-denied`.
///
/// We mock `FirebaseFirestore` just enough for the constructor — the
/// allowlist check throws before any Firestore call would happen.

class _MockFirestore extends Mock implements FirebaseFirestore {}

class _MockCollection extends Mock
    implements CollectionReference<Map<String, dynamic>> {}

class _MockDoc extends Mock
    implements DocumentReference<Map<String, dynamic>> {}

void main() {
  late _MockFirestore firestore;
  late _MockCollection collection;
  late _MockDoc doc;

  setUp(() {
    firestore = _MockFirestore();
    collection = _MockCollection();
    doc = _MockDoc();
    when(() => firestore.collection('appointments')).thenReturn(collection);
    when(() => collection.doc(any())).thenReturn(doc);
    when(() => doc.update(any())).thenAnswer((_) async {});
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
    for (final s in const [
      'pending',
      'confirmed',
      'in_progress',
      'done',
      'cancelled',
    ]) {
      await repo.updateAppointmentStatus(id: 'a1', status: s);
    }
    verify(() => doc.update(any())).called(5);
  });
}

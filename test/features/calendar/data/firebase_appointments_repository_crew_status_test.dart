// Mocktail stubs of sealed Firestore types; only the constructor and one
// `update` need satisfying.
// ignore_for_file: subtype_of_sealed_class

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:scheduling/features/calendar/data/firebase_appointments_repository.dart';

/// `updateCrewStatus` is pinned field by field, like the status write: the
/// rules branch behind it is `hasOnly(['crewStatus', 'crewStatusAt',
/// 'crewStatusBy', 'updatedAt'])` with both instants pinned to `request.time`,
/// so one extra key — a `seriesOpId`, say — or one client clock is an opaque
/// `permission-denied` on the field.

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

  Map<String, dynamic> captured() =>
      (verify(() => doc.update(captureAny())).captured.single as Map)
          .cast<String, dynamic>();

  test('writes exactly the four keys the rules branch admits', () async {
    final repo = FirebaseAppointmentsRepository(firestore);
    await repo.updateCrewStatus(
      id: 'a1',
      status: 'onMyWay',
      byEmployeeId: 'e1',
    );

    final payload = captured();
    expect(
      payload.keys.toSet(),
      {'crewStatus', 'crewStatusAt', 'crewStatusBy', 'updatedAt'},
    );
    expect(payload['crewStatus'], 'onMyWay');
    expect(payload['crewStatusBy'], 'e1');
  });

  test('both instants are server timestamps, never the device clock', () async {
    final repo = FirebaseAppointmentsRepository(firestore);
    await repo.updateCrewStatus(
      id: 'a1',
      status: 'runningLate',
      byEmployeeId: 'e1',
    );

    final payload = captured();
    expect(payload['crewStatusAt'], isA<FieldValue>());
    expect(payload['updatedAt'], isA<FieldValue>());
  });

  test('rejects a value outside the two-string vocabulary', () async {
    final repo = FirebaseAppointmentsRepository(firestore);
    expect(
      () => repo.updateCrewStatus(
        id: 'a1',
        status: 'teleporting',
        byEmployeeId: 'e1',
      ),
      throwsArgumentError,
    );
    verifyNever(() => doc.update(any()));
  });
}

// Mocktail fakes must subclass cloud_firestore's sealed query/snapshot types.
// ignore_for_file: subtype_of_sealed_class

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:scheduling/features/calendar/data/firebase_appointments_repository.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_image.dart';
import 'package:scheduling/features/calendar/domain/policies/appointment_image_doc_id.dart';

class _MockFirestore extends Mock implements FirebaseFirestore {}

class _MockCollection extends Mock
    implements CollectionReference<Map<String, dynamic>> {}

class _MockDoc extends Mock
    implements DocumentReference<Map<String, dynamic>> {}

class _MockBatch extends Mock implements WriteBatch {}

class _MockQuery extends Mock implements Query<Map<String, dynamic>> {}

class _MockQuerySnapshot extends Mock
    implements QuerySnapshot<Map<String, dynamic>> {}

class _MockDocSnap extends Mock
    implements QueryDocumentSnapshot<Map<String, dynamic>> {}

class _FakeDoc extends Fake implements DocumentReference<Map<String, dynamic>> {}

class _FakeSetOptions extends Fake implements SetOptions {}

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeDoc());
    registerFallbackValue(_FakeSetOptions());
    registerFallbackValue(<String, dynamic>{});
  });

  late _MockFirestore firestore;
  late _MockCollection appointments;
  late _MockDoc parentDoc;
  late _MockCollection images;
  late _MockBatch batch;

  // Doc ids the batch was asked for, in order.
  late List<String> requestedImageIds;

  const photo = AppointmentImage(
    storagePath: 'appointments/a1/images/1754835600000_p.jpg',
    url: 'https://firebasestorage.googleapis.com/v0/b/x/o/y?alt=media&token=t',
    fileName: '1754835600000_p.jpg',
  );

  setUp(() {
    firestore = _MockFirestore();
    appointments = _MockCollection();
    parentDoc = _MockDoc();
    images = _MockCollection();
    batch = _MockBatch();
    requestedImageIds = [];

    when(() => firestore.collection('appointments')).thenReturn(appointments);
    when(() => appointments.doc(any())).thenReturn(parentDoc);
    when(() => appointments.firestore).thenReturn(firestore);
    when(() => parentDoc.collection('images')).thenReturn(images);
    when(() => images.doc(any())).thenAnswer((invocation) {
      requestedImageIds.add(invocation.positionalArguments.first as String);
      return _MockDoc();
    });

    when(firestore.batch).thenReturn(batch);
    when(() => batch.set<Map<String, dynamic>>(any(), any(), any()))
        .thenReturn(null);
    when(() => batch.update(any(), any())).thenReturn(null);
    when(() => batch.delete(any())).thenReturn(null);
    when(batch.commit).thenAnswer((_) async {});
  });

  FirebaseAppointmentsRepository repo() =>
      FirebaseAppointmentsRepository(firestore);

  group('appendAppointmentPictures writes BOTH stores', () {
    // Phase 1 of moving photos off the parent doc. The array is kept in step
    // because the build in the field reads photos from it and knows nothing
    // about the subcollection — dropping it now blanks every photo on every
    // phone until it updates.

    test('writes the subcollection doc AND the array, in one batch', () async {
      await repo().appendAppointmentPictures('a1', [photo]);

      verify(() => batch.set<Map<String, dynamic>>(any(), any(), any())).called(1);
      verify(() => batch.update(any(), any())).called(1);
      // One commit: the two stores must not be able to disagree, and this path
      // is retried by the offline queue, which has no way to reconcile a
      // half-written state.
      verify(batch.commit).called(1);
    });

    test('the subcollection id is derived from the photo, not generated',
        () async {
      // A generated id would make the offline queue's append-only retry of an
      // already-uploaded photo create a SECOND document, and the photo would
      // render twice. This is what replaces the array's arrayUnion dedupe.
      await repo().appendAppointmentPictures('a1', [photo]);
      expect(requestedImageIds, [appointmentImageDocId(photo)]);
    });

    test('the array half still uses arrayUnion', () async {
      await repo().appendAppointmentPictures('a1', [photo]);
      // WriteBatch.update takes Map<Object, Object?>, so read the key off the
      // raw map rather than casting the whole thing.
      final patch =
          verify(() => batch.update(any(), captureAny())).captured.single as Map;
      expect(patch['pictures'], isA<FieldValue>());
    });

    test('the subcollection doc omits url when storagePath is present',
        () async {
      // A persisted download URL is a permanent rules-free token, and nothing
      // reads it here — photos render from storagePath so every read
      // re-evaluates storage.rules. Dropping it is also most of the size win.
      await repo().appendAppointmentPictures('a1', [photo]);
      final body =
          verify(() => batch.set<Map<String, dynamic>>(any(), captureAny(), any()))
              .captured
              .single
              as Map<String, dynamic>;
      expect(body.containsKey('url'), isFalse);
      expect(body['storagePath'], photo.storagePath);
    });

    test('a LEGACY photo with no storagePath keeps its url', () async {
      // That url is the only thing that can render it — the same entries
      // AppointmentImageLoader's fallback exists for. Dropping it here
      // would destroy them.
      const legacy = AppointmentImage(
        url: 'https://firebasestorage.googleapis.com/v0/b/x/o/z?alt=media&t=q',
      );
      await repo().appendAppointmentPictures('a1', [legacy]);
      final body =
          verify(() => batch.set<Map<String, dynamic>>(any(), captureAny(), any()))
              .captured
              .single
              as Map<String, dynamic>;
      expect(body['url'], legacy.url);
    });

    test('skips an entry with no identity rather than failing the batch',
        () async {
      // An empty doc id would throw and take the valid photos down with it.
      await repo().appendAppointmentPictures('a1', [
        const AppointmentImage(),
        photo,
      ]);
      expect(requestedImageIds, [appointmentImageDocId(photo)]);
      verify(() => batch.set<Map<String, dynamic>>(any(), any(), any())).called(1);
      // The array half still receives both — it is the compat mirror and its
      // own dedupe governs it.
      verify(batch.commit).called(1);
    });

    test('does nothing at all for an empty list', () async {
      await repo().appendAppointmentPictures('a1', const []);
      verifyNever(batch.commit);
    });
  });

  group('removeAppointmentPictures removes from BOTH stores', () {
    test('deletes the subcollection doc and arrayRemoves', () async {
      await repo().removeAppointmentPictures('a1', [photo]);

      expect(requestedImageIds, [appointmentImageDocId(photo)]);
      verify(() => batch.delete(any())).called(1);
      // WriteBatch.update takes Map<Object, Object?>, so read the key off the
      // raw map rather than casting the whole thing.
      final patch =
          verify(() => batch.update(any(), captureAny())).captured.single as Map;
      expect(patch['pictures'], isA<FieldValue>());
      verify(batch.commit).called(1);
    });

    test('does nothing at all for an empty list', () async {
      await repo().removeAppointmentPictures('a1', const []);
      verifyNever(batch.commit);
    });
  });

  group('fetchAppointmentPictures', () {
    test('reads the subcollection ordered by uploadedAt', () async {
      // The subcollection has no inherent order where the array carried its
      // own, so without this the photo viewer's index means something
      // different on every device.
      final query = _MockQuery();
      final bounded = _MockQuery();
      final snapshot = _MockQuerySnapshot();
      final doc = _MockDocSnap();
      when(() => images.orderBy('uploadedAt')).thenReturn(query);
      // Bounded like every other read in this repository — the array's rules
      // cap is 100 and a subcollection has none of its own.
      when(() => query.limit(any())).thenReturn(bounded);
      when(bounded.get).thenAnswer((_) async => snapshot);
      when(() => snapshot.docs).thenReturn([doc]);
      when(doc.data).thenReturn({'storagePath': photo.storagePath});

      final result = await repo().fetchAppointmentPictures('a1');

      expect(result.single.storagePath, photo.storagePath);
      verify(() => images.orderBy('uploadedAt')).called(1);
      verify(() => query.limit(100)).called(1);
    });

    test('an empty subcollection returns empty, meaning "use the array"',
        () async {
      // Empty must never be read as "this job has no photos" while the array
      // is still authoritative — a doc the backfill has not reached yet is
      // exactly this shape.
      final query = _MockQuery();
      final bounded = _MockQuery();
      final snapshot = _MockQuerySnapshot();
      when(() => images.orderBy('uploadedAt')).thenReturn(query);
      when(() => query.limit(any())).thenReturn(bounded);
      when(bounded.get).thenAnswer((_) async => snapshot);
      when(() => snapshot.docs).thenReturn([]);

      expect(await repo().fetchAppointmentPictures('a1'), isEmpty);
    });
  });
}

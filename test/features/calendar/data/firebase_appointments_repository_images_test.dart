// Mocktail fakes must subclass cloud_firestore's sealed query/snapshot types.
// ignore_for_file: subtype_of_sealed_class

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/features/calendar/data/firebase_appointments_repository.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_image.dart';
import 'package:scheduling/features/calendar/domain/policies/appointment_image_doc_id.dart';

class _RecordingLogger extends AppLogger {
  final warnings = <String>[];

  @override
  void warn(String message, [Object? error, StackTrace? stack]) {
    warnings.add(message);
  }
}

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

class _FakeDoc extends Fake
    implements DocumentReference<Map<String, dynamic>> {}

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
    when(
      () => batch.set<Map<String, dynamic>>(any(), any(), any()),
    ).thenReturn(null);
    when(
      () => batch.update(
        any<DocumentReference<Map<String, dynamic>>>(),
        any<Map<String, dynamic>>(),
      ),
    ).thenReturn(null);
    when(() => batch.delete(any())).thenReturn(null);
    when(batch.commit).thenAnswer((_) async {});
  });

  FirebaseAppointmentsRepository repo() =>
      FirebaseAppointmentsRepository(firestore);

  group('appendAppointmentPictures writes the subcollection', () {
    // The CONTRACT step: photos live in `appointments/{id}/images` and nowhere
    // else. The parent document is touched for `updatedAt` alone.

    test('writes one photo document, in one batch', () async {
      await repo().appendAppointmentPictures('a1', [photo]);

      verify(
        () => batch.set<Map<String, dynamic>>(any(), any(), any()),
      ).called(1);
      // One commit: this path is retried by the offline queue, which has no
      // way to reconcile a half-written batch.
      verify(batch.commit).called(1);
    });

    test(
      'the subcollection id is derived from the photo, not generated',
      () async {
        // A generated id would make the offline queue's append-only retry of an
        // already-uploaded photo create a SECOND document, and the photo would
        // render twice. This is what replaces the array's arrayUnion dedupe.
        await repo().appendAppointmentPictures('a1', [photo]);
        expect(requestedImageIds, [appointmentImageDocId(photo)]);
      },
    );

    test('the parent write is updatedAt alone — no array, no count', () async {
      // Recreating `pictures` would put the photo list back on a document the
      // calendar reads a thousand of at a time, and writing `pictureCount`
      // would be rejected outright: the recount trigger owns it, and the rules
      // refuse an update that moves it.
      await repo().appendAppointmentPictures('a1', [photo]);
      // WriteBatch.update takes Map<Object, Object?>, so read the keys off the
      // raw map rather than casting the whole thing.
      final patch =
          verify(
                () => batch.update(
                  any<DocumentReference<Map<String, dynamic>>>(),
                  captureAny<Map<String, dynamic>>(),
                ),
              ).captured.single
              as Map;
      expect(patch.keys, ['updatedAt']);
    });

    test(
      'the subcollection doc omits url when storagePath is present',
      () async {
        // A persisted download URL is a permanent rules-free token, and nothing
        // reads it here — photos render from storagePath so every read
        // re-evaluates storage.rules. Dropping it is also most of the size win.
        await repo().appendAppointmentPictures('a1', [photo]);
        final body =
            verify(
                  () => batch.set<Map<String, dynamic>>(
                    any(),
                    captureAny(),
                    any(),
                  ),
                ).captured.single
                as Map<String, dynamic>;
        expect(body.containsKey('url'), isFalse);
        expect(body['storagePath'], photo.storagePath);
      },
    );

    test(
      'a url-only photo is SKIPPED, not written as a handle-less doc',
      () async {
        // This used to keep the url, as the only thing that could render a
        // LEGACY entry. Both that carve-out and AppointmentImageLoader's
        // matching fallback went on 2026-08-22, once a prod count found zero
        // such documents: the string is a permanent, rules-free, transferable
        // download link that nothing revokes, and `firestore.rules` now rejects
        // the field outright.
        //
        // Dropping the url alone was not enough, and this is the half that
        // matters: the write would still land as `{storagePath: ''}`, a
        // document that renders nothing AND reads as coverage to
        // `clear-appointment-picture-arrays.js`, which would then destroy the
        // array entry holding the only surviving pointer to those bytes. The
        // backfill skips exactly this shape; so does `append` now.
        const legacy = AppointmentImage(
          url:
              'https://firebasestorage.googleapis.com/v0/b/x/o/z?alt=media&t=q',
        );
        await repo().appendAppointmentPictures('a1', [legacy]);
        verifyNever(() => batch.set<Map<String, dynamic>>(any(), any(), any()));
      },
    );

    test('ALWAYS writes uploadedAt, as an explicit null when unknown', () async {
      // The invariant the file states and nothing asserted. `fetch` orders by
      // `uploadedAt`, and Firestore EXCLUDES a document missing the field it
      // orders by — so omitting the key (the way `fileName` legitimately omits
      // its own) drops that photo out of the read entirely, with nothing
      // erroring. Same trap as `archived` on clients.
      await repo().appendAppointmentPictures('a1', [photo]);
      final body =
          verify(
                () =>
                    batch.set<Map<String, dynamic>>(any(), captureAny(), any()),
              ).captured.single
              as Map<String, dynamic>;
      expect(body.containsKey('uploadedAt'), isTrue);
      expect(body['uploadedAt'], isNull);
    });

    test('a known uploadedAt is written as a Timestamp', () async {
      final stamped = AppointmentImage(
        storagePath: photo.storagePath,
        uploadedAt: DateTime.utc(2026, 8, 10, 14, 30),
      );
      await repo().appendAppointmentPictures('a1', [stamped]);
      final body =
          verify(
                () =>
                    batch.set<Map<String, dynamic>>(any(), captureAny(), any()),
              ).captured.single
              as Map<String, dynamic>;
      expect(body['uploadedAt'], isA<Timestamp>());
      expect(
        (body['uploadedAt'] as Timestamp).toDate().toUtc(),
        DateTime.utc(2026, 8, 10, 14, 30),
      );
    });

    test(
      'skips an entry with no identity rather than failing the batch',
      () async {
        // An empty doc id would throw and take the valid photos down with it.
        await repo().appendAppointmentPictures('a1', [
          const AppointmentImage(),
          photo,
        ]);
        expect(requestedImageIds, [appointmentImageDocId(photo)]);
        verify(
          () => batch.set<Map<String, dynamic>>(any(), any(), any()),
        ).called(1);
        verify(batch.commit).called(1);
      },
    );

    test('does nothing at all for an empty list', () async {
      await repo().appendAppointmentPictures('a1', const []);
      verifyNever(batch.commit);
    });
  });

  group('removeAppointmentPictures deletes from the subcollection', () {
    test('deletes by the derived id and touches only updatedAt', () async {
      // By id, so a concurrent upload's own documents are untouched. The
      // retired array half matched by DEEP EQUALITY of the whole entry map,
      // which is why it could silently remove nothing.
      await repo().removeAppointmentPictures('a1', [photo]);

      expect(requestedImageIds, [appointmentImageDocId(photo)]);
      verify(() => batch.delete(any())).called(1);
      final patch =
          verify(
                () => batch.update(
                  any<DocumentReference<Map<String, dynamic>>>(),
                  captureAny<Map<String, dynamic>>(),
                ),
              ).captured.single
              as Map;
      expect(patch.keys, ['updatedAt']);
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
      // Bounded like every other read in this repository. A subcollection has
      // no document-size ceiling of its own, so this cap is the only bound
      // left on a job's photos — `PICTURE_COUNT_WARN_CAP` is its server-side
      // twin and must keep the same number.
      when(() => query.limit(any())).thenReturn(bounded);
      when(bounded.get).thenAnswer((_) async => snapshot);
      when(() => snapshot.docs).thenReturn([doc]);
      when(doc.data).thenReturn({'storagePath': photo.storagePath});

      final result = await repo().fetchAppointmentPictures('a1');

      expect(result.single.storagePath, photo.storagePath);
      verify(() => images.orderBy('uploadedAt')).called(1);
      verify(() => query.limit(100)).called(1);
    });

    test(
      'a full page warns that photos beyond the cap were not loaded',
      () async {
        // The only bound left on a job's photos — a subcollection has no
        // document-size ceiling of its own — and the warn is the only sign a
        // job's photo strip is short. The picker caps a job at 10, so reaching
        // 100 means a modified client, which is exactly what wants recording.
        final query = _MockQuery();
        final bounded = _MockQuery();
        final snapshot = _MockQuerySnapshot();
        final doc = _MockDocSnap();
        when(doc.data).thenReturn({'storagePath': photo.storagePath});
        when(() => images.orderBy('uploadedAt')).thenReturn(query);
        when(() => query.limit(any())).thenReturn(bounded);
        when(bounded.get).thenAnswer((_) async => snapshot);
        when(() => snapshot.docs).thenReturn(List.filled(100, doc));

        final logger = _RecordingLogger();
        final result = await FirebaseAppointmentsRepository(
          firestore,
          logger: logger,
        ).fetchAppointmentPictures('a1');

        expect(result, hasLength(100));
        expect(logger.warnings, hasLength(1));
        expect(logger.warnings.single, startsWith('APPT-IMG'));
        expect(logger.warnings.single, contains('100'));
      },
    );

    test('an empty subcollection means this job has no photos', () async {
      // During the migration empty meant "not backfilled yet, use the array".
      // The array is gone, so it now means exactly what it says. The detail
      // sheet runs this read unconditionally — gating it on `pictureCount`
      // made a just-uploaded photo invisible until the recount landed.
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

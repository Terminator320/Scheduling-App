import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scheduling/core/images/image_storage_service.dart';
import 'package:scheduling/core/images/image_upload_failure.dart';
import 'package:scheduling/features/calendar/application/photo_upload_notifier.dart';
import 'package:scheduling/features/calendar/data/appointment_image_upload_service.dart';
import 'package:scheduling/features/calendar/data/pending_upload_store.dart';
import 'package:scheduling/features/calendar/domain/appointments_repository.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_image.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockAppointmentsRepository extends Mock
    implements AppointmentsRepository {}

class _MockImageStorageService extends Mock implements ImageStorageService {}

AppointmentImage _img(String name) => AppointmentImage(
  url: 'https://example.com/$name',
  storagePath: 'appointments/a1/images/$name',
  fileName: name,
  uploadedAt: DateTime(2026),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockAppointmentsRepository appointments;
  late _MockImageStorageService storage;
  late PhotoUploadNotifier notifier;
  late PendingUploadStore store;
  late Directory tempRoot;
  late Directory sourceDir;
  late Directory stagingDir;

  setUpAll(() => registerFallbackValue(File('fallback')));

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    appointments = _MockAppointmentsRepository();
    storage = _MockImageStorageService();
    notifier = PhotoUploadNotifier();
    store = PendingUploadStore();
    // The queue no longer persists download URLs, so a carried image comes
    // back with an empty one and the drain re-mints it from storagePath.
    when(() => storage.downloadUrlFor(any())).thenAnswer(
      (_) async => 'https://example.com/resolved.jpg',
    );
    tempRoot = Directory.systemTemp.createTempSync('img_upload_test');
    sourceDir = Directory('${tempRoot.path}/src')..createSync();
    stagingDir = Directory('${tempRoot.path}/staging')..createSync();

    when(
      () => appointments.appendAppointmentPictures(any(), any()),
    ).thenAnswer((_) async {});
  });

  tearDown(() {
    notifier.dispose();
    if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
  });

  AppointmentImageUploadService makeService() => AppointmentImageUploadService(
    appointments: appointments,
    notifier: notifier,
    storage: storage,
    store: store,
    stagingDirProvider: () async => stagingDir,
  );

  File makeSource(String name) =>
      File('${sourceDir.path}/$name')..writeAsStringSync('data');

  // Manually stages files and enqueues an entry, the same way _stageAndRun
  // would. Uses a fresh timestamp so drainPending's 7-day prune leaves it alone.
  Future<PendingUpload> stageEntry(
    String appointmentId,
    List<String> names, {
    int? enqueuedAtMs,
  }) async {
    enqueuedAtMs ??= DateTime.now().millisecondsSinceEpoch;
    final paths = <String>[];
    for (final n in names) {
      final p = '${stagingDir.path}/${enqueuedAtMs}_$n';
      File(p).writeAsStringSync('data');
      paths.add(p);
    }
    final entry = PendingUpload(
      appointmentId: appointmentId,
      paths: paths,
      enqueuedAtMs: enqueuedAtMs,
    );
    await store.add(entry);
    return entry;
  }

  group('drainPending', () {
    test('uploads, clears failure, deletes files, empties queue', () async {
      notifier.reportFailure('a1', failedCount: 1); // stale prior failure
      final entry = await stageEntry('a1', ['1.jpg']);
      when(
        () => storage.uploadImage(any(), any()),
      ).thenAnswer((_) async => _img('1.jpg'));

      await makeService().drainPending();

      expect(await store.load(), isEmpty);
      expect(notifier.failureFor('a1'), isNull);
      expect(File(entry.paths.single).existsSync(), isFalse);
      verify(
        () => appointments.appendAppointmentPictures(any(), any()),
      ).called(1);
    });

    test('transient failure re-queues only the unsent paths', () async {
      final entry = await stageEntry('a1', ['ok.jpg', 'fail.jpg']);
      when(() => storage.uploadImage(any(), any())).thenAnswer((invocation) {
        final f = invocation.positionalArguments[1] as File;
        if (f.path.endsWith('fail.jpg')) {
          throw const SocketException('offline');
        }
        return Future.value(_img('ok.jpg'));
      });

      await makeService().drainPending();

      final remaining = await store.load();
      expect(remaining, hasLength(1));
      expect(remaining.single.paths.single, endsWith('fail.jpg'));
      // Entry age preserved so a batch never retries past the pruning window.
      expect(remaining.single.enqueuedAtMs, entry.enqueuedAtMs);
      expect(notifier.failureFor('a1')?.failedCount, 1);
    });

    test('append failure re-queues uploaded images for an append-only '
        'retry instead of orphaning them', () async {
      final entry = await stageEntry('a1', ['1.jpg']);
      when(
        () => storage.uploadImage(any(), any()),
      ).thenAnswer((_) async => _img('1.jpg'));
      when(
        () => appointments.appendAppointmentPictures(any(), any()),
      ).thenThrow(const SocketException('offline'));

      await makeService().drainPending();

      final remaining = await store.load();
      expect(remaining, hasLength(1));
      // The upload succeeded so the local file is gone and no path re-uploads,
      // but the uploaded image is carried for an append-only retry.
      expect(remaining.single.paths, isEmpty);
      expect(remaining.single.uploaded, hasLength(1));
      expect(remaining.single.uploaded.single.storagePath, endsWith('1.jpg'));
      expect(remaining.single.enqueuedAtMs, entry.enqueuedAtMs);
      expect(File(entry.paths.single).existsSync(), isFalse);
      expect(notifier.failureFor('a1')?.failedCount, 1);
    });

    test('a re-queued append-only entry re-links without re-uploading '
        'once the write succeeds', () async {
      // Seed the queue directly with a link-only entry (no on-disk paths).
      await store.add(
        PendingUpload(
          appointmentId: 'a1',
          paths: const [],
          enqueuedAtMs: DateTime.now().millisecondsSinceEpoch,
          uploaded: [_img('1.jpg')],
        ),
      );

      await makeService().drainPending();

      expect(await store.load(), isEmpty);
      expect(notifier.failureFor('a1'), isNull);
      // No file existed to upload; only the append was re-attempted.
      verifyNever(() => storage.uploadImage(any(), any()));
      verify(
        () => appointments.appendAppointmentPictures(any(), any()),
      ).called(1);
    });

    test('a carried image whose url cannot be re-minted stays queued '
        'and is not appended', () async {
      // Appending with a blank url would write a second, broken array entry
      // beside the one a partially-committed append already left there —
      // `arrayUnion` matches by deep equality, so it would not dedupe.
      when(() => storage.downloadUrlFor(any())).thenAnswer((_) async => '');

      await store.add(
        PendingUpload(
          appointmentId: 'a1',
          paths: const [],
          enqueuedAtMs: DateTime.now().millisecondsSinceEpoch,
          uploaded: [_img('1.jpg')],
        ),
      );

      await makeService().drainPending();

      verifyNever(() => appointments.appendAppointmentPictures(any(), any()));
      final remaining = await store.load();
      expect(remaining, hasLength(1));
      expect(remaining.single.uploaded, hasLength(1));
      expect(
        remaining.single.uploaded.single.storagePath,
        'appointments/a1/images/1.jpg',
      );
    });

    test('permanent ImageUploadFailure drops the file and the entry', () async {
      await stageEntry('a1', ['bad.jpg']);
      when(
        () => storage.uploadImage(any(), any()),
      ).thenThrow(const ImageUploadFailureInvalidFormat());

      await makeService().drainPending();

      expect(await store.load(), isEmpty); // gone, never retried
      expect(notifier.failureFor('a1')?.failedCount, 1);
    });

    test('too-large rejection surfaces the file name', () async {
      await stageEntry('a1', ['big.jpg']);
      when(
        () => storage.uploadImage(any(), any()),
      ).thenThrow(const ImageUploadFailureTooLarge());

      await makeService().drainPending();

      expect(
        notifier.failureFor('a1')?.tooLargeFileNames,
        contains(endsWith('big.jpg')),
      );
    });

    test(
      'a mixed permanent + transient batch still names the too-large file',
      () async {
        await stageEntry('a1', ['big.jpg', 'ok.jpg']);
        when(() => storage.uploadImage(any(), any())).thenAnswer((
          invocation,
        ) async {
          final file = invocation.positionalArguments[1] as File;
          if (file.path.endsWith('big.jpg')) {
            throw const ImageUploadFailureTooLarge();
          }
          throw Exception('network');
        });

        await makeService().drainPending();

        final failure = notifier.failureFor('a1');
        // The oversized file was deleted from staging, so it can NEVER retry —
        // reporting only the retryable one left the user waiting for a retry
        // that cannot happen, with the one actionable detail withheld.
        expect(failure?.tooLargeFileNames, contains(endsWith('big.jpg')));
        // Both count: one permanently rejected, one queued for another go.
        expect(failure?.failedCount, 2);
        // The retryable half is still queued.
        expect((await store.load()).single.paths.single, endsWith('ok.jpg'));
      },
    );

    test('is reentrancy-safe (second call while draining no-ops)', () async {
      await stageEntry('a1', ['1.jpg']);
      final gate = Completer<AppointmentImage>();
      var calls = 0;
      when(() => storage.uploadImage(any(), any())).thenAnswer((_) async {
        calls++;
        return gate.future;
      });

      final service = makeService();
      final first = service.drainPending(); // enters, blocks on the gate
      await service
          .drainPending(); // synchronous guard, so this is an immediate no-op
      gate.complete(_img('1.jpg'));
      await first;

      expect(calls, 1);
    });

    test(
      'a batch staged mid-drain is coalesced into the in-flight pass',
      () async {
        // The guard alone ("if (_draining) return") would leave this batch
        // queued until the next connectivity flip. CLAUDE.md: coalesce, never
        // drop — the in-flight pass has to loop again and pick it up.
        await stageEntry('a1', ['a.jpg']);
        final gate = Completer<AppointmentImage>();
        final firstUploadStarted = Completer<void>();
        var calls = 0;
        when(() => storage.uploadImage(any(), any())).thenAnswer((
          invocation,
        ) async {
          calls++;
          final file = invocation.positionalArguments[1] as File;
          if (file.path.endsWith('a.jpg')) {
            firstUploadStarted.complete();
            return gate.future;
          }
          return _img('b.jpg');
        });

        final service = makeService();
        final first = service.drainPending();
        await firstUploadStarted
            .future; // pass 1 is mid-upload on the first batch
        await stageEntry('a2', ['b.jpg']); // staged while that drain is running
        await service.drainPending(); // coalesced, not dropped
        gate.complete(_img('a.jpg'));
        await first;

        expect(calls, 2);
        expect(await store.load(), isEmpty);
      },
    );

    test('an entry with no paths and no carried uploads is the only one '
        'that drains away', () async {
      // Files gone AND nothing carried: genuinely empty, so it is dropped with
      // no upload and no append. An entry carrying uploaded images is never
      // empty in this sense, however few paths it has left.
      await store.add(
        PendingUpload(
          appointmentId: 'a1',
          paths: ['${stagingDir.path}/vanished.jpg'],
          enqueuedAtMs: DateTime.now().millisecondsSinceEpoch,
        ),
      );

      await makeService().drainPending();

      expect(await store.load(), isEmpty);
      verifyNever(() => storage.uploadImage(any(), any()));
      verifyNever(() => appointments.appendAppointmentPictures(any(), any()));
      expect(notifier.failureFor('a1'), isNull);
    });
  });

  group('AttemptOutcome.from', () {
    AttemptOutcome outcome({
      int permanentFailures = 0,
      bool transientFailure = false,
      List<String> survivors = const [],
      bool resolveFailed = false,
      bool appendThrew = false,
      List<AppointmentImage> uploaded = const [],
    }) => AttemptOutcome.from(
      permanentFailures: permanentFailures,
      transientFailure: transientFailure,
      survivors: survivors,
      resolveFailed: resolveFailed,
      appendThrew: appendThrew,
      uploaded: uploaded,
    );

    test('a clean pass drains the entry and clears the failure', () {
      final result = outcome(uploaded: [_img('1.jpg')]);

      expect(result.requeue, isFalse);
      expect(result.uploadedToCarry, isEmpty);
      expect(result.failedCount, 0);
    });

    test('a failed append carries the uploaded images forward, never '
        'drops them', () {
      final images = [_img('1.jpg'), _img('2.jpg')];

      final result = outcome(appendThrew: true, uploaded: images);

      expect(result.requeue, isTrue);
      expect(result.uploadedToCarry, images);
      // No survivor paths: their local files are gone, so the retry is
      // append-only and must never re-upload them.
      expect(result.failedCount, 2);
    });

    test('an unresolvable carried url keeps the images queued', () {
      final images = [_img('1.jpg')];

      final result = outcome(
        transientFailure: true,
        resolveFailed: true,
        uploaded: images,
      );

      expect(result.requeue, isTrue);
      expect(result.uploadedToCarry, images);
      expect(result.failedCount, 1);
    });

    test('a transient upload failure re-queues the survivors alone', () {
      final result = outcome(
        transientFailure: true,
        survivors: ['/staging/fail.jpg'],
        uploaded: [_img('ok.jpg')],
      );

      expect(result.requeue, isTrue);
      // The append landed, so re-carrying these would re-link them a second
      // time on the next pass.
      expect(result.uploadedToCarry, isEmpty);
      expect(result.failedCount, 1);
    });

    test('permanent failures alone drain the entry but still report', () {
      final result = outcome(permanentFailures: 2);

      expect(result.requeue, isFalse);
      expect(result.uploadedToCarry, isEmpty);
      expect(result.failedCount, 2);
    });

    test('a mixed permanent + transient pass counts both', () {
      final result = outcome(
        permanentFailures: 1,
        transientFailure: true,
        survivors: ['/staging/ok.jpg'],
      );

      expect(result.requeue, isTrue);
      expect(result.failedCount, 2);
    });
  });

  group('uploadInBackground', () {
    test('stages picker files into the durable dir before uploading', () async {
      final src = makeSource('photo.jpg');
      final gate = Completer<AppointmentImage>();
      when(
        () => storage.uploadImage(any(), any()),
      ).thenAnswer((_) => gate.future);

      makeService().uploadInBackground(appointmentId: 'a1', newImages: [src]);

      // Poll until the file is staged and enqueued (upload is still gated open).
      var entries = <PendingUpload>[];
      for (var i = 0; i < 50 && entries.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        entries = await store.load();
      }

      expect(entries, hasLength(1));
      expect(src.existsSync(), isFalse); // moved out of the picker temp
      expect(entries.single.paths.single, startsWith(stagingDir.path));
      expect(File(entries.single.paths.single).existsSync(), isTrue);

      gate.complete(_img('photo.jpg'));
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });

    test(
      'a mid-loop staging failure deletes the files it already moved',
      () async {
        // Files moved before the throw have no queue entry naming them, so
        // nothing would ever reach them again — they must not be left behind.
        final good = makeSource('good.jpg');
        final missing = File('${sourceDir.path}/never_existed.jpg');

        makeService().uploadInBackground(
          appointmentId: 'a1',
          newImages: [good, missing],
        );

        for (var i = 0; i < 50 && notifier.failureFor('a1') == null; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }

        expect(notifier.failureFor('a1')?.failedCount, 2);
        expect(await store.load(), isEmpty);
        expect(stagingDir.listSync(), isEmpty);
        verifyNever(() => storage.uploadImage(any(), any()));
      },
    );
  });
}

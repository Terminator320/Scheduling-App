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
      await service.drainPending(); // synchronous guard, so this is an immediate no-op
      gate.complete(_img('1.jpg'));
      await first;

      expect(calls, 1);
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
  });
}

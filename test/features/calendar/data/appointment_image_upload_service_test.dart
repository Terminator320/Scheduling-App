import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:scheduling/core/images/image_storage_service.dart';
import 'package:scheduling/features/calendar/application/photo_upload_notifier.dart';
import 'package:scheduling/features/calendar/data/appointment_image_upload_service.dart';
import 'package:scheduling/features/calendar/domain/appointments_repository.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_image.dart';

class _MockAppointmentsRepository extends Mock
    implements AppointmentsRepository {}

class _MockImageStorageService extends Mock implements ImageStorageService {}

class _MockFile extends Mock implements File {}

void main() {
  late _MockAppointmentsRepository appointments;
  late _MockImageStorageService storage;
  late PhotoUploadNotifier notifier;

  setUp(() {
    appointments = _MockAppointmentsRepository();
    storage = _MockImageStorageService();
    notifier = PhotoUploadNotifier();

    when(
      () => appointments.appendAppointmentPictures(
        any<String>(),
        any<List<AppointmentImage>>(),
      ),
    ).thenAnswer((_) async {});
  });

  tearDown(() => notifier.dispose());

  AppointmentImageUploadService makeService() => AppointmentImageUploadService(
    appointments: appointments,
    notifier: notifier,
    storage: storage,
  );

  _MockFile file(String name, {int size = 1024}) {
    final f = _MockFile();
    when(() => f.uri).thenReturn(Uri.parse('file:///tmp/$name'));
    when(f.length).thenAnswer((_) async => size);
    when(f.exists).thenAnswer((_) async => true);
    when(f.delete).thenAnswer((_) async => f);
    return f;
  }

  group('uploadInBackground', () {
    test('reports no failure when all images upload successfully', () async {
      final src = file('photo.jpg');

      when(() => storage.uploadImages(any(), any())).thenAnswer(
        (_) async => ImageUploadBatchResult(
          uploaded: [
            AppointmentImage(
              url: 'https://example.com/photo.jpg',
              storagePath: 'appointments/a1/images/photo.jpg',
              fileName: 'photo.jpg',
              uploadedAt: DateTime.now(),
            ),
          ],
          failedCount: 0,
        ),
      );

      makeService().uploadInBackground(appointmentId: 'a1', newImages: [src]);

      await Future<void>.delayed(Duration.zero);
      expect(notifier.latestFailure.value, isNull);
    });

    test('reports failedCount when storage upload partially fails', () async {
      final src = file('photo.jpg');

      when(() => storage.uploadImages(any(), any())).thenAnswer(
        (_) async => const ImageUploadBatchResult(uploaded: [], failedCount: 1),
      );

      makeService().uploadInBackground(appointmentId: 'a1', newImages: [src]);

      await Future<void>.delayed(Duration.zero);
      expect(notifier.latestFailure.value?.failedCount, 1);
      expect(notifier.latestFailure.value?.appointmentId, 'a1');
    });

    test('reports tooLargeFileNames for images over size limit', () async {
      const overLimit = ImageStorageService.maxUploadBytes + 1;
      final src = file('big.jpg', size: overLimit);

      makeService().uploadInBackground(appointmentId: 'a1', newImages: [src]);

      await Future<void>.delayed(Duration.zero);
      expect(
        notifier.latestFailure.value?.tooLargeFileNames,
        contains('big.jpg'),
      );
    });

    test('reports all images as failed when run throws unexpectedly', () async {
      final src = file('photo.jpg');

      when(
        () => storage.uploadImages(any(), any()),
      ).thenThrow(Exception('upload failed'));

      makeService().uploadInBackground(appointmentId: 'a1', newImages: [src]);

      await Future<void>.delayed(Duration.zero);
      expect(notifier.latestFailure.value?.failedCount, 1);
    });
  });
}

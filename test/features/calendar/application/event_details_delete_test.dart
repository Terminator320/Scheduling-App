import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/core/images/image_storage_service.dart';
import 'package:scheduling/core/images/images_providers.dart';
import 'package:scheduling/features/calendar/application/appointments_providers.dart';
import 'package:scheduling/features/calendar/application/event_details_controller.dart';
import 'package:scheduling/features/calendar/domain/appointments_repository.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_image.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';

class _ThrowingRepo implements AppointmentsRepository {
  @override
  Future<void> deleteAppointment(String id) async {
    throw Exception('boom');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _RecordingRepo implements AppointmentsRepository {
  _RecordingRepo({this.series = const []});

  final List<AppointmentRecord> series;
  final List<String> deletedIds = [];

  @override
  Future<void> deleteAppointment(String id) async {
    deletedIds.add(id);
  }

  @override
  Future<void> deleteAppointments(List<String> ids) async {
    deletedIds.addAll(ids);
  }

  @override
  Future<List<AppointmentRecord>> getSeries(String seriesId) async => series;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _RecordingStorage implements ImageStorageService {
  final List<AppointmentImage> deleted = [];

  @override
  Future<void> deleteImages(List<AppointmentImage> images) async {
    deleted.addAll(images);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

AppointmentImage _image(String path) => AppointmentImage(storagePath: path);

void main() {
  test(
    'deleteAppointment returns the error when the repository throws',
    () async {
      final container = ProviderContainer(
        overrides: [
          appointmentsRepositoryProvider.overrideWithValue(_ThrowingRepo()),
        ],
      );
      addTearDown(container.dispose);

      final appointment = AppointmentRecord(
        id: 'a1',
        startTime: DateTime(2026, 6, 6, 9),
        endTime: DateTime(2026, 6, 6, 10),
      );
      final provider = eventDetailsControllerProvider(appointment);
      // AutoDispose family: keep state alive across reads (testing.md).
      final sub = container.listen(provider, (_, _) {});
      addTearDown(sub.close);

      final error = await container
          .read(provider.notifier)
          .deleteAppointment(appointment);

      expect(error, isNotNull);
      expect(error.toString(), contains('boom'));
    },
  );

  test('deleting an appointment deletes its Storage images', () async {
    final repo = _RecordingRepo();
    final storage = _RecordingStorage();
    final container = ProviderContainer(
      overrides: [
        appointmentsRepositoryProvider.overrideWithValue(repo),
        imageStorageProvider.overrideWithValue(storage),
      ],
    );
    addTearDown(container.dispose);

    final appointment = AppointmentRecord(
      id: 'a1',
      startTime: DateTime(2026, 6, 6, 9),
      endTime: DateTime(2026, 6, 6, 10),
      pictures: [_image('appointments/a1/images/p1'), _image('a1/p2')],
    );
    final provider = eventDetailsControllerProvider(appointment);
    final sub = container.listen(provider, (_, _) {});
    addTearDown(sub.close);

    final error = await container
        .read(provider.notifier)
        .deleteAppointment(appointment);

    expect(error, isNull);
    expect(repo.deletedIds, ['a1']);
    expect(
      storage.deleted.map((i) => i.storagePath),
      ['appointments/a1/images/p1', 'a1/p2'],
    );
  });

  test(
    'series delete also removes future-visit images but preserves '
    'terminal-visit images',
    () async {
      final base = DateTime(2026, 6, 6, 9);
      final deleted = AppointmentRecord(
        id: 's1',
        seriesId: 's1',
        startTime: base,
        endTime: base.add(const Duration(hours: 1)),
        pictures: [_image('s1/p')],
      );
      final futureVisit = AppointmentRecord(
        id: 's2',
        seriesId: 's1',
        startTime: base.add(const Duration(days: 120)),
        endTime: base.add(const Duration(days: 120, hours: 1)),
        pictures: [_image('s2/future')],
      );
      // A completed future visit is preserved as a record — its bytes stay.
      final doneVisit = AppointmentRecord(
        id: 's3',
        seriesId: 's1',
        startTime: base.add(const Duration(days: 240)),
        endTime: base.add(const Duration(days: 240, hours: 1)),
        status: 'done',
        pictures: [_image('s3/done')],
      );

      final repo = _RecordingRepo(series: [deleted, futureVisit, doneVisit]);
      final storage = _RecordingStorage();
      final container = ProviderContainer(
        overrides: [
          appointmentsRepositoryProvider.overrideWithValue(repo),
          imageStorageProvider.overrideWithValue(storage),
        ],
      );
      addTearDown(container.dispose);

      final provider = eventDetailsControllerProvider(deleted);
      final sub = container.listen(provider, (_, _) {});
      addTearDown(sub.close);

      final error = await container
          .read(provider.notifier)
          .deleteAppointment(deleted, includeFuture: true);

      expect(error, isNull);
      expect(repo.deletedIds, ['s1', 's2']);
      expect(
        storage.deleted.map((i) => i.storagePath),
        ['s1/p', 's2/future'],
      );
    },
  );
}

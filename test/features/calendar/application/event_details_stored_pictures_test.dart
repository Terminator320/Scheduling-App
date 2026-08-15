import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/features/calendar/application/appointments_providers.dart';
import 'package:scheduling/features/calendar/application/event_details_controller.dart';
import 'package:scheduling/features/calendar/domain/appointments_repository.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_image.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';

/// Serves one canned subcollection read, or throws.
///
/// Hand-rolled rather than mocked so [gate] can hold the read open across the
/// window a user edit lands in — the case the adopt check exists for.
class _PicturesRepo implements AppointmentsRepository {
  _PicturesRepo({this.stored = const [], this.gate, this.throws = false});

  final List<AppointmentImage> stored;
  final Completer<void>? gate;
  final bool throws;
  int calls = 0;

  @override
  Future<List<AppointmentImage>> fetchAppointmentPictures(String id) async {
    calls++;
    if (gate != null) await gate!.future;
    if (throws) throw Exception('subcollection read failed');
    return stored;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

AppointmentImage _image(String name, {String url = ''}) =>
    AppointmentImage(storagePath: 'appointments/a1/images/$name', url: url);

AppointmentRecord _appointmentWith(List<AppointmentImage> pictures) =>
    AppointmentRecord(
      id: 'a1',
      startTime: DateTime(2026, 6, 6, 9),
      endTime: DateTime(2026, 6, 6, 10),
      pictures: pictures,
    );

typedef _Harness = ({
  EventDetailsController notifier,
  EventDetailsState Function() read,
});

void main() {
  _Harness build(AppointmentRecord appointment, AppointmentsRepository repo) {
    final container = ProviderContainer(
      overrides: [appointmentsRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    final provider = eventDetailsControllerProvider(
      EventDetailsKey(appointment),
    );
    // Keep the autoDispose family's state alive across reads (see testing.md).
    final sub = container.listen(provider, (_, _) {});
    addTearDown(sub.close);
    return (
      notifier: container.read(provider.notifier),
      read: () => container.read(provider),
    );
  }

  /// Lets the `Future.microtask` in `build()` and the awaited read settle.
  Future<void> settle() async {
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
  }

  List<String> paths(List<AppointmentImage> images) => [
    for (final i in images) i.storagePath,
  ];

  test('adopts the subcollection read while the list is untouched', () async {
    final repo = _PicturesRepo(stored: [_image('p1'), _image('p2')]);
    final harness = build(_appointmentWith([_image('p1')]), repo);

    await settle();

    expect(paths(harness.read().existingImages), [
      'appointments/a1/images/p1',
      'appointments/a1/images/p2',
    ]);
  });

  test(
    'a partial subcollection UNIONS with the array rather than replacing it',
    () async {
      // Photo phase 1's normal shape: three legacy photos live in the array
      // only, and the one added on the current build is the single row the
      // subcollection carries. Iterating `stored` alone rendered 1 of 4.
      final repo = _PicturesRepo(stored: [_image('p4')]);
      final harness = build(
        _appointmentWith([_image('p1'), _image('p2'), _image('p3')]),
        repo,
      );

      await settle();

      expect(paths(harness.read().existingImages), [
        'appointments/a1/images/p1',
        'appointments/a1/images/p2',
        'appointments/a1/images/p3',
        'appointments/a1/images/p4',
      ]);
    },
  );

  test('a photo in both stores keeps the ARRAY instance', () async {
    // The array entry carries a url; the subcollection row deliberately omits
    // it. `arrayRemove` matches by deep equality of the whole map, so a later
    // removal only works against the instance the parent document parsed.
    final repo = _PicturesRepo(stored: [_image('p1'), _image('p2')]);
    final harness = build(
      _appointmentWith([_image('p1', url: 'https://token/p1')]),
      repo,
    );

    await settle();

    expect(harness.read().existingImages.first.url, 'https://token/p1');
  });

  test(
    'adopts even though the freezed list getter is never identical to the seed',
    () async {
      final repo = _PicturesRepo(stored: [_image('p1'), _image('p2')]);
      final harness = build(_appointmentWith([_image('p1')]), repo);

      // Every read of the collection getter wraps the backing list in a new
      // view, so an `identical` seed check could never pass — which is why the
      // adopt gate compares by value.
      expect(
        identical(
          harness.read().existingImages,
          harness.read().existingImages,
        ),
        isFalse,
      );

      await settle();

      expect(harness.read().existingImages, hasLength(2));
    },
  );

  test(
    'DISCARDS the read when the user removed a photo mid-round-trip',
    () async {
      final gate = Completer<void>();
      final repo = _PicturesRepo(
        stored: [_image('p1'), _image('p2'), _image('p3')],
        gate: gate,
      );
      final harness = build(
        _appointmentWith([_image('p1'), _image('p2')]),
        repo,
      );
      await settle();

      harness.notifier.removeExistingImage(0);
      gate.complete();
      await settle();

      expect(repo.calls, 1);
      expect(paths(harness.read().existingImages), [
        'appointments/a1/images/p2',
      ]);
      expect(harness.read().removedExistingImages, hasLength(1));
    },
  );

  test('a throwing read leaves the seeded array intact', () async {
    final repo = _PicturesRepo(throws: true);
    final harness = build(
      _appointmentWith([_image('p1'), _image('p2')]),
      repo,
    );

    await settle();

    expect(paths(harness.read().existingImages), [
      'appointments/a1/images/p1',
      'appointments/a1/images/p2',
    ]);
  });

  test('an empty read leaves the seeded array intact', () async {
    final repo = _PicturesRepo();
    final harness = build(_appointmentWith([_image('p1')]), repo);

    await settle();

    expect(paths(harness.read().existingImages), [
      'appointments/a1/images/p1',
    ]);
  });

  test('a subset read leaves the seeded array unchanged', () async {
    final repo = _PicturesRepo(stored: [_image('p2')]);
    final harness = build(
      _appointmentWith([_image('p1'), _image('p2')]),
      repo,
    );

    await settle();

    expect(paths(harness.read().existingImages), [
      'appointments/a1/images/p1',
      'appointments/a1/images/p2',
    ]);
  });

  test('skips the read entirely when neither store holds a photo', () async {
    final repo = _PicturesRepo(stored: [_image('p1')]);
    final harness = build(_appointmentWith(const []), repo);

    await settle();

    expect(repo.calls, 0);
    expect(harness.read().existingImages, isEmpty);
  });
}

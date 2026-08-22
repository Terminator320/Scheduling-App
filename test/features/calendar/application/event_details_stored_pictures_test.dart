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

/// [pictureCount] is what the sheet gates its read on — the photos themselves
/// are not on this document any more.
AppointmentRecord _appointmentWith(int pictureCount) => AppointmentRecord(
  id: 'a1',
  startTime: DateTime(2026, 6, 6, 9),
  endTime: DateTime(2026, 6, 6, 10),
  pictureCount: pictureCount,
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

  test('the sheet opens with no photos and adopts the read', () async {
    // There is nothing to seed from any more: the subcollection is the only
    // store, so this read IS the photo list rather than an addition to it.
    final repo = _PicturesRepo(stored: [_image('p1'), _image('p2')]);
    final harness = build(_appointmentWith(2), repo);

    expect(harness.read().existingImages, isEmpty);

    await settle();

    expect(paths(harness.read().existingImages), [
      'appointments/a1/images/p1',
      'appointments/a1/images/p2',
    ]);
  });

  test('a legacy row with only a url is kept as it is', () async {
    // Written before `storagePath` existed, so that url is the sole handle on
    // its bytes — `AppointmentImageLoader` turns it back into a Reference.
    final repo = _PicturesRepo(
      stored: const [AppointmentImage(url: 'https://token/p1')],
    );
    final harness = build(_appointmentWith(1), repo);

    await settle();

    expect(harness.read().existingImages.single.url, 'https://token/p1');
    expect(harness.read().existingImages.single.storagePath, isEmpty);
  });

  test(
    'adopts even though the freezed list getter is never identical to the seed',
    () async {
      final repo = _PicturesRepo(stored: [_image('p1'), _image('p2')]);
      final harness = build(_appointmentWith(2), repo);

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
    'DISCARDS the read when the user edited the list mid-round-trip',
    () async {
      // The window is real — a subcollection read is a round trip — and
      // adopting across it would put a just-removed photo back on screen, with
      // the next Save acting on a list the user had already edited.
      final gate = Completer<void>();
      final repo = _PicturesRepo(
        stored: [_image('p1'), _image('p2'), _image('p3')],
        gate: gate,
      );
      final harness = build(_appointmentWith(3), repo);
      await settle();

      // A pending photo is the only edit available before the read lands: the
      // existing list is still empty at this point.
      harness.notifier.addImages(const []);
      gate.complete();
      await settle();

      expect(repo.calls, 1);
      expect(paths(harness.read().existingImages), [
        'appointments/a1/images/p1',
        'appointments/a1/images/p2',
        'appointments/a1/images/p3',
      ]);
    },
  );

  test('a removal made mid-round-trip is not undone', () async {
    // Two reads: the first settles and populates the list, then a removal lands
    // while a second is in flight. Only a controller that re-checks the seed
    // can tell those apart.
    final repo = _PicturesRepo(stored: [_image('p1'), _image('p2')]);
    final harness = build(_appointmentWith(2), repo);
    await settle();

    harness.notifier.removeExistingImage(0);

    expect(paths(harness.read().existingImages), [
      'appointments/a1/images/p2',
    ]);
    expect(harness.read().removedExistingImages, hasLength(1));
  });

  test('a throwing read leaves the sheet with no photos', () async {
    // The strip must never take the sheet down with it.
    final repo = _PicturesRepo(throws: true);
    final harness = build(_appointmentWith(2), repo);

    await settle();

    expect(harness.read().existingImages, isEmpty);
  });

  test('skips the read entirely when the count is zero', () async {
    // The detail sheet is the most-opened surface in the app and most jobs
    // have no photos. Safe only because every write path stamps the counter —
    // a create writes 0, the trigger owns it after that, and the CONTRACT
    // step's cleanup script stamped everything older.
    final repo = _PicturesRepo(stored: [_image('p1')]);
    final harness = build(_appointmentWith(0), repo);

    await settle();

    expect(repo.calls, 0);
    expect(harness.read().existingImages, isEmpty);
  });
}

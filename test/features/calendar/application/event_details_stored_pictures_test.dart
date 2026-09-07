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
  _PicturesRepo({
    this.stored = const [],
    this.later,
    this.gate,
    this.throws = false,
  }) {
    addTearDown(localWrites.close);
  }

  final List<AppointmentImage> stored;

  /// Served from the second read on, so a poke-driven refresh is visible.
  final List<AppointmentImage>? later;
  final Completer<void>? gate;
  final bool throws;
  int calls = 0;

  /// The background-upload poke, real rather than `Stream.empty()`: stubbed
  /// empty, the subscription under test could be deleted with every test green.
  final StreamController<void> localWrites = StreamController<void>.broadcast();

  @override
  Future<List<AppointmentImage>> fetchAppointmentPictures(String id) async {
    calls++;
    if (gate != null) await gate!.future;
    if (throws) throw Exception('subcollection read failed');
    return calls > 1 ? (later ?? stored) : stored;
  }

  @override
  Stream<void> get onLocalWrite => localWrites.stream;

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
    // Written before `storagePath` existed. The READ still round-trips the
    // field — it is the entry's only identity, so `appointmentImageDocId`
    // keys on it — but nothing renders from it: the loader's `refFromURL`
    // fallback was deleted once a prod count found zero such rows.
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
        identical(harness.read().existingImages, harness.read().existingImages),
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

    expect(paths(harness.read().existingImages), ['appointments/a1/images/p2']);
    expect(harness.read().removedExistingImages, hasLength(1));
  });

  test('a throwing read leaves the sheet with no photos', () async {
    // The strip must never take the sheet down with it.
    final repo = _PicturesRepo(throws: true);
    final harness = build(_appointmentWith(2), repo);

    await settle();

    expect(harness.read().existingImages, isEmpty);
  });

  test('a local write poke re-reads and adopts the new photo list', () async {
    // The subscription in `build()` IS the fix for a background upload landing
    // with nothing left to re-read the subcollection.
    final repo = _PicturesRepo(
      stored: [_image('p1')],
      later: [_image('p1'), _image('p2')],
    );
    final harness = build(_appointmentWith(1), repo);
    await settle();
    expect(paths(harness.read().existingImages), ['appointments/a1/images/p1']);

    repo.localWrites.add(null);
    await settle();

    expect(repo.calls, 2);
    expect(paths(harness.read().existingImages), [
      'appointments/a1/images/p1',
      'appointments/a1/images/p2',
    ]);
  });

  test('a poke does NOT adopt over an edit made in the sheet', () async {
    // Same refusal the mid-round-trip case pins, reached from the poke instead:
    // a photo removed in the sheet must not be put back by a server list.
    final repo = _PicturesRepo(
      stored: [_image('p1')],
      later: [_image('p1'), _image('p2')],
    );
    final harness = build(_appointmentWith(1), repo);
    await settle();

    harness.notifier.removeExistingImage(0);
    expect(harness.read().existingImages, isEmpty);

    repo.localWrites.add(null);
    await settle();

    expect(repo.calls, 2);
    expect(harness.read().existingImages, isEmpty);
  });

  test('reads the subcollection even when the count says zero', () async {
    // THE REGRESSION THIS PINS. The sheet used to skip the read whenever
    // `pictureCount` was 0, on the reasoning that the counter is complete. It
    // is not complete in TIME: `debouncedRecountPictures` settles for 2 s
    // before it even runs the aggregate, so a photo added seconds ago still
    // reads as 0 — and a parent write that exhausts its retry budget leaves it
    // at 0 forever. Both cases rendered "No photos" over photos that exist.
    final repo = _PicturesRepo(stored: [_image('p1')]);
    final harness = build(_appointmentWith(0), repo);

    await settle();

    expect(repo.calls, 1);
    expect(harness.read().existingImages.map((i) => i.storagePath), [
      'appointments/a1/images/p1',
    ]);
  });
}

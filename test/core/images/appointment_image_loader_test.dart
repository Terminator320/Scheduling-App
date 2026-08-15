// Pins AppointmentImageLoader — the reason appointment photos are rendered
// from bytes held in memory rather than from any URL.
//
// getDownloadURL() mints a permanent `?alt=media&token=…` URL readable by
// anyone holding it with no auth and no rules evaluation, so a URL rendered
// while an employee was active kept working after deactivateEmployee revoked
// everything else — and its predecessor, which re-minted that URL at render
// time, only ever gated the MINT. getData() is an authenticated SDK fetch:
// storage.rules is evaluated every time, and nothing shareable is produced.
// The legacy fallback is what keeps that from being a migration.

import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:scheduling/core/images/appointment_image_loader.dart';
import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_image.dart';

class _MockStorage extends Mock implements FirebaseStorage {}

class _MockRef extends Mock implements Reference {}

Uint8List _bytes(String tag) => Uint8List.fromList(tag.codeUnits);

void main() {
  late _MockStorage storage;
  late _MockRef ref;
  late AppointmentImageLoader loader;

  setUp(() {
    storage = _MockStorage();
    ref = _MockRef();
    loader = AppointmentImageLoader(storage: storage, logger: AppLogger());
  });

  const path = 'appointments/a1/images/123_photo.jpg';
  const stored = 'https://storage/stale?token=old';
  final photo = _bytes('photo-bytes');

  /// Stubs [r] to answer [answer] for whatever `maxSize` the loader passes.
  void whenGetData(_MockRef r, Future<Uint8List?> Function() answer) {
    when(() => r.getData(any())).thenAnswer((_) => answer());
  }

  test(
    'fetches the bytes from storagePath, never from the stored url',
    () async {
      when(() => storage.ref(path)).thenReturn(ref);
      whenGetData(ref, () async => photo);

      expect(
        await loader.load(
          const AppointmentImage(url: stored, storagePath: path),
        ),
        photo,
      );
      verifyNever(() => storage.refFromURL(any()));
    },
  );

  test('a doc with no storagePath is fetched through its url', () async {
    // Legacy docs written before storagePath existed have nothing else to
    // identify them by — this fallback is why the change needs no migration.
    // The url is only a HANDLE: it is resolved back to a Reference and fetched
    // through the SDK, so even here storage.rules is evaluated and the token
    // url never reaches the network stack.
    when(() => storage.refFromURL(stored)).thenReturn(ref);
    whenGetData(ref, () async => photo);

    expect(await loader.load(const AppointmentImage(url: stored)), photo);
  });

  test('a doc with neither a storagePath nor a url resolves to nothing', () {
    return expectLater(
      loader.load(const AppointmentImage()),
      completion(isEmpty),
    );
  });

  test('a url Storage cannot parse resolves to nothing, not a throw', () {
    // refFromURL parses, so it throws rather than returning — and it must be
    // caught here, or the broken future escapes into the widget's setState.
    when(() => storage.refFromURL(any())).thenThrow(ArgumentError('not ours'));

    return expectLater(
      loader.load(const AppointmentImage(url: 'not-a-storage-url')),
      completion(isEmpty),
    );
  });

  test('an offline fetch resolves to nothing, never a fallback url', () async {
    // The old resolver fell back to the stored url here, on the grounds that a
    // transport failure says nothing about entitlement. That url is a
    // permanent rules-free link, so there is deliberately no such fallback
    // left: the tile is empty and the next open retries.
    when(() => storage.ref(path)).thenReturn(ref);
    whenGetData(ref, () async => throw Exception('offline'));

    expect(
      await loader.load(const AppointmentImage(url: stored, storagePath: path)),
      isEmpty,
    );
  });

  for (final code in const ['unauthorized', 'permission-denied']) {
    test('a $code rejection resolves to nothing, never the token url', () {
      // The stored url reads with no auth and no rules evaluation, so falling
      // back on a RULES rejection would hand a disabled employee a working
      // link — the exact hole this loader exists to close.
      when(() => storage.ref(path)).thenReturn(ref);
      whenGetData(
        ref,
        () async =>
            throw FirebaseException(plugin: 'firebase_storage', code: code),
      );

      return expectLater(
        loader.load(
          const AppointmentImage(url: stored, storagePath: path),
        ),
        completion(isEmpty),
      );
    });
  }

  test('loadAll keeps list order', () async {
    // The viewer opens at a tapped INDEX, so a reordered result would open
    // the wrong photo.
    for (final key in const ['p/1', 'p/2', 'p/3']) {
      final r = _MockRef();
      when(() => storage.ref(key)).thenReturn(r);
      whenGetData(r, () async => _bytes(key));
    }

    final loaded = await loader.loadAll(const [
      AppointmentImage(storagePath: 'p/1'),
      AppointmentImage(storagePath: 'p/2'),
      AppointmentImage(storagePath: 'p/3'),
    ]);

    expect(loaded, [_bytes('p/1'), _bytes('p/2'), _bytes('p/3')]);
  });

  test('loadAll keeps list order past the concurrency bound', () async {
    // loadAll fetches in batches, so the order guarantee has to survive being
    // reassembled across more than one batch.
    final paths = [for (var i = 0; i < 9; i++) 'p/$i'];
    for (final p in paths) {
      final r = _MockRef();
      when(() => storage.ref(p)).thenReturn(r);
      whenGetData(r, () async => _bytes(p));
    }

    final loaded = await loader.loadAll([
      for (final p in paths) AppointmentImage(storagePath: p),
    ]);

    expect(loaded, [for (final p in paths) _bytes(p)]);
  });

  group('the session cache', () {
    test('bytes are fetched once and served from memory after', () async {
      // The fetch is a live round-trip paid per widget State — so a sheet
      // toggled View→Edit used to re-fetch every photo. Holding the BYTES
      // rather than a url is what keeps that win without a leakable string.
      when(() => storage.ref(path)).thenReturn(ref);
      whenGetData(ref, () async => photo);
      const image = AppointmentImage(url: stored, storagePath: path);

      expect(await loader.load(image), photo);
      expect(await loader.load(image), photo);

      verify(() => ref.getData(any())).called(1);
    });

    test('a permission-denied REFUSAL is never cached', () async {
      // Empty is a refusal, not a value, and entitlement can change
      // mid-session — an employee reactivated (or a token propagating right
      // after sign-in) must not stay refused for the rest of the session.
      when(() => storage.ref(path)).thenReturn(ref);
      whenGetData(
        ref,
        () async => throw FirebaseException(
          plugin: 'firebase_storage',
          code: 'permission-denied',
        ),
      );
      const image = AppointmentImage(url: stored, storagePath: path);

      expect(await loader.load(image), isEmpty);

      whenGetData(ref, () async => photo);
      expect(await loader.load(image), photo);
      verify(() => ref.getData(any())).called(2);
    });

    test('a transient failure is not cached either', () async {
      // It resolves to the same empty refusal, and the network coming back
      // must be enough to render the photo on the next open.
      when(() => storage.ref(path)).thenReturn(ref);
      whenGetData(ref, () async => throw Exception('offline'));
      const image = AppointmentImage(url: stored, storagePath: path);

      expect(await loader.load(image), isEmpty);

      whenGetData(ref, () async => photo);
      expect(await loader.load(image), photo);
      verify(() => ref.getData(any())).called(2);
    });

    test(
      'a legacy doc with no storagePath is never cached under a blank key',
      () async {
        // Two legacy docs share the empty storagePath, so keying on it would
        // serve the first doc's bytes for the second — the positional-mixup
        // shape this whole area has been bitten by.
        for (final url in const ['legacy-a', 'legacy-b']) {
          final r = _MockRef();
          when(() => storage.refFromURL(url)).thenReturn(r);
          whenGetData(r, () async => _bytes(url));
        }

        expect(
          await loader.load(const AppointmentImage(url: 'legacy-a')),
          _bytes('legacy-a'),
        );
        expect(
          await loader.load(const AppointmentImage(url: 'legacy-b')),
          _bytes('legacy-b'),
        );
      },
    );

    test(
      'the cache is bounded, so a long session cannot retain every photo',
      () async {
        // Bytes are far heavier than the urls this replaced. Without a budget a
        // session that opens fifty jobs holds every photo of every one of them
        // for as long as the app runs.
        final big = Uint8List(9 * 1024 * 1024);
        final paths = [for (var i = 0; i < 3; i++) 'big/$i'];
        final refs = <String, _MockRef>{};
        for (final p in paths) {
          final r = _MockRef();
          refs[p] = r;
          when(() => storage.ref(p)).thenReturn(r);
          whenGetData(r, () async => big);
        }

        for (final p in paths) {
          await loader.load(AppointmentImage(storagePath: p));
        }
        // 27 MB is over the 24 MB budget, so the oldest entry was evicted and
        // asking for it again refetches; the newest is still served from memory.
        await loader.load(AppointmentImage(storagePath: paths.first));
        await loader.load(AppointmentImage(storagePath: paths.last));

        verify(() => refs[paths.first]!.getData(any())).called(2);
        verify(() => refs[paths.last]!.getData(any())).called(1);
      },
    );
  });
}

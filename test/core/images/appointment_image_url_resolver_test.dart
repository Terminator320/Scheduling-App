// Pins AppointmentImageUrlResolver — the reason appointment photos are no
// longer rendered from the URL persisted at upload time.
//
// getDownloadURL() mints a permanent `?alt=media&token=…` URL readable by
// anyone holding it with no rules evaluation, so a URL captured while an
// employee was active kept working after deactivateEmployee revoked
// everything else. Resolving from storagePath puts storage.rules back in
// front of every read — and the legacy fallback is what keeps that from
// being a migration.

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:scheduling/core/images/appointment_image_url_resolver.dart';
import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_image.dart';

class _MockStorage extends Mock implements FirebaseStorage {}

class _MockRef extends Mock implements Reference {}

void main() {
  late _MockStorage storage;
  late _MockRef ref;
  late AppointmentImageUrlResolver resolver;

  setUp(() {
    storage = _MockStorage();
    ref = _MockRef();
    resolver = AppointmentImageUrlResolver(
      storage: storage,
      logger: AppLogger(),
    );
  });

  const path = 'appointments/a1/images/123_photo.jpg';
  const fresh = 'https://storage/fresh?token=new';
  const stored = 'https://storage/stale?token=old';

  test('resolves from storagePath, not the stored url', () {
    when(() => storage.ref(path)).thenReturn(ref);
    when(ref.getDownloadURL).thenAnswer((_) async => fresh);

    return expectLater(
      resolver.resolve(
        const AppointmentImage(url: stored, storagePath: path),
      ),
      completion(fresh),
    );
  });

  test('falls back to the stored url for a doc with no storagePath', () {
    // Legacy docs written before storagePath existed have nothing else to
    // render from — this fallback is why the change needs no migration.
    return expectLater(
      resolver.resolve(const AppointmentImage(url: stored)),
      completion(stored),
    );
  });

  test('falls back to the stored url when Storage is offline', () {
    when(() => storage.ref(path)).thenReturn(ref);
    when(ref.getDownloadURL).thenThrow(Exception('offline'));

    // A broken tile for someone who IS entitled to the photo is worse than a
    // stale URL, and a transport failure says nothing about entitlement.
    return expectLater(
      resolver.resolve(
        const AppointmentImage(url: stored, storagePath: path),
      ),
      completion(stored),
    );
  });

  for (final code in const ['unauthorized', 'permission-denied']) {
    test('a $code rejection resolves to nothing, never the token url', () {
      // The stored url reads with no auth and no rules evaluation, so falling
      // back on a RULES rejection would hand a disabled employee a working
      // link — the exact hole this resolver exists to close.
      when(() => storage.ref(path)).thenReturn(ref);
      when(ref.getDownloadURL).thenThrow(
        FirebaseException(plugin: 'firebase_storage', code: code),
      );

      return expectLater(
        resolver.resolve(
          const AppointmentImage(url: stored, storagePath: path),
        ),
        completion(isEmpty),
      );
    });
  }

  test('resolveAll keeps list order', () async {
    // The viewer opens at a tapped INDEX, so a reordered result would open
    // the wrong photo.
    final refs = {
      'p/1': 'url-1',
      'p/2': 'url-2',
      'p/3': 'url-3',
    };
    for (final entry in refs.entries) {
      final r = _MockRef();
      when(() => storage.ref(entry.key)).thenReturn(r);
      when(r.getDownloadURL).thenAnswer((_) async => entry.value);
    }

    final urls = await resolver.resolveAll([
      for (final key in refs.keys) AppointmentImage(storagePath: key),
    ]);

    expect(urls, ['url-1', 'url-2', 'url-3']);
  });
}

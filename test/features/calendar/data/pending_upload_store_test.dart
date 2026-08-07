import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/features/calendar/data/pending_upload_store.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_image.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('load returns empty when nothing stored', () async {
    final store = PendingUploadStore();
    expect(await store.load(), isEmpty);
  });

  test('add then load round-trips an entry', () async {
    final store = PendingUploadStore();
    const entry = PendingUpload(
      appointmentId: 'a1',
      paths: ['/x/1.jpg', '/x/2.jpg'],
      enqueuedAtMs: 1000,
    );
    await store.add(entry);
    final loaded = await store.load();
    expect(loaded, hasLength(1));
    expect(loaded.first.appointmentId, 'a1');
    expect(loaded.first.paths, ['/x/1.jpg', '/x/2.jpg']);
    expect(loaded.first.id, 'a1_1000');
  });

  test(
    'round-trips already-uploaded images preserving the exact timestamp',
    () async {
      // Microsecond precision must survive so the arrayUnion re-link stays
      // idempotent against a Firestore Timestamp minted from the same instant.
      final uploadedAt = DateTime.utc(2026, 7, 26, 13, 45, 12, 340, 567);
      final store = PendingUploadStore();
      await store.add(
        PendingUpload(
          appointmentId: 'a1',
          paths: const [],
          enqueuedAtMs: 1000,
          uploaded: [
            AppointmentImage(
              url: 'https://example.com/1.jpg',
              storagePath: 'appointments/a1/images/1.jpg',
              fileName: '1.jpg',
              uploadedAt: uploadedAt,
            ),
          ],
        ),
      );
      final loaded = await store.load();
      expect(loaded, hasLength(1));
      expect(loaded.single.paths, isEmpty);
      final img = loaded.single.uploaded.single;
      expect(img.url, 'https://example.com/1.jpg');
      expect(img.storagePath, 'appointments/a1/images/1.jpg');
      expect(img.uploadedAt, uploadedAt);
    },
  );

  test(
    'an entry without uploaded images omits the field and loads empty',
    () async {
      final store = PendingUploadStore();
      await store.add(
        const PendingUpload(
          appointmentId: 'a1',
          paths: ['/x/1.jpg'],
          enqueuedAtMs: 1,
        ),
      );
      expect((await store.load()).single.uploaded, isEmpty);
    },
  );

  test('remove drops only the matching entry', () async {
    final store = PendingUploadStore();
    await store.add(
      const PendingUpload(
        appointmentId: 'a1',
        paths: ['/x/1.jpg'],
        enqueuedAtMs: 1,
      ),
    );
    await store.add(
      const PendingUpload(
        appointmentId: 'a1',
        paths: ['/x/2.jpg'],
        enqueuedAtMs: 2,
      ),
    );
    await store.remove('a1_1');
    final loaded = await store.load();
    expect(loaded.single.id, 'a1_2');
  });

  test('prune removes entries older than maxAge and returns them', () async {
    final store = PendingUploadStore();
    const old = PendingUpload(
      appointmentId: 'old',
      paths: ['/x/o.jpg'],
      enqueuedAtMs: 0,
    );
    final fresh = PendingUpload(
      appointmentId: 'new',
      paths: const ['/x/n.jpg'],
      enqueuedAtMs: DateTime.utc(2026, 7, 13).millisecondsSinceEpoch,
    );
    await store.add(old);
    await store.add(fresh);
    final pruned = await store.prune(now: DateTime.utc(2026, 7, 13));
    expect(pruned.single.appointmentId, 'old');
    expect((await store.load()).single.appointmentId, 'new');
  });

  test('malformed stored JSON resets to empty instead of throwing', () async {
    SharedPreferences.setMockInitialValues({
      'pending_photo_uploads': 'not-json',
    });
    final store = PendingUploadStore();
    expect(await store.load(), isEmpty);
  });

  test('an overlapping add and remove do not erase each other', () async {
    // Every other test here drives ONE mutation at a time, which is exactly
    // the shape that passed while this bug was live. `add`/`remove`/`prune`
    // are each load() -> mutate -> _save() over ONE SharedPreferences key, so
    // without `_serialized` both callers read the same list and the second
    // save wipes the first's change: a save staging a batch while a drain
    // removed a finished one wrote [E1, E2] then [], stranding E2's files
    // with no queue entry and no failure notice.
    final store = PendingUploadStore();
    const first = PendingUpload(
      appointmentId: 'a1',
      paths: ['/x/1.jpg'],
      enqueuedAtMs: 1000,
    );
    const second = PendingUpload(
      appointmentId: 'a2',
      paths: ['/x/2.jpg'],
      enqueuedAtMs: 2000,
    );
    await store.add(first);

    // Deliberately NOT awaited between the two — that interleaving is the
    // whole point.
    final adding = store.add(second);
    final removing = store.remove(first.id);
    await Future.wait([adding, removing]);

    final loaded = await store.load();
    expect(loaded.map((e) => e.appointmentId), ['a2']);
  });
}

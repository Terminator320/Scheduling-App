import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/features/calendar/data/pending_upload_store.dart';
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
}

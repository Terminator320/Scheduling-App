# Offline Mode Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Status: IMPLEMENTED 2026-07-13 — Tasks 1–6 built, all committed on branch
`notification` (analyzer clean, 834 tests green). Task 7 (airplane-mode device
pass) is the only remaining item and is device-only.**

> Adaptations from the illustrative plan: the upload service kept its existing
> named-param constructor (not the positional form sketched here) and preserves
> the too-large filename detail in the failure notice. `path_provider` was added
> as a direct dep (it was transitive-only). Controllers surface the offline case
> by returning their existing `*Failed(SocketException('offline'))` outcome — the
> widgets already route that through `composeErrorNotice`'s offline cause, so no
> new outcome types or widget changes were needed. Wave actions surface
> `WaveNetwork` (its catch uses typed `WaveFailure`, not `composeErrorNotice`).
> Callable-timeout `options:` broke every `httpsCallable('name')` test stub;
> those were migrated to `httpsCallable(any(that: equals('name')), options:
> any(named: 'options'))`.

**Goal:** Make the app degrade predictably without a network: failed appointment
photo uploads survive and retry automatically, callable-backed flows fail fast
with a clear offline message instead of hanging ~60 s, and submit buttons never
spin forever on an offline Firestore write.

**Architecture:** Build on the connectivity layer that already exists
(`connectivity_plus`, `isOfflineProvider`, `OfflineBanner` — all live in prod).
Add a SharedPreferences-backed pending-upload queue drained on reconnect, a
durable staging directory so temp files survive a failed upload, explicit
timeouts on every `httpsCallable`, and synchronous offline pre-checks at the
controller layer that reuse the existing `composeErrorNotice` offline cause.

**Tech Stack:** Flutter/Dart, Riverpod (manual providers), `connectivity_plus`
(already a dep), `shared_preferences` (already a dep), `path_provider`
(add if absent), Firebase Storage/Firestore.

---

## Context

### What already exists (do NOT rebuild)

- `connectivity_plus: ^7.2.0` is in `pubspec.yaml:85`.
- `lib/core/connectivity/connectivity_providers.dart` —
  `connectivityResultsProvider` (StreamProvider seeding `checkConnectivity()`
  then following `onConnectivityChanged`) and `isOfflineProvider`
  (`Provider<bool>`, deliberate "unknown = online" bias so the banner never
  false-flashes).
- `lib/core/connectivity/offline_banner.dart` — persistent bottom strip, wired
  in `main.dart:543` inside `MaterialApp.builder`. Test at
  `test/core/connectivity/offline_banner_test.dart`.
- Offline **classification** for errors: `lib/core/errors/error_cause.dart`
  `_classifyError` maps `FirebaseException` codes
  `unavailable`/`network-request-failed`/`deadline-exceeded`, plus
  `SocketException`/`TimeoutException`, to the offline cause.
  `composeErrorNotice(context, intro:, tag:, error:)` renders it.

### The gaps this plan closes

1. **Photo uploads are lost on failure.**
   `AppointmentImageUploadService._run`
   (`lib/features/calendar/data/appointment_image_upload_service.dart:34-62`)
   swallows errors after `_notifier.reportFailure(...)`, and `_uploadAndPatch`'s
   `finally` (lines 99-107) deletes the picker temp files **even when the upload
   failed** — a basement photo with no signal is gone.
2. **Callables hang ~60 s offline.** None of the call sites set
   `HttpsCallableOptions(timeout:)`:
   `firebase_employees_repository.dart:70,100` (invites),
   `wave_service.dart:22,49,72,99`, `google_places_repository.dart:30,60`,
   `account_deletion_service.dart:56`.
3. **Submit flows hang offline.** Awaited Firestore writes (`addAppointment`,
   client save) only complete on server ack, so an offline save leaves
   `isSubmitting` spinning indefinitely. (One step past the approved bullet
   list, but same spirit: a clear offline error instead of a hang. The write
   is NOT queued in this design — the user is told to retry online.)
4. **Firestore persistence is implicit.** Nothing in `main.dart` configures it;
   the app relies on the mobile SDK default. Make it explicit.

### Decisions made with the user (2026-07-13)

- **Practical hardening**, not offline-first: no pending-write badges, no
  conflict UX, no offline create guarantees.
- Address autocomplete gets a short timeout only, no pre-check notice
  (a per-keystroke surface must not spam notices).

---

### Task 1: Explicit Firestore persistence

**Files:**
- Modify: `lib/main.dart` (in `main()`, right after `Firebase.initializeApp(...)`)

- [ ] **Step 1: Set settings before any Firestore use**

```dart
import 'package:cloud_firestore/cloud_firestore.dart';
// ...after await Firebase.initializeApp(...):
FirebaseFirestore.instance.settings = const Settings(
  persistenceEnabled: true,
);
```

This pins today's implicit default so an SDK default-flip can never silently
remove the offline cache. Must run before the first Firestore read (it is —
`SplashScreen` reads later).

- [ ] **Step 2: Verify**

Run: `flutter analyze 2>&1 | grep -E "error -|warning -"`
Expected: no new issues.

- [ ] **Step 3: Commit**

```bash
git add lib/main.dart
git commit -m "feat: pin Firestore offline persistence explicitly"
```

---

### Task 2: `PendingUploadStore` (pure, TDD)

A SharedPreferences-backed JSON queue of photo batches awaiting upload.

**Files:**
- Create: `lib/features/calendar/data/pending_upload_store.dart`
- Test: `test/features/calendar/data/pending_upload_store_test.dart`

- [ ] **Step 1: Write the failing tests**

```dart
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
    final entry = PendingUpload(
      appointmentId: 'a1',
      paths: const ['/x/1.jpg', '/x/2.jpg'],
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
    await store.add(PendingUpload(
        appointmentId: 'a1', paths: const ['/x/1.jpg'], enqueuedAtMs: 1));
    await store.add(PendingUpload(
        appointmentId: 'a1', paths: const ['/x/2.jpg'], enqueuedAtMs: 2));
    await store.remove('a1_1');
    final loaded = await store.load();
    expect(loaded.single.id, 'a1_2');
  });

  test('prune removes entries older than maxAge and returns them', () async {
    final store = PendingUploadStore();
    final old = PendingUpload(
        appointmentId: 'old', paths: const ['/x/o.jpg'], enqueuedAtMs: 0);
    final fresh = PendingUpload(
        appointmentId: 'new',
        paths: const ['/x/n.jpg'],
        enqueuedAtMs: DateTime.utc(2026, 7, 13).millisecondsSinceEpoch);
    await store.add(old);
    await store.add(fresh);
    final pruned = await store.prune(now: DateTime.utc(2026, 7, 13));
    expect(pruned.single.appointmentId, 'old');
    expect((await store.load()).single.appointmentId, 'new');
  });

  test('malformed stored JSON resets to empty instead of throwing', () async {
    SharedPreferences.setMockInitialValues(
        {'pending_photo_uploads': 'not-json'});
    final store = PendingUploadStore();
    expect(await store.load(), isEmpty);
  });
}
```

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/features/calendar/data/pending_upload_store_test.dart`
Expected: FAIL (file/classes don't exist).

- [ ] **Step 3: Implement**

```dart
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// One queued photo batch for an appointment (staged file paths on disk).
class PendingUpload {
  const PendingUpload({
    required this.appointmentId,
    required this.paths,
    required this.enqueuedAtMs,
  });

  final String appointmentId;
  final List<String> paths;
  final int enqueuedAtMs;

  String get id => '${appointmentId}_$enqueuedAtMs';

  Map<String, dynamic> toJson() => {
    'appointmentId': appointmentId,
    'paths': paths,
    'enqueuedAtMs': enqueuedAtMs,
  };

  static PendingUpload? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final map = raw.cast<String, dynamic>();
    final appointmentId = (map['appointmentId'] ?? '').toString();
    final enqueuedAtMs = map['enqueuedAtMs'];
    final paths = map['paths'];
    if (appointmentId.isEmpty || enqueuedAtMs is! int || paths is! List) {
      return null;
    }
    return PendingUpload(
      appointmentId: appointmentId,
      paths: paths.map((p) => p.toString()).toList(),
      enqueuedAtMs: enqueuedAtMs,
    );
  }
}

/// Durable queue of photo batches that failed (or have yet) to upload.
/// JSON list under one SharedPreferences key; corrupt data resets to empty.
class PendingUploadStore {
  static const _key = 'pending_photo_uploads';
  static const _maxAge = Duration(days: 7);

  Future<List<PendingUpload>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .map(PendingUpload.fromJson)
          .whereType<PendingUpload>()
          .toList();
    } on FormatException {
      return const [];
    }
  }

  Future<void> _save(List<PendingUpload> entries) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _key, jsonEncode(entries.map((e) => e.toJson()).toList()));
  }

  Future<void> add(PendingUpload entry) async {
    final entries = await load();
    await _save([...entries, entry]);
  }

  Future<void> remove(String id) async {
    final entries = await load();
    await _save(entries.where((e) => e.id != id).toList());
  }

  /// Drops entries older than [_maxAge]; returns them so the caller can
  /// delete their staged files.
  Future<List<PendingUpload>> prune({required DateTime now}) async {
    final entries = await load();
    final cutoff = now.subtract(_maxAge).millisecondsSinceEpoch;
    final pruned = entries.where((e) => e.enqueuedAtMs < cutoff).toList();
    if (pruned.isNotEmpty) {
      await _save(entries.where((e) => e.enqueuedAtMs >= cutoff).toList());
    }
    return pruned;
  }
}
```

- [ ] **Step 4: Run tests**

Run: `flutter test test/features/calendar/data/pending_upload_store_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/calendar/data/pending_upload_store.dart test/features/calendar/data/pending_upload_store_test.dart
git commit -m "feat: pending photo-upload store"
```

---

### Task 3: Staging + retry in `AppointmentImageUploadService`

**Files:**
- Modify: `lib/features/calendar/data/appointment_image_upload_service.dart`
- Modify: `pubspec.yaml` (add `path_provider` ONLY if absent — check first;
  `flutter pub get` after a dep change needs the sandbox disabled on this box)

Behavior change:
1. `uploadInBackground` first **moves** the picker temp files into a durable
   staging dir (`<app-support>/pending_uploads/`), records a `PendingUpload`
   entry, then runs the upload unawaited (public signature unchanged — still
   sync `void`).
2. On full success → remove the entry + delete staged files.
3. On **permanent** per-file failure (`ImageUploadFailure` — bad magic bytes /
   too large) → drop that file from the entry, count it failed (existing
   `PhotoUploadNotifier.reportFailure` path unchanged).
4. On **transient** failure (anything else: network, storage) → keep the entry
   queued for `drainPending()`; still `reportFailure` so the existing failure
   UI shows.
5. New `Future<void> drainPending()` — reentrancy-guarded (`_draining` flag,
   set synchronously before the first await per the repo submit-reentrancy
   rule), prunes >7-day entries (deleting their files), retries the rest, and
   `clearFailure(appointmentId)` on a batch that fully succeeds.

- [ ] **Step 1: Restructure the service**

Key excerpts (constructor gains injectable seams for tests; defaults preserve
current call sites):

```dart
AppointmentImageUploadService(
  this._storage,
  this._appointments, {
  PhotoUploadNotifier? notifier,
  AppLogger? logger,
  PendingUploadStore? store,
  Future<Directory> Function()? stagingDirProvider,
})  : _notifier = notifier ?? PhotoUploadNotifier(),
      _logger = logger ?? AppLogger(),
      _store = store ?? PendingUploadStore(),
      _stagingDirProvider = stagingDirProvider ?? _defaultStagingDir;

static Future<Directory> _defaultStagingDir() async {
  final base = await getApplicationSupportDirectory();
  return Directory('${base.path}/pending_uploads').create(recursive: true);
}
```

Staging (rename with copy fallback — picker temps may sit on another volume):

```dart
Future<File> _stage(File source, Directory dir, int i, int enqueuedAtMs) async {
  final name = source.uri.pathSegments.isNotEmpty
      ? source.uri.pathSegments.last
      : 'photo.jpg';
  final target = File('${dir.path}/${enqueuedAtMs}_${i}_$name');
  try {
    return await source.rename(target.path);
  } on FileSystemException {
    final copied = await source.copy(target.path);
    await source.delete();
    return copied;
  }
}
```

`uploadInBackground` stages, records, then uploads:

```dart
void uploadInBackground({
  required String appointmentId,
  required List<File> newImages,
}) {
  if (newImages.isEmpty) return;
  unawaited(_stageAndRun(appointmentId, newImages));
}

Future<void> _stageAndRun(String appointmentId, List<File> images) async {
  try {
    final dir = await _stagingDirProvider();
    final enqueuedAtMs = DateTime.now().millisecondsSinceEpoch;
    final staged = <File>[];
    for (var i = 0; i < images.length; i++) {
      staged.add(await _stage(images[i], dir, i, enqueuedAtMs));
    }
    final entry = PendingUpload(
      appointmentId: appointmentId,
      paths: staged.map((f) => f.path).toList(),
      enqueuedAtMs: enqueuedAtMs,
    );
    await _store.add(entry);
    await _attempt(entry);
  } catch (e, st) {
    _notifier.reportFailure(appointmentId, failedCount: images.length);
    _logger.warn('IMG-UPLOAD staging failed for $appointmentId', e, st);
  }
}
```

`_attempt` replaces `_run`/`_uploadAndPatch` — per-file upload so permanent
failures are separable from transient ones. **The unconditional `finally`
temp-file deletion is removed**; staged files are deleted only on success or
permanent rejection:

```dart
Future<void> _attempt(PendingUpload entry) async {
  final files =
      entry.paths.map(File.new).where((f) => f.existsSync()).toList();
  if (files.isEmpty) {
    await _store.remove(entry.id);
    return;
  }
  final uploaded = <AppointmentImage>[];
  var permanentFailures = 0;
  var transientFailure = false;
  final survivors = <String>[];
  for (final file in files) {
    try {
      uploaded.add(await _storage.uploadImage(entry.appointmentId, file));
      await _deleteQuietly(file);
    } on ImageUploadFailure catch (e, st) {
      permanentFailures++;
      _logger.warn('IMG-UPLOAD rejected file for ${entry.appointmentId}', e, st);
      await _deleteQuietly(file);
    } catch (e, st) {
      transientFailure = true;
      survivors.add(file.path);
      _logger.warn('IMG-UPLOAD transient failure for ${entry.appointmentId}', e, st);
    }
  }
  if (uploaded.isNotEmpty) {
    await _appointments.appendAppointmentPictures(entry.appointmentId, uploaded);
  }
  if (transientFailure) {
    await _store.remove(entry.id);
    await _store.add(PendingUpload(
      appointmentId: entry.appointmentId,
      paths: survivors,
      enqueuedAtMs: entry.enqueuedAtMs,
    ));
    _notifier.reportFailure(entry.appointmentId, failedCount: survivors.length);
  } else {
    await _store.remove(entry.id);
    if (permanentFailures > 0) {
      _notifier.reportFailure(entry.appointmentId,
          failedCount: permanentFailures);
    } else {
      _notifier.clearFailure(entry.appointmentId);
    }
  }
}
```

(`appendAppointmentPictures` already arrayUnions, so a partial batch that
retries later can never clobber the first half. Re-adding under the same
`enqueuedAtMs` keeps the entry's age for pruning — a batch never retries past
7 days.)

`drainPending`:

```dart
bool _draining = false;

Future<void> drainPending() async {
  if (_draining) return;
  _draining = true;
  try {
    final expired = await _store.prune(now: DateTime.now());
    for (final e in expired) {
      for (final p in e.paths) {
        await _deleteQuietly(File(p));
      }
    }
    for (final entry in await _store.load()) {
      await _attempt(entry);
    }
  } catch (e, st) {
    _logger.warn('IMG-UPLOAD drain failed', e, st);
  } finally {
    _draining = false;
  }
}

Future<void> _deleteQuietly(File f) async {
  try {
    await f.delete();
  } catch (e, st) {
    _logger.warn('IMG-UPLOAD cleanup failed for ${f.path}', e, st);
  }
}
```

- [ ] **Step 2: Tests**

Method-channel storage means no full unit test (repo policy — same as
`ImageStorageService`), but the pure decision seams ARE testable with a fake
`stagingDirProvider` pointing at a temp dir and a mocktail `ImageStorageService`:
add `test/features/calendar/data/appointment_image_upload_service_test.dart`
covering: transient failure keeps a surviving entry with only unsent paths;
`ImageUploadFailure` drops the file and the entry; success clears the failure
in the notifier; `drainPending` is reentrancy-safe (second call during first is
a no-op). Remember `(captured as Map).cast<String, dynamic>()` for captures
and pass all optional ctor deps explicitly.

- [ ] **Step 3: Run**

Run: `flutter test test/features/calendar/data/` and
`flutter analyze 2>&1 | grep -E "error -|warning -"`
Expected: PASS / clean.

- [ ] **Step 4: Commit**

```bash
git add -A lib/features/calendar/data pubspec.yaml pubspec.lock test/features/calendar/data
git commit -m "feat: durable retry queue for appointment photo uploads"
```

---

### Task 4: Drain triggers in `main.dart`

**Files:**
- Modify: `lib/main.dart` (`_PaulAppState`)

- [ ] **Step 1: Add a listener following the `_listenForPushRegistration` pattern**

Called from `build()` beside the existing five listeners (main.dart:495-499):

```dart
void _listenForUploadDrain() {
  // Reconnect: drain queued photo batches once per offline→online flip.
  ref.listen<bool>(isOfflineProvider, (previous, next) {
    if (previous == true && !next && _isSignedIn) {
      unawaited(ref.read(appointmentImageUploadProvider).drainPending());
    }
  });
  // Startup / sign-in: one drain when the account doc first arrives.
  ref.listen<AsyncValue<Map<String, dynamic>>>(currentUserDocProvider,
      (previous, next) {
    final wasEmpty = previous?.value?.isEmpty ?? true;
    final hasDoc = next.value?.isNotEmpty ?? false;
    if (wasEmpty && hasDoc) {
      unawaited(ref.read(appointmentImageUploadProvider).drainPending());
    }
  });
}
```

(`_isSignedIn` = `ref.read(currentUserDocProvider).value?.isNotEmpty ?? false`
inline — Storage rules need an authed user; a signed-out drain would just fail
and re-queue, but skipping it avoids noise.)

- [ ] **Step 2: Verify + commit**

Run: `flutter analyze 2>&1 | grep -E "error -|warning -"` → clean.

```bash
git add lib/main.dart
git commit -m "feat: drain pending photo uploads on reconnect and sign-in"
```

---

### Task 5: Callable timeouts + offline pre-checks

**Files:**
- Modify: `lib/features/employees/data/firebase_employees_repository.dart:70,100`
- Modify: `lib/features/wave/data/wave_service.dart:22,49,72,99`
- Modify: `lib/features/maps/data/google_places_repository.dart:30,60`
- Modify: `lib/features/auth/services/account_deletion_service.dart:56`
- Modify: the widgets/controllers that trigger invites, Wave actions, and
  account deletion (pre-checks live at the UI layer where `ref` and l10n live)

- [ ] **Step 1: Timeouts on every callable**

At each `httpsCallable('name')` call site add options — e.g.:

```dart
_functions.httpsCallable(
  'createEmployeeInvite',
  options: HttpsCallableOptions(timeout: const Duration(seconds: 20)),
)
```

Durations: invites/Wave 20 s, `deleteAccount` 30 s (does more work),
`placesAutocomplete`/`placesGetDetails` 10 s (interactive surface). A timeout
surfaces as `deadline-exceeded`, which every existing mapper already treats as
network/offline (`error_cause.dart`, `WaveErrorMapper`, `MapsErrorMapper`) —
no new failure variants needed.

- [ ] **Step 2: Synchronous pre-checks at the action sites**

At each user-triggered callable action (invite create, Wave
connect/import/schedule, account deletion) — BEFORE the busy flag is set:

```dart
if (ref.read(isOfflineProvider)) {
  ref.read(noticeServiceProvider).error(composeErrorNotice(
        context,
        intro: /* the SAME intro this site's catch already uses */,
        tag: /* the SAME tag this site's catch already uses */,
        error: const SocketException('offline'),
      ));
  return;
}
```

The synthetic `SocketException` routes `composeErrorNotice` to its existing
offline cause — no new l10n keys, and the notice matches what the catch block
would eventually have shown. Deliberately NOT added to address autocomplete
(per-keystroke; the 10 s timeout + silent empty result is the right UX).

- [ ] **Step 3: Verify + commit**

Run `flutter analyze` filter + the touched features' tests
(`flutter test test/features/employees test/features/wave test/features/maps`).

```bash
git add -A lib
git commit -m "feat: callable timeouts and offline pre-checks"
```

---

### Task 6: Submit-flow offline guards

**Files:**
- Modify: `lib/features/calendar/application/add_event_controller.dart` (submit)
- Modify: `lib/features/calendar/application/event_details_controller.dart` (save)
- Modify: `lib/features/clients/application/client_form_controller.dart` (addClient/updateClient)

- [ ] **Step 1: Guard each submit**

Same pattern as Task 5 Step 2, synchronously at the top of each submit/save
(before the `isSubmitting`/`isSaving` flag per the reentrancy rule — the guard
returns, so the flag is never left set), reusing each site's existing
intro/tag (APPT-CREATE, APPT-SAVE, CLI-ADD, CLI-SAVE). Rationale: an awaited
Firestore write offline resolves only on server ack, so without the guard the
button spins until reconnect.

- [ ] **Step 2: Tests**

Extend the existing controller tests: with a ProviderContainer overriding
`isOfflineProvider` to `true`, submit → repository never called, a notice was
pushed, `isSubmitting` stays false. (Override:
`isOfflineProvider.overrideWithValue(true)`.)

- [ ] **Step 3: Verify + commit**

Run: `flutter test test/features/calendar test/features/clients` → PASS.

```bash
git add -A lib test
git commit -m "feat: offline guards on appointment and client submit flows"
```

---

### Task 7: Device verification (airplane mode pass)

No code. On the Android dev device (`net.vogas.scheduling`):

- [ ] Airplane mode ON → calendar / clients / employees show cached data + the
  offline banner; no spinners hang, no crash.
- [ ] Create an appointment with photos while offline → clear offline notice,
  button re-enabled (no stuck spinner), no orphan write.
- [ ] Take photos on an ONLINE save, kill connectivity mid-upload → failure
  notice; restore connectivity → photos appear on the appointment without
  reopening the app (drain on reconnect); temp files gone afterwards.
- [ ] Invite / Wave import / delete-account tapped offline → immediate offline
  notice, no 60 s hang.
- [ ] Address autocomplete offline → silently no suggestions, no notice spam.
- [ ] Kill the app with a queued upload, relaunch online → drain on sign-in
  emission uploads it.

## Failure guarantees

| Failure | Behavior |
|---|---|
| Upload fails mid-batch (network) | Uploaded half is arrayUnioned; survivors stay queued under the same entry age |
| Invalid image (magic bytes) queued | Dropped permanently, counted in the failure notice, file deleted — never retried |
| Queue entry older than 7 days | Pruned on next drain, staged files deleted |
| Corrupt SharedPreferences JSON | Store resets to empty (fails open, logs nothing user-facing) |
| Drain re-entered (reconnect flaps) | `_draining` flag → second call no-ops |
| Callable invoked offline | Pre-check notice (interactive flows) or ≤10-30 s `deadline-exceeded` → existing offline cause |

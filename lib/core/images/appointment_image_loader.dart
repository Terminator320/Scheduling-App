import 'dart:async';
import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/images/appointment_image_disk_cache.dart';
import 'package:scheduling/core/images/image_storage_service.dart';
import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_image.dart';

/// App-wide loader, injectable so widget tests never touch Storage.
final appointmentImageLoaderProvider = Provider<AppointmentImageLoader>(
  (ref) => AppointmentImageLoader(logger: ref.watch(loggerProvider)),
);

/// Fetches an appointment photo's BYTES from Storage, for rendering in memory.
///
/// **No renderable URL is ever produced ON THE RENDER PATH, and that is the
/// point — but be precise about how far it goes.**
/// `getDownloadURL()` mints a `?alt=media&token=…` URL whose
/// `firebaseStorageDownloadTokens` value is stable per object and never
/// expires; fetching it serves the bytes over plain HTTPS with **no auth and
/// no rules evaluation**. Its predecessor resolved that URL at render time,
/// which put `storage.rules` in front of the MINT — but handed back the same
/// permanent string every time, so a URL rendered while an employee was active
/// sat in the on-disk image cache and kept working for anyone holding it long
/// after `deactivateEmployee` revoked their credential. `getData()` is an
/// authenticated SDK call: `storage.rules` is evaluated on **every fetch**,
/// and a refused reader gets nothing.
///
/// Nothing mints one any more. The CONTRACT step deleted `downloadUrlFor`,
/// `uploadImage` persists a `storagePath` alone, and no write path in the app
/// produces a token URL — so this class is no longer working against a supply
/// of them.
///
/// **And as of 2026-08-22 there is nothing shareable left to capture either.**
/// This paragraph used to say the opposite, because LEGACY rows could still
/// carry a `url` with no `storagePath` — a rules-free, non-expiring,
/// transferable download link that an assigned employee could read straight
/// out of the image document, with the rotation that once invalidated it on
/// deactivation deleted alongside the minting machinery. The open question was
/// only how many survived in prod, and the answer came back **zero**
/// (`functions/scripts/count-legacy-image-urls.js`: 14 image documents
/// scanned, 0 with a url and no storagePath). So the three things that kept
/// the field alive went with it: `firestore.rules` no longer accepts `url`,
/// `AppointmentImagesStore` no longer writes it, and the `refFromURL` fallback
/// below is gone. An entry reaching here without a `storagePath` now has no
/// handle at all and loads as empty bytes rather than through a permanent
/// link.
///
/// If a url-only row is ever reintroduced, re-home its bytes under a real
/// `storagePath` — do not re-add the field to make the write pass.
///
/// **Photos render offline again, and that was never in tension with the
/// above.** `cached_network_image` cached BYTES too; what made it unacceptable
/// was the handle it cached them against — a permanent, rules-free token URL.
/// [AppointmentImageDiskCache] keys on `storagePath` instead and stores nothing
/// shareable, so the on-disk cache is back without the leak. Two caches, two
/// jobs: the session map below keeps the fetch from being paid per widget
/// State (every sheet open, and again on every View→Edit toggle), and the disk
/// cache keeps it from being paid per SESSION — which is what a tech in a
/// basement or an underground garage actually needs.
///
/// Be precise about the residual: a cache HIT of either kind is not
/// rules-evaluated, so bytes fetched while entitled stay renderable on that
/// device until they are evicted or [clear] runs. That is the accepted cost,
/// and it is why [clear] is wired into `deregisterThisDevice`.
///
/// A doc written before `storagePath` was stored has only its `url`, so that
/// URL is unavoidably the handle — but it is resolved back to a `Reference`
/// via `refFromURL` and fetched through the SDK like any other, so even the
/// legacy path is rules-evaluated and never hands the token URL to the network
/// stack. That fallback is why this is not a migration.
class AppointmentImageLoader {
  AppointmentImageLoader({
    FirebaseStorage? storage,
    AppLogger? logger,
    AppointmentImageDiskCache? diskCache,
  }) : _injectedStorage = storage,
       _logger = logger ?? AppLogger(),
       _disk = diskCache ?? AppointmentImageDiskCache(logger: logger);

  /// Session-scoped, keyed by `storagePath`. The provider is a singleton, so
  /// this survives a sheet close — the fetch is otherwise paid per widget
  /// State, i.e. on every sheet open AND again on every View→Edit toggle.
  ///
  /// An EMPTY result is **never cached**: a rules refusal must not outlive a
  /// change of entitlement, and a transport failure must not outlive the
  /// network coming back.
  final Map<String, Future<Uint8List>> _cache = {};

  /// Sizes of the entries in [_cache] that have settled, in insertion order,
  /// so the cache can be trimmed oldest-first when it outgrows its budget.
  final Map<String, int> _sizes = {};
  int _cachedBytes = 0;

  /// Fetches at most this many photos at once, so opening a job with a long
  /// strip doesn't fire the whole batch at Storage in one burst.
  static const int _maxConcurrentLoads = 4;

  /// Holding bytes for the session is only safe if it is bounded — a session
  /// that opens fifty jobs would otherwise retain every photo of every one of
  /// them.
  static const int _maxCachedBytes = 24 * 1024 * 1024;

  /// The upload cap IS the ceiling: nothing this app wrote can be larger, and
  /// `getData` needs an explicit bound.
  static const int _maxImageBytes = ImageStorageService.maxUploadBytes;

  /// Resolved LAZILY, on the first fetch.
  ///
  /// `FirebaseStorage.instance` throws without an initialized app, and this
  /// provider is now touched by `deregisterThisDevice` — which every widget
  /// test covering sign-out builds — purely to [clear] the cache. Constructing
  /// the singleton there would make forgetting the session require Firebase.
  FirebaseStorage get _storage => _injectedStorage ?? FirebaseStorage.instance;

  final FirebaseStorage? _injectedStorage;
  final AppLogger _logger;
  final AppointmentImageDiskCache _disk;

  /// The photo's bytes, or an EMPTY list when there are none to render — a
  /// rules refusal, a transport failure, or a legacy entry with no usable
  /// handle. Callers must treat empty as a refusal (error tile, untappable),
  /// never as a pending load.
  Future<Uint8List> load(AppointmentImage image) {
    final key = _cacheKeyFor(image);
    // Nothing to fetch and nothing to key on.
    if (key.isEmpty) return Future.value(Uint8List(0));

    final cached = _cache[key];
    if (cached != null) return cached;

    final pending = _resolve(image, key);
    _cache[key] = pending;
    unawaited(pending.then((bytes) => _settle(key, pending, bytes)));
    return pending;
  }

  /// Disk first, then the network — and the network result is written back.
  ///
  /// The disk write is deliberately NOT awaited: it is a cache fill, so making
  /// the photo wait on it would put a file write (and the eviction sweep behind
  /// it) in front of every first render. [AppointmentImageDiskCache] serializes
  /// its own mutations and drops a write whose session has already ended, so
  /// nothing here needs to sequence it.
  Future<Uint8List> _resolve(AppointmentImage image, String key) async {
    final onDisk = await _disk.read(key);
    if (onDisk != null) return onDisk;

    // Read BEFORE the fetch: a sign-out during the round trip bumps the
    // generation, and this is the value that lets the write-back notice.
    final generation = _disk.generation;
    final bytes = await _fetch(() => _refFor(image), key);
    // An EMPTY result is a refusal or a transport failure. Caching either one
    // would outlive the thing that caused it — a change of entitlement, or the
    // network coming back — so neither store keeps it.
    if (bytes.isNotEmpty) {
      unawaited(_disk.write(key, bytes, generation: generation));
    }
    return bytes;
  }

  /// The cache key for [image], or `''` when it carries no usable handle.
  ///
  /// `storagePath` is the only handle a photo has, so it is the only key.
  ///
  /// There used to be a `url:`-prefixed second key space for legacy url-only
  /// entries. Both it and the `refFromURL` fetch below went on 2026-08-22,
  /// when a prod count found zero such documents and `firestore.rules` stopped
  /// accepting the field — an entry that reaches here without a
  /// `storagePath` now has no handle at all, which `_fetch` reports rather
  /// than silently rendering from a permanent rules-free link.
  static String _cacheKeyFor(AppointmentImage image) => image.storagePath;

  Reference _refFor(AppointmentImage image) => _storage.ref(image.storagePath);

  /// Fetches in list order so the returned bytes line up index-for-index with
  /// [images] — the viewer opens at a tapped index, so a reordered result
  /// would open the wrong photo.
  Future<List<Uint8List>> loadAll(List<AppointmentImage> images) async {
    final loaded = <Uint8List>[];
    for (var i = 0; i < images.length; i += _maxConcurrentLoads) {
      final end = i + _maxConcurrentLoads;
      final batch = images.sublist(
        i,
        end < images.length ? end : images.length,
      );
      loaded.addAll(await Future.wait(batch.map(load)));
    }
    return loaded;
  }

  /// Forgets every cached photo, in memory and on disk.
  ///
  /// Called from the account-exit teardown, which is the single owner of
  /// "forget this session". The provider is a process-lifetime singleton, so
  /// without this up to 24 MB of one user's photo bytes stays resident in the
  /// heap across sign-out into the next user's session on a shared device.
  /// That is not a rules bypass — serving them still requires the next user
  /// to be entitled to the same `storagePath` — but it is memory-forensics
  /// exposure, and it was the one thing `AccountExitListeners` did not
  /// tear down.
  ///
  /// The DISK half raises the stakes: those bytes outlive the process
  /// entirely, so a shared handset would otherwise hand the next person every
  /// job photo the last one opened. The memory clear happens first and
  /// synchronously — it cannot fail, and the awaited disk delete must not
  /// delay it.
  Future<void> clear() async {
    _cache.clear();
    _sizes.clear();
    _cachedBytes = 0;
    await _disk.clear();
  }

  /// [refOf] is a thunk because `refFromURL` parses, and therefore throws, on
  /// a URL Storage doesn't own — which has to be caught here like any other
  /// failure rather than escaping to the caller as a broken future.
  Future<Uint8List> _fetch(Reference Function() refOf, String label) async {
    try {
      return await refOf().getData(_maxImageBytes) ?? Uint8List(0);
    } catch (e, st) {
      // A RULES REJECTION MUST NOT FALL BACK. Its predecessor's `catch`
      // returned the stored `url` — a permanent, rules-free token link — in
      // exactly the case it existed to refuse. Nothing here can fall back to a
      // URL because nothing here produces one; the branch survives so the log
      // still says which of the two happened, and neither result is cached.
      _logger.warn(
        _isRefusal(e)
            ? 'IMG-LOAD refused by storage.rules: $label'
            : 'IMG-LOAD failed: $label',
        e,
        st,
      );
      return Uint8List(0);
    }
  }

  static bool _isRefusal(Object error) {
    if (error is! FirebaseException) return false;
    return error.code == 'unauthorized' || error.code == 'permission-denied';
  }

  void _settle(String path, Future<Uint8List> pending, Uint8List bytes) {
    if (!identical(_cache[path], pending)) return;
    if (bytes.isEmpty) {
      _cache.remove(path);
      return;
    }
    _sizes[path] = bytes.length;
    _cachedBytes += bytes.length;
    // Checked BEFORE the key copy, which is the overwhelmingly common path:
    // the budget only binds once a session has opened a lot of photos, and
    // `_sizes.keys.toList()` above the test copied the whole key list on every
    // single photo load to usually evict nothing.
    if (_cachedBytes <= _maxCachedBytes) return;
    for (final oldest in _sizes.keys.toList()) {
      if (_cachedBytes <= _maxCachedBytes) break;
      _cachedBytes -= _sizes.remove(oldest) ?? 0;
      _cache.remove(oldest);
    }
  }
}

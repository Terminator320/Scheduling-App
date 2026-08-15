import 'dart:async';
import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/images/image_storage_service.dart';
import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_image.dart';

/// App-wide loader, injectable so widget tests never touch Storage.
final appointmentImageLoaderProvider = Provider<AppointmentImageLoader>(
  (ref) => AppointmentImageLoader(logger: ref.watch(loggerProvider)),
);

/// Fetches an appointment photo's BYTES from Storage, for rendering in memory.
///
/// **No renderable URL is ever produced, and that is the whole point.**
/// `getDownloadURL()` mints a `?alt=media&token=…` URL whose
/// `firebaseStorageDownloadTokens` value is stable per object and never
/// expires; fetching it serves the bytes over plain HTTPS with **no auth and
/// no rules evaluation**. Its predecessor resolved that URL at render time,
/// which put `storage.rules` in front of the MINT — but handed back the same
/// permanent string every time, so a URL rendered while an employee was active
/// sat in the on-disk image cache and kept working for anyone holding it long
/// after `deactivateEmployee` revoked their credential. `getData()` is an
/// authenticated SDK call: `storage.rules` is evaluated on **every fetch**,
/// there is nothing shareable to capture, and a refused reader gets nothing.
///
/// The cost, accepted by the owner: this loses `cached_network_image`'s
/// on-disk byte cache, so photos re-download once per session and do not
/// render at all offline. The session cache below is what keeps that from
/// being paid per widget State.
///
/// A doc written before `storagePath` was stored has only its `url`, so that
/// URL is unavoidably the handle — but it is resolved back to a `Reference`
/// via `refFromURL` and fetched through the SDK like any other, so even the
/// legacy path is rules-evaluated and never hands the token URL to the network
/// stack. That fallback is why this is not a migration.
class AppointmentImageLoader {
  AppointmentImageLoader({FirebaseStorage? storage, AppLogger? logger})
    : _storage = storage ?? FirebaseStorage.instance,
      _logger = logger ?? AppLogger();

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

  final FirebaseStorage _storage;
  final AppLogger _logger;

  /// The photo's bytes, or an EMPTY list when there are none to render — a
  /// rules refusal, a transport failure, or a legacy entry with no usable
  /// handle. Callers must treat empty as a refusal (error tile, untappable),
  /// never as a pending load.
  Future<Uint8List> load(AppointmentImage image) {
    final path = image.storagePath;
    // Two legacy docs share the empty storagePath, so caching under it would
    // serve the first one's bytes for the second.
    if (path.isEmpty) return _loadLegacy(image);

    final cached = _cache[path];
    if (cached != null) return cached;

    final pending = _fetch(() => _storage.ref(path), path);
    _cache[path] = pending;
    unawaited(pending.then((bytes) => _settle(path, pending, bytes)));
    return pending;
  }

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

  Future<Uint8List> _loadLegacy(AppointmentImage image) {
    if (image.url.isEmpty) return Future.value(Uint8List(0));
    return _fetch(() => _storage.refFromURL(image.url), image.url);
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
    for (final oldest in _sizes.keys.toList()) {
      if (_cachedBytes <= _maxCachedBytes) break;
      _cachedBytes -= _sizes.remove(oldest) ?? 0;
      _cache.remove(oldest);
    }
  }
}

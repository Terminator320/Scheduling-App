import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import 'package:scheduling/core/logging/app_logger.dart';

/// Holds fetched photo bytes on disk, so a photo rendered once renders again
/// with no network at all.
///
/// **Why this is not the thing the render-from-bytes change removed.**
/// `cached_network_image` cached bytes too; what made it unacceptable was the
/// HANDLE — a permanent `?alt=media&token=…` URL that reads with no auth and no
/// rules evaluation, is trivially copyable, and keeps working for anyone
/// holding it after `deactivateEmployee` has revoked the credential. Nothing
/// here produces or stores a URL. The key is the `storagePath`, the bytes were
/// obtained through an authenticated, rules-evaluated `getData()`, and the file
/// is readable only by this app's sandbox.
///
/// **What it does cost, stated plainly.** A disk HIT is not rules-evaluated,
/// exactly as a session-cache hit is not today — so bytes an employee was
/// entitled to when they fetched them stay renderable on that device after the
/// entitlement is revoked, until the entry is evicted or the session is
/// forgotten. That is why [clear] is wired into `deregisterThisDevice`, the
/// single owner of "forget this session", and why the cache lives in the
/// platform CACHE directory: iOS excludes it from device and iCloud backups, so
/// job photos never leave the handset the way the Keychain rule already keeps
/// the cached identity out of backups.
///
/// **Entries never need revalidating.** `ImageStorageService.uploadImage`
/// composes every file name from `DateTime.now()`, so a `storagePath` is
/// written exactly once and never overwritten — the bytes at a given key cannot
/// change. A rotated download token mints a different URL, so a legacy
/// (`url:`-keyed) entry simply becomes unreachable and ages out.
///
/// Every operation is best-effort: a disk failure degrades to a cache miss and
/// a log, never to a photo that fails to render.
class AppointmentImageDiskCache {
  AppointmentImageDiskCache({
    Future<Directory> Function()? directory,
    AppLogger? logger,
    int? budgetBytes,
  }) : _resolveRoot = directory ?? _platformCacheDirectory,
       _logger = logger ?? AppLogger(),
       _budget = budgetBytes ?? maxCachedBytes;

  /// Sized for the job at hand rather than for a media app: a 1600×1600 JPEG at
  /// quality 70 lands around 300 KB, so this holds roughly four hundred photos
  /// — far more than the handful of jobs a tech revisits in a day, and small
  /// enough that the OS is unlikely to reclaim it under storage pressure.
  static const int maxCachedBytes = 128 * 1024 * 1024;

  /// Kept in its own subdirectory so [clear] is one recursive delete rather
  /// than a filtered sweep of a directory other things also write to.
  static const String _folder = 'appointment_images';

  final Future<Directory> Function() _resolveRoot;
  final AppLogger _logger;
  final int _budget;

  Future<Directory>? _root;

  /// Resolves once every queued mutation has run.
  ///
  /// The loader fills this cache with an UNAWAITED write, deliberately — a
  /// cache fill must not sit in front of the first render. That leaves a test
  /// with nothing to await, and "pump a few event-loop turns and hope" is the
  /// shape of a flaky test. This is the same chain [_serialized] already
  /// maintains, exposed so a test can be deterministic about it.
  Future<void> get settled => _mutations;

  /// Serializes every mutation, the same discipline as `PendingUploadStore`.
  ///
  /// Writes trim the directory to [maxCachedBytes], so two overlapping writes
  /// would each list the folder, each decide the same files were oldest, and
  /// each try to delete them — and a [clear] racing a write would leave the
  /// write's file behind, which is the one outcome "forget this session" may
  /// not produce.
  Future<void> _mutations = Future<void>.value();

  /// Bumped by [clear]. A fetch already in flight when the session ends
  /// resolves AFTERWARDS, so without this its write lands on a cache that was
  /// just emptied and one user's photos outlive their sign-out on a shared
  /// device — the exact leak [clear] exists to prevent.
  int _generation = 0;

  /// The folder's size in bytes, or `null` when no sweep has measured it yet.
  ///
  /// Only ever read and written from inside [_serialized], so it cannot be
  /// observed mid-mutation; `null` forces the next write to measure, which is
  /// what bounds how far it can drift LOW (drifting HIGH only buys a sweep
  /// that evicts nothing).
  int? _bytesOnDisk;

  static Future<Directory> _platformCacheDirectory() =>
      getApplicationCacheDirectory();

  /// A filesystem-safe, fixed-length, collision-free name for [key].
  ///
  /// Hashed rather than encoded because the keys are neither: a `storagePath`
  /// carries `/`, and a legacy `url:` key can run past the 255-character file
  /// name limit once escaped. Serving one photo's bytes for another is the
  /// failure this whole area keeps being bitten by, so the name has to be
  /// injective in practice, not merely tidy.
  static String fileNameFor(String key) =>
      sha256.convert(utf8.encode(key)).toString();

  /// The bytes cached for [key], or `null` when there are none.
  ///
  /// Never returns an empty list: a zero-length file is a half-written entry,
  /// and the caller reads empty as a REFUSAL rather than a miss.
  Future<Uint8List?> read(String key) async {
    if (key.isEmpty) return null;
    try {
      final file = await _fileFor(key);
      final bytes = await file.readAsBytes();
      return bytes.isEmpty ? null : bytes;
    } on PathNotFoundException {
      // The ordinary miss — a photo not cached yet is not a fault, and asking
      // `exists()` first would pay a second syscall to learn what the read
      // already tells us.
      return null;
    } catch (e, st) {
      _logger.warn('IMG-DISK read failed: $key', e, st);
      return null;
    }
  }

  /// The current session's cache generation, bumped by [clear].
  ///
  /// Read this where a fetch STARTS and hand it back to [write], so a write
  /// whose session ended mid-flight is dropped. Capturing it inside [write]
  /// instead is a no-op for that case: the loader only calls `write` after the
  /// Storage fetch resolves, by which point the captured value already equals
  /// the current one and the bytes land on disk — where they outlive the
  /// process, on a shared handset, for whoever signs in next.
  int get generation => _generation;

  /// Stores [bytes] for [key], trimming the folder when it may be over budget.
  ///
  /// Empty bytes are never written — see the refusal rule on
  /// `AppointmentImageLoader`. [generation] is the value read when the fetch
  /// behind these bytes started; the write is dropped if [clear] has run since.
  /// It is REQUIRED rather than defaulted to [generation] because a default is
  /// always the current value, which always passes the staleness check — the
  /// one caller that forgot the argument would silently get no guard at all.
  Future<void> write(String key, Uint8List bytes, {required int generation}) {
    if (key.isEmpty || bytes.isEmpty) return Future<void>.value();
    final startedAt = generation;
    return _serialized(() async {
      // The session ended while the fetch behind this was still in flight.
      if (startedAt != _generation) return;
      final file = await _fileFor(key);
      await file.parent.create(recursive: true);
      // Written beside the target and renamed, so a kill mid-write leaves a
      // stray temp file rather than a truncated entry under a real key — which
      // `read` could not tell from a genuinely small photo.
      final temp = File('${file.path}.part');
      await temp.writeAsBytes(bytes, flush: true);
      await temp.rename(file.path);
      // A sweep stats every file in the folder, so it is paid only when the
      // running total says the budget could be breached — a ten-photo strip
      // otherwise queues ten full sweeps to evict nothing. The total is
      // re-seeded from every sweep, and forgotten by [clear] and by a failed
      // directory resolve, so drift (the OS prunes the platform cache folder
      // behind us) costs at most one unnecessary sweep.
      final known = _bytesOnDisk;
      _bytesOnDisk = known == null || known + bytes.length > _budget
          ? await _trim()
          : known + bytes.length;
    }, 'write $key');
  }

  /// Deletes every cached photo.
  ///
  /// Wired into `deregisterThisDevice`: these bytes outlive the process, so
  /// without this one user's job photos stay on a shared device and render for
  /// whoever signs in next.
  Future<void> clear() {
    _generation += 1;
    return _serialized(() async {
      _bytesOnDisk = null;
      final dir = await _directory();
      // Sync existence/metadata checks throughout: they are single cheap
      // syscalls, and `avoid_slow_async_io` is right that the async forms cost
      // more than they save. The BYTES still move asynchronously.
      if (dir.existsSync()) await dir.delete(recursive: true);
    }, 'clear');
  }

  Future<void> _serialized(Future<void> Function() run, String label) {
    final next = _mutations.then((_) => run()).catchError((
      Object e,
      StackTrace st,
    ) {
      // Best-effort by contract, and swallowed HERE so one failure cannot
      // break the chain for every mutation queued behind it.
      _logger.warn('IMG-DISK $label failed', e, st);
    });
    _mutations = next;
    return next;
  }

  Future<Directory> _directory() {
    return _root ??= _resolveRoot()
        .then(
          (root) => Directory('${root.path}${Platform.pathSeparator}$_folder'),
        )
        .onError<Object>((e, st) {
          // A rejected memo is STICKY: every later call would return this same
          // failed future, so one transient hiccup at launch would silently
          // disable offline photos for the rest of the process. Forget it and
          // let the next fetch resolve the directory again.
          _root = null;
          // The next resolve may land somewhere else entirely, so the measured
          // size no longer describes anything.
          _bytesOnDisk = null;
          Error.throwWithStackTrace(e, st);
        });
  }

  Future<File> _fileFor(String key) async {
    final dir = await _directory();
    return File('${dir.path}${Platform.pathSeparator}${fileNameFor(key)}');
  }

  /// Evicts oldest-first until the folder is inside its budget, and returns the
  /// bytes it holds afterwards — the only measurement [_bytesOnDisk] trusts.
  ///
  /// Ordered by last-modified, i.e. by INSERTION, not by use — the same
  /// tradeoff the in-memory cache makes one level up, and for the same reason:
  /// touching a file on every render turns each cache hit into a write.
  Future<int> _trim() async {
    final dir = await _directory();
    if (!dir.existsSync()) return 0;

    final entries = <({File file, int size, DateTime modified})>[];
    var total = 0;
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final stat = entity.statSync();
      total += stat.size;
      entries.add((file: entity, size: stat.size, modified: stat.modified));
    }
    if (total <= _budget) return total;

    entries.sort((a, b) => a.modified.compareTo(b.modified));
    for (final entry in entries) {
      if (total <= _budget) break;
      try {
        await entry.file.delete();
        total -= entry.size;
      } catch (e, st) {
        // One undeletable file must not strand the rest of the eviction.
        _logger.warn('IMG-DISK evict failed: ${entry.file.path}', e, st);
      }
    }
    return total;
  }
}

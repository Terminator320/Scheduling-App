import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'package:scheduling/core/images/appointment_image_url_resolver.dart';
import 'package:scheduling/core/images/image_storage_service.dart';
import 'package:scheduling/core/images/image_upload_failure.dart';
import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/features/calendar/application/appointments_providers.dart';
import 'package:scheduling/features/calendar/application/photo_upload_notifier.dart';
import 'package:scheduling/features/calendar/data/pending_upload_store.dart';
import 'package:scheduling/features/calendar/domain/appointments_repository.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_image.dart';

class AppointmentImageUploadService {
  AppointmentImageUploadService({
    required AppointmentsRepository appointments,
    required PhotoUploadNotifier notifier,
    ImageStorageService? storage,
    AppLogger? logger,
    PendingUploadStore? store,
    AppointmentImageUrlResolver? urlResolver,
    Future<Directory> Function()? stagingDirProvider,
  }) : _appointments = appointments,
       _notifier = notifier,
       _storage = storage ?? ImageStorageService(),
       _logger = logger ?? AppLogger(),
       _store = store ?? PendingUploadStore(),
       _injectedUrlResolver = urlResolver,
       _stagingDirProvider = stagingDirProvider ?? _defaultStagingDir;

  final AppointmentsRepository _appointments;
  final PhotoUploadNotifier _notifier;
  final ImageStorageService _storage;
  final AppLogger _logger;
  final PendingUploadStore _store;

  /// Constructed LAZILY, not defaulted in the initializer list: the default
  /// resolves `FirebaseStorage.instance`, which throws without a Firebase app,
  /// and this service is otherwise constructible in a plain unit test. The
  /// carried-url path is the only thing that touches it, and a test exercising
  /// that path injects one.
  final AppointmentImageUrlResolver? _injectedUrlResolver;
  AppointmentImageUrlResolver? _resolvedUrlResolver;
  AppointmentImageUrlResolver get _urlResolver =>
      _injectedUrlResolver ??
      (_resolvedUrlResolver ??= AppointmentImageUrlResolver());

  final Future<Directory> Function() _stagingDirProvider;

  bool _draining = false;

  /// Set when a drain is requested while one is already running, so the
  /// in-flight pass just loops again instead of two drains running at once.
  bool _pendingDrain = false;

  static Future<Directory> _defaultStagingDir() async {
    final base = await getApplicationSupportDirectory();
    return Directory('${base.path}/pending_uploads').create(recursive: true);
  }

  /// Stages the files, records them, and kicks off the upload in the
  /// background — this doesn't wait for any of that to finish.
  void uploadInBackground({
    required String appointmentId,
    required List<File> newImages,
  }) {
    if (newImages.isEmpty) return;
    unawaited(_stageAndRun(appointmentId, List.of(newImages)));
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
      // Drain runs serialized so we don't end up uploading the same batch
      // twice under two different sets of staged paths.
      await drainPending();
    } catch (e, st) {
      _notifier.reportFailure(appointmentId, failedCount: images.length);
      _logger.warn('IMG-UPLOAD staging failed for $appointmentId', e, st);
    }
  }

  /// Moves the temp file into the staging dir. If that's a cross-device
  /// move (rename fails), falls back to copying it over and deleting the
  /// original.
  Future<File> _stage(
    File source,
    Directory dir,
    int i,
    int enqueuedAtMs,
  ) async {
    final name = source.uri.pathSegments.isNotEmpty
        ? source.uri.pathSegments.last
        : 'photo.jpg';
    final target = File('${dir.path}/${enqueuedAtMs}_${i}_$name');
    try {
      return await source.rename(target.path);
    } on FileSystemException {
      final copied = await source.copy(target.path);
      await _deleteQuietly(source);
      return copied;
    }
  }

  /// Puts the download URL back on a carried image before its re-link.
  ///
  /// Returns null when it could not be resolved, which the caller treats as a
  /// transient failure. An image with no `storagePath` is a legacy entry whose
  /// `url` the queue still persists, so it is already complete.
  Future<AppointmentImage?> _resolveCarriedUrl(
    AppointmentImage image,
    String appointmentId,
  ) async {
    if (image.storagePath.isEmpty) return image;
    if (image.url.isNotEmpty) return image;
    final url = await _urlResolver.resolve(image);
    if (url.isEmpty) {
      _logger.warn(
        'IMG-UPLOAD could not re-resolve a carried url for $appointmentId',
      );
      return null;
    }
    return image.copyWith(url: url);
  }

  /// Uploads one queued batch. Files that are permanently rejected are
  /// dropped, files that hit a transient failure get re-queued, and anything
  /// that uploads successfully is removed from the queue.
  Future<void> _attempt(PendingUpload entry) async {
    final files = entry.paths
        .map(File.new)
        .where((f) => f.existsSync())
        .toList();
    if (files.isEmpty && entry.uploaded.isEmpty) {
      await _store.remove(entry.id);
      return;
    }

    var permanentFailures = 0;
    final tooLargeNames = <String>[];
    var transientFailure = false;
    final survivors = <String>[];

    // Images uploaded on a prior pass whose doc-link append didn't land are
    // carried forward, so we re-attempt just the append without re-uploading
    // them — their local temp files are already gone.
    //
    // The queue deliberately does not persist download URLs (see
    // `PendingUpload._imageToJson`), so a carried image arrives with an empty
    // one and it has to be resolved again before the re-link. The token is
    // stable per object, so this reproduces the map a partially-committed
    // append already wrote and the `arrayUnion` dedupe still holds.
    //
    // Resolved CONCURRENTLY: each is a Storage round trip, and this runs on
    // the offline→online flip — exactly when the connection is worst and a
    // ten-photo batch would otherwise serialise ten of them.
    final resolved = await Future.wait(
      entry.uploaded.map((i) => _resolveCarriedUrl(i, entry.appointmentId)),
    );
    // A null could not be re-resolved. Appending with a blank url would write
    // a second, broken array entry beside the one already there, so treat it
    // as the transient failure it almost always is and keep the image queued.
    final resolveFailed = resolved.any((i) => i == null);
    if (resolveFailed) transientFailure = true;
    final uploaded = <AppointmentImage>[
      for (var i = 0; i < resolved.length; i++)
        resolved[i] ?? entry.uploaded[i],
    ];

    for (final file in files) {
      try {
        uploaded.add(await _storage.uploadImage(entry.appointmentId, file));
        await _deleteQuietly(file);
      } on ImageUploadFailure catch (e, st) {
        permanentFailures++;
        if (e is ImageUploadFailureTooLarge) {
          tooLargeNames.add(_fileName(file));
        }
        _logger.warn(
          'IMG-UPLOAD rejected file for ${entry.appointmentId}',
          e,
          st,
        );
        await _deleteQuietly(file);
      } catch (e, st) {
        transientFailure = true;
        survivors.add(file.path);
        _logger.warn(
          'IMG-UPLOAD transient failure for ${entry.appointmentId}',
          e,
          st,
        );
      }
    }

    // Skipped entirely when a carried url could not be re-resolved: appending
    // then would write a blank-url duplicate beside the entry already in the
    // array, which is worse than waiting for the next drain.
    var appendFailed = resolveFailed && uploaded.isNotEmpty;
    if (uploaded.isNotEmpty && !resolveFailed) {
      try {
        // Use arrayUnion so concurrent edits/retries never clobber existing pictures.
        await _appointments.appendAppointmentPictures(
          entry.appointmentId,
          uploaded,
        );
      } catch (e, st) {
        // Uploads landed but the doc-link write didn't. The local files are
        // already deleted, so re-queue the uploaded images for an append-only
        // retry rather than dropping them — otherwise the bytes sit orphaned
        // in Storage, invisible on the appointment.
        appendFailed = true;
        _logger.warn(
          'IMG-UPLOAD append failed for ${entry.appointmentId}',
          e,
          st,
        );
      }
    }

    if (transientFailure || appendFailed) {
      // Re-queue whatever didn't land — survivor paths to re-upload, plus the
      // already-uploaded images if only their append failed — keeping the
      // original enqueued time so the 7-day pruning still counts from when the
      // batch first showed up.
      await _store.remove(entry.id);
      await _store.add(
        PendingUpload(
          appointmentId: entry.appointmentId,
          paths: survivors,
          enqueuedAtMs: entry.enqueuedAtMs,
          uploaded: appendFailed ? uploaded : const [],
        ),
      );
      // The permanent failures counted in the SAME pass belong here too. A
      // batch holding one oversized photo and one network blip deletes the
      // oversized file above, so it can never retry — reporting only the
      // retryable ones left the person waiting for a retry that cannot happen,
      // with the one actionable detail ("this file is too large") withheld.
      _notifier.reportFailure(
        entry.appointmentId,
        failedCount:
            survivors.length +
            (appendFailed ? uploaded.length : 0) +
            permanentFailures,
        tooLargeFileNames: tooLargeNames,
      );
    } else {
      await _store.remove(entry.id);
      if (permanentFailures > 0) {
        _notifier.reportFailure(
          entry.appointmentId,
          failedCount: permanentFailures,
          tooLargeFileNames: tooLargeNames,
        );
      } else {
        _notifier.clearFailure(entry.appointmentId);
      }
    }
  }

  /// Uploads queued batches one drain at a time. If this gets called again
  /// while a drain is already running, [_pendingDrain] makes it loop instead
  /// of starting a second one concurrently.
  Future<void> drainPending() async {
    if (_draining) {
      _pendingDrain = true;
      return;
    }
    _draining = true;
    try {
      do {
        _pendingDrain = false;
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
        }
      } while (_pendingDrain);
    } finally {
      _draining = false;
    }
  }

  Future<void> _deleteQuietly(File f) async {
    try {
      if (f.existsSync()) await f.delete();
    } catch (e, st) {
      _logger.warn('IMG-UPLOAD cleanup failed for ${f.path}', e, st);
    }
  }

  static String _fileName(File file) {
    final segments = file.uri.pathSegments;
    return segments.isNotEmpty ? segments.last : file.path;
  }
}

final appointmentImageUploadProvider = Provider<AppointmentImageUploadService>((
  ref,
) {
  return AppointmentImageUploadService(
    appointments: ref.watch(appointmentsRepositoryProvider),
    notifier: ref.watch(photoUploadNotifierProvider),
  );
});

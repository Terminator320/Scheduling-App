import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'package:scheduling/core/images/image_storage_service.dart';
import 'package:scheduling/core/images/image_upload_failure.dart';
import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/features/calendar/application/appointments_providers.dart';
import 'package:scheduling/features/calendar/application/photo_upload_notifier.dart';
import 'package:scheduling/features/calendar/data/pending_upload_store.dart';
import 'package:scheduling/features/calendar/domain/appointments_repository.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_image.dart';

typedef _UploadFilesResult = ({
  List<AppointmentImage> uploaded,
  List<String> survivors,
  List<String> tooLargeNames,
  int permanentFailures,
  bool transientFailure,
});

class AppointmentImageUploadService {
  AppointmentImageUploadService({
    required AppointmentsRepository appointments,
    required PhotoUploadNotifier notifier,
    ImageStorageService? storage,
    AppLogger? logger,
    PendingUploadStore? store,
    Future<Directory> Function()? stagingDirProvider,
  }) : _appointments = appointments,
       _notifier = notifier,
       _storage = storage ?? ImageStorageService(),
       _logger = logger ?? AppLogger(),
       _store = store ?? PendingUploadStore(),
       _stagingDirProvider = stagingDirProvider ?? _defaultStagingDir;

  final AppointmentsRepository _appointments;
  final PhotoUploadNotifier _notifier;
  final ImageStorageService _storage;
  final AppLogger _logger;
  final PendingUploadStore _store;

  final Future<Directory> Function() _stagingDirProvider;

  bool _draining = false;

  /// Set when an active drain should loop again.
  bool _pendingDrain = false;

  static Future<Directory> _defaultStagingDir() async {
    final base = await getApplicationSupportDirectory();
    return Directory(_pathIn(base.path, 'pending_uploads')).create(
      recursive: true,
    );
  }

  /// Stages files and starts the background upload.
  void uploadInBackground({
    required String appointmentId,
    required List<File> newImages,
  }) {
    if (newImages.isEmpty) return;
    unawaited(_stageAndRun(appointmentId, List.of(newImages)));
  }

  Future<void> _stageAndRun(String appointmentId, List<File> images) async {
    // Keep staged files reachable for cleanup until the queue owns them.
    var staged = <File>[];
    try {
      final dir = await _stagingDirProvider();
      final enqueuedAtMs = DateTime.now().millisecondsSinceEpoch;
      for (var i = 0; i < images.length; i++) {
        staged.add(await _stage(images[i], dir, i, enqueuedAtMs));
      }
      final entry = PendingUpload(
        appointmentId: appointmentId,
        paths: staged.map((f) => f.path).toList(),
        enqueuedAtMs: enqueuedAtMs,
      );
      await _store.add(entry);
      // Now owned by the queue, so nothing below may delete them.
      staged = const [];
      // Published BEFORE the drain, so an offline device shows "waiting"
      // immediately rather than only after the attempt has failed.
      await _publishPending();
      // Drains are serialized to avoid duplicate upload passes.
      await drainPending();
    } catch (e, st) {
      for (final file in staged) {
        await _deleteQuietly(file);
      }
      _notifier.reportFailure(appointmentId, failedCount: images.length);
      _logger.warn('IMG-UPLOAD staging failed for $appointmentId', e, st);
    }
  }

  /// Moves a temp file into staging, falling back to copy/delete.
  Future<File> _stage(
    File source,
    Directory dir,
    int i,
    int enqueuedAtMs,
  ) async {
    final name = source.uri.pathSegments.isNotEmpty
        ? source.uri.pathSegments.last
        : 'photo.jpg';
    final target = File(_pathIn(dir.path, '${enqueuedAtMs}_${i}_$name'));
    try {
      return await source.rename(target.path);
    } on FileSystemException {
      final copied = await source.copy(target.path);
      await _deleteQuietly(source);
      return copied;
    }
  }

  /// Upload result for one pass over a batch's local files.
  Future<_UploadFilesResult> _uploadFiles(
    PendingUpload entry,
    List<File> files,
  ) async {
    var permanentFailures = 0;
    var transientFailure = false;
    final tooLargeNames = <String>[];
    final survivors = <String>[];

    // Previously uploaded images are retried append-only.
    final uploaded = <AppointmentImage>[...entry.uploaded];

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

    return (
      uploaded: uploaded,
      survivors: survivors,
      tooLargeNames: tooLargeNames,
      permanentFailures: permanentFailures,
      transientFailure: transientFailure,
    );
  }

  /// Links uploaded photos and reports whether the append failed.
  Future<bool> _appendLinks(
    PendingUpload entry,
    List<AppointmentImage> uploaded,
  ) async {
    if (uploaded.isEmpty) return false;
    try {
      // Derived photo ids make partial append retries idempotent.
      await _appointments.appendAppointmentPictures(
        entry.appointmentId,
        uploaded,
      );
      return false;
    } catch (e, st) {
      // Re-queue uploaded images for an append-only retry.
      _logger.warn(
        'IMG-UPLOAD append failed for ${entry.appointmentId}',
        e,
        st,
      );
      return true;
    }
  }

  /// Uploads one queued batch and updates its queue entry.
  Future<void> _attempt(PendingUpload entry) async {
    final files = entry.paths
        .map(File.new)
        .where((f) => f.existsSync())
        .toList();
    if (files.isEmpty && entry.uploaded.isEmpty) {
      await _store.remove(entry.id);
      return;
    }

    final upload = await _uploadFiles(entry, files);
    final appendThrew = await _appendLinks(entry, upload.uploaded);
    final tooLargeNames = upload.tooLargeNames;
    final survivors = upload.survivors;

    final outcome = AttemptOutcome.from(
      permanentFailures: upload.permanentFailures,
      transientFailure: upload.transientFailure,
      survivors: survivors,
      appendThrew: appendThrew,
      uploaded: upload.uploaded,
    );

    if (outcome.requeue) {
      // Replace atomically so failed requeues leave the original entry intact.
      await _store.replace(
        entry.id,
        PendingUpload(
          appointmentId: entry.appointmentId,
          paths: survivors,
          enqueuedAtMs: entry.enqueuedAtMs,
          uploaded: outcome.uploadedToCarry,
        ),
      );
      _notifier.reportFailure(
        entry.appointmentId,
        failedCount: outcome.failedCount,
        tooLargeFileNames: tooLargeNames,
      );
    } else {
      await _store.remove(entry.id);
      if (outcome.failedCount > 0) {
        _notifier.reportFailure(
          entry.appointmentId,
          failedCount: outcome.failedCount,
          tooLargeFileNames: tooLargeNames,
        );
      } else {
        _notifier.clearFailure(entry.appointmentId);
      }
    }
  }

  /// Drains queued batches without running two drains at once.
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
            // Per entry, not per drain: a long queue should visibly shrink.
            await _publishPending();
          }
          await _publishPending();
        } catch (e, st) {
          _logger.warn('IMG-UPLOAD drain failed', e, st);
          // A failed drain leaves the queue as it was; republish so the waiting
          // count is never left stale by the failure path.
          await _publishPending();
        }
      } while (_pendingDrain);
    } finally {
      _draining = false;
    }
  }

  /// Republishes the queue depth per appointment from the store itself.
  Future<void> _publishPending() async {
    try {
      final counts = <String, int>{};
      for (final entry in await _store.load()) {
        counts[entry.appointmentId] =
            (counts[entry.appointmentId] ?? 0) + entry.paths.length;
      }
      _notifier.reportPending(counts);
    } catch (e, st) {
      // Never let the SIGNAL break the upload: this is a status read.
      _logger.warn('IMG-UPLOAD pending count failed', e, st);
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

  static String _pathIn(String parent, String child) =>
      '$parent${Platform.pathSeparator}$child';
}

/// Queue decision from one upload attempt.
@visibleForTesting
class AttemptOutcome {
  const AttemptOutcome({
    required this.requeue,
    required this.uploadedToCarry,
    required this.failedCount,
  });

  factory AttemptOutcome.from({
    required int permanentFailures,
    required bool transientFailure,
    required List<String> survivors,
    required bool appendThrew,
    required List<AppointmentImage> uploaded,
  }) {
    final requeue = transientFailure || appendThrew;
    final retryableFailures =
        survivors.length + (appendThrew ? uploaded.length : 0);
    return AttemptOutcome(
      requeue: requeue,
      uploadedToCarry: appendThrew ? uploaded : const [],
      // Permanent failures still count when retryable failures requeue.
      failedCount: requeue
          ? retryableFailures + permanentFailures
          : permanentFailures,
    );
  }

  /// Whether the entry goes back on the queue instead of draining away.
  final bool requeue;

  /// Already-uploaded images to carry for append-only retry.
  final List<AppointmentImage> uploadedToCarry;

  /// Failed photo count reported to the notifier.
  final int failedCount;
}

final appointmentImageUploadProvider = Provider<AppointmentImageUploadService>((
  ref,
) {
  return AppointmentImageUploadService(
    appointments: ref.watch(appointmentsRepositoryProvider),
    notifier: ref.watch(photoUploadNotifierProvider),
  );
});

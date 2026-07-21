import 'dart:async';
import 'dart:io';

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

  /// Set when a drain is requested while one is already running (a save that
  /// stages a new batch mid-drain). The in-flight pass re-runs instead of the
  /// caller starting a second, concurrent one — see [drainPending].
  bool _pendingDrain = false;

  static Future<Directory> _defaultStagingDir() async {
    final base = await getApplicationSupportDirectory();
    return Directory('${base.path}/pending_uploads').create(recursive: true);
  }

  /// Stages the picked files into durable storage, records them, then uploads
  /// in the background. Signature unchanged — still fire-and-forget.
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
      // Upload through the same serialized drain the listeners use. Calling
      // `_attempt(entry)` directly here raced them: a drain fired by the
      // offline→online or account-doc listener in this window would load the
      // just-added entry and upload it concurrently, and because
      // `ImageStorageService` mints each file name from `DateTime.now()`, the
      // two passes produce DIFFERENT storage paths that `arrayUnion` cannot
      // dedupe — the same photo lands twice.
      await drainPending();
    } catch (e, st) {
      _notifier.reportFailure(appointmentId, failedCount: images.length);
      _logger.warn('IMG-UPLOAD staging failed for $appointmentId', e, st);
    }
  }

  /// Moves a picker temp file into the staging dir. Falls back to copy+delete
  /// when the temp file sits on another volume (rename crosses devices).
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

  /// Uploads one queued batch. Uploaded files are deleted; permanently rejected
  /// files (bad magic bytes / too large) are dropped and counted; transient
  /// failures keep only the unsent paths queued under the same entry age.
  Future<void> _attempt(PendingUpload entry) async {
    final files = entry.paths
        .map(File.new)
        .where((f) => f.existsSync())
        .toList();
    if (files.isEmpty) {
      await _store.remove(entry.id);
      return;
    }

    final uploaded = <AppointmentImage>[];
    var permanentFailures = 0;
    final tooLargeNames = <String>[];
    var transientFailure = false;
    final survivors = <String>[];

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

    if (uploaded.isNotEmpty) {
      // Append (arrayUnion) rather than rewriting the whole array: an edit saved
      // while this upload was in flight, or a later retry of the batch's other
      // half, must never clobber the already-uploaded pictures.
      await _appointments.appendAppointmentPictures(
        entry.appointmentId,
        uploaded,
      );
    }

    if (transientFailure) {
      // Re-queue only the unsent paths, preserving the entry age so a batch
      // never retries past the 7-day pruning window.
      await _store.remove(entry.id);
      await _store.add(
        PendingUpload(
          appointmentId: entry.appointmentId,
          paths: survivors,
          enqueuedAtMs: entry.enqueuedAtMs,
        ),
      );
      _notifier.reportFailure(
        entry.appointmentId,
        failedCount: survivors.length,
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

  /// The single serialized path for uploading queued batches — both the
  /// listener-driven retries and [_stageAndRun] go through here. Prunes >7-day
  /// entries first, deleting their staged files.
  ///
  /// Reentrancy-guarded: a request arriving mid-drain (a reconnect flap, or a
  /// save staging a batch) sets [_pendingDrain] so the in-flight pass repeats
  /// rather than running concurrently — coalescing instead of dropping, so a
  /// batch staged during a drain still uploads without waiting for the next
  /// reconnect.
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

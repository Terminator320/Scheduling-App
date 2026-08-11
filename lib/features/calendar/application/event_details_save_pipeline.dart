import 'dart:io';

import 'package:scheduling/core/images/image_storage_service.dart';
import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/features/calendar/application/appointment_series_editor.dart';
import 'package:scheduling/features/calendar/application/event_details_outcome.dart';
import 'package:scheduling/features/calendar/data/appointment_image_upload_service.dart';
import 'package:scheduling/features/calendar/domain/appointments_repository.dart';
import 'package:scheduling/features/calendar/domain/assignee_resolver.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_image.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/calendar/domain/models/repeat_interval.dart';
import 'package:scheduling/features/clients/domain/models/client_record.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';
import 'package:scheduling/shared/widgets/feedback/status_chip.dart';

/// The write half of editing an appointment: merge the assignees, build the
/// record, apply it (single visit / whole series / repeat rewrite), then apply
/// the photo changes.
///
/// Split out of `EventDetailsController` because the rules it carries are the
/// ones the codebase flags hardest for correctness — retaining assignees the
/// picker cannot show, normalizing a legacy status through
/// [AppointmentStatus.storedRaw], choosing the series branch, and deleting
/// orphaned bytes only AFTER the doc stops pointing at them. Each is far
/// easier to reason about (and to test) when it takes explicit values instead
/// of reaching into controller state.
///
/// Deliberately holds NO state and touches no `Ref`: the controller keeps
/// owning `isSaving`, the error map and the seed, so the reentrancy and
/// `ref.mounted` rules stay in one place.
class EventDetailsSavePipeline {
  const EventDetailsSavePipeline({
    required this.repo,
    required this.resolveStorage,
    required this.logger,
  });

  final AppointmentsRepository repo;

  /// Resolved LAZILY, and only when there are bytes to delete: constructing
  /// `ImageStorageService` touches `FirebaseStorage.instance`, so resolving it
  /// on every save would initialize Storage for edits that have no photos.
  ///
  /// Returns null once the host is gone — this runs after several awaits, and
  /// reading a disposed `Ref` throws. Orphaned bytes are the acceptable loss.
  final ImageStorageService? Function() resolveStorage;

  final AppLogger logger;

  /// The final assignee list: the selected employees plus any original
  /// assignee the picker could not show, so a disabled or removed person is
  /// never silently unassigned.
  ///
  /// [activeEmployees] must be a FRESHLY awaited list — a cold or empty cached
  /// value makes every original assignee look inactive, so all of them are
  /// retained and a real deselection is silently undone.
  ({List<String> ids, List<String> names}) resolveAssignees({
    required AppointmentRecord appointment,
    required List<EmployeeRecord> selected,
    required List<EmployeeRecord> activeEmployees,
  }) {
    return mergeRetainedAssignees(
      originalIds: appointment.employeeIds,
      originalNames: appointment.employeeNames,
      selectedIds: selected.map((e) => e.id).toList(),
      selectedNames: selected.map((e) => e.name).toList(),
      activeIds: activeEmployees.map((e) => e.id).toSet(),
    );
  }

  /// The edited record, from the form fields and the resolved assignees.
  AppointmentRecord buildUpdatedRecord(
    AppointmentRecord appointment, {
    required String id,
    required String title,
    required String address,
    required String notes,
    required String materialsNeeded,
    required DateTime start,
    required DateTime end,
    required ({List<String> ids, List<String> names}) assignees,
    required ClientRecord? selectedClient,
    required List<AppointmentImage> pictures,
    required String status,
    required RepeatInterval repeat,
    required bool isPersonal,
    required bool isAllDay,
  }) {
    // A personal job carries no client and no address — including when an
    // existing client visit is converted into one, so the stored copies are
    // cleared rather than left behind on a job that no longer shows them.
    final pickedClient = isPersonal ? null : selectedClient;
    return AppointmentRecord(
      id: id,
      title: title.trim(),
      startTime: start,
      endTime: end,
      clientId: isPersonal ? '' : pickedClient?.id ?? appointment.clientId,
      clientName: isPersonal
          ? ''
          : pickedClient?.displayName ?? appointment.clientName,
      clientPhone: isPersonal
          ? ''
          : pickedClient?.phone ?? appointment.clientPhone,
      address: isPersonal ? '' : address.trim(),
      isPersonal: isPersonal,
      isAllDay: isAllDay,
      employeeIds: assignees.ids,
      employeeNames: assignees.names,
      notes: notes.trim(),
      materialsNeeded: materialsNeeded.trim(),
      // Pictures are included here only for the outcome/UI — actual updates
      // go through append/remove instead.
      pictures: pictures,
      status: status,
      repeat: repeat,
      seriesId: appointment.seriesId,
    );
  }

  /// Applies the edit: rewrite the series if the repeat changed, propagate it
  /// if [applyToSeries] is set, or otherwise update the single appointment.
  Future<EventDetailsSaved> applySeriesChange(
    AppointmentRecord appointment, {
    required AppointmentRecord updated,
    required String id,
    required DateTime start,
    required DateTime end,
    required bool applyToSeries,
    required RepeatInterval repeat,
    required RepeatInterval savedRepeat,
  }) async {
    final seriesEditor = AppointmentSeriesEditor(repo);
    if (repeat != savedRepeat) {
      final result = await seriesEditor.rewrite(
        updated: updated,
        appointment: appointment,
        id: id,
        start: start,
        end: end,
        repeat: repeat,
      );
      return EventDetailsSaved(
        result.updated,
        futureBookings: result.futureBookings,
        removedBookings: result.removedBookings,
      );
    }
    if (applyToSeries && appointment.seriesId.isNotEmpty) {
      final updatedSiblings = await seriesEditor.propagate(
        updated: updated,
        appointment: appointment,
        id: id,
        start: start,
        end: end,
      );
      return EventDetailsSaved(updated, updatedSiblings: updatedSiblings);
    }
    await repo.updateAppointment(updated);
    return EventDetailsSaved(updated);
  }

  /// Photo changes, AFTER the record write — the ordering matters.
  ///
  /// [onRecordWritten] runs between the removal and the storage cleanup; the
  /// controller uses it to move its repeat baseline, which is state and so
  /// stays out of here.
  Future<void> applyPhotoChanges({
    required String id,
    required AppointmentImageUploadService? uploader,
    required List<AppointmentImage> removedImages,
    required List<File> newImages,
    void Function()? onRecordWritten,
  }) async {
    // arrayRemove only, so a concurrent upload isn't clobbered.
    if (removedImages.isNotEmpty) {
      await repo.removeAppointmentPictures(id, removedImages);
    }
    onRecordWritten?.call();
    // Bytes are deleted only once the doc has stopped referencing them.
    await deleteOrphanedImages(removedImages, tag: 'APPT-SAVE');
    if (newImages.isNotEmpty) {
      uploader?.uploadInBackground(appointmentId: id, newImages: newImages);
    }
  }

  /// Best-effort cleanup — orphaned bytes are harmless, so this only logs.
  Future<void> deleteOrphanedImages(
    List<AppointmentImage> images, {
    required String tag,
  }) async {
    if (images.isEmpty) return;
    final storage = resolveStorage();
    if (storage == null) return;
    try {
      await storage.deleteImages(images);
    } catch (e, st) {
      logger.warn('$tag deleteImages failed (orphaned bytes)', e, st);
    }
  }
}

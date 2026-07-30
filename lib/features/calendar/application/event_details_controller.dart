import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:scheduling/core/connectivity/connectivity_providers.dart';
import 'package:scheduling/core/images/images_providers.dart';
import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/features/auth/application/account_status_provider.dart';
import 'package:scheduling/features/calendar/application/appointment_form_concerns.dart';
import 'package:scheduling/features/calendar/application/appointment_series_editor.dart';
import 'package:scheduling/features/calendar/application/appointments_providers.dart';
import 'package:scheduling/features/calendar/application/event_details_outcome.dart';
import 'package:scheduling/features/calendar/application/event_series_helpers.dart';
import 'package:scheduling/features/calendar/data/appointment_image_upload_service.dart';
import 'package:scheduling/features/calendar/domain/appointments_repository.dart';
import 'package:scheduling/features/calendar/domain/assignee_resolver.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_image.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/calendar/domain/models/repeat_interval.dart';
import 'package:scheduling/features/calendar/domain/policies/appointment_form_validator.dart';
import 'package:scheduling/features/clients/application/clients_providers.dart';
import 'package:scheduling/features/clients/domain/models/client_record.dart';
import 'package:scheduling/features/employees/application/employees_providers.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';
import 'package:scheduling/shared/widgets/feedback/status_chip.dart';

// Re-export for single-source imports.
export 'package:scheduling/features/calendar/application/event_details_outcome.dart';

part 'event_details_controller.freezed.dart';

@freezed
abstract class EventDetailsState
    with _$EventDetailsState
    implements AppointmentFormFields {
  const factory EventDetailsState({
    required DateTime selectedDate,
    required TimeOfDay selectedStartTime,
    required TimeOfDay selectedEndTime,
    required String editingStatus,
    @Default(false) bool isEditing,
    @Default(RepeatInterval.none) RepeatInterval repeat,
    // The repeat value as last saved — if the user changes it, that triggers new bookings.
    @Default(RepeatInterval.none) RepeatInterval savedRepeat,
    @Default(<EmployeeRecord>[]) List<EmployeeRecord> selectedEmployees,
    @Default(<AppointmentImage>[]) List<AppointmentImage> existingImages,
    @Default(<AppointmentImage>[]) List<AppointmentImage> removedExistingImages,
    @Default(<File>[]) List<File> newImages,
    @Default(false) bool isSaving,
    ClientRecord? client,
    ClientRecord? selectedClient,
    @Default(<ClientRecord>[]) List<ClientRecord> clientResults,
    @Default(false) bool isSearchingClient,
    @Default(false) bool useCustomAddress,
    // Set when the user explicitly removes the client, so we don't fall back to a placeholder.
    @Default(false) bool clientCleared,
    @Default(<String, AppointmentFormError>{})
    Map<String, AppointmentFormError> errors,
  }) = _EventDetailsState;
}

class EventDetailsController extends Notifier<EventDetailsState>
    with AppointmentFormConcerns<EventDetailsState> {
  EventDetailsController(EventDetailsKey key) : appointment = key.appointment;

  final AppointmentRecord appointment;

  // Settles when employee enrichment completes, so save() runs on warm data.
  Future<void>? _seedFuture;

  @override
  EventDetailsState build() {
    Future.microtask(() => _loadClientIfNeeded(appointment.clientId));
    _seedFuture = Future.microtask(_enrichSelectedEmployees);
    return EventDetailsState(
      selectedDate: appointment.startTime,
      selectedStartTime: TimeOfDay.fromDateTime(appointment.startTime),
      selectedEndTime: TimeOfDay.fromDateTime(appointment.endTime),
      // storedRaw normalizes legacy/unknown status so save won't fail rules validation.
      editingStatus: AppointmentStatus.storedRaw(appointment.status),
      repeat: appointment.repeat,
      savedRepeat: appointment.repeat,
      // Seeded synchronously to avoid a race with the async load below — employee
      // visibility depends on employeeIds being set right away.
      selectedEmployees: _assigneesFromRecord(appointment),
      existingImages: List.of(appointment.pictures),
    );
  }

  /// Builds placeholder employees from the stored ids and names. They get
  /// swapped for the full records once those load.
  static List<EmployeeRecord> _assigneesFromRecord(AppointmentRecord a) => [
    for (var i = 0; i < a.employeeIds.length; i++)
      EmployeeRecord(
        id: a.employeeIds[i],
        name: i < a.employeeNames.length ? a.employeeNames[i] : '',
      ),
  ];

  /// Fills in the seeded placeholders with full employee records, for display
  /// only — whatever the user has toggled still wins.
  Future<void> _enrichSelectedEmployees() async {
    if (state.selectedEmployees.isEmpty) return;
    final logger = ref.read(loggerProvider);
    try {
      final all = await _resolveActiveEmployees();
      if (!ref.mounted) return;
      final byId = {for (final e in all) e.id: e};
      state = state.copyWith(
        selectedEmployees: [
          for (final e in state.selectedEmployees) byId[e.id] ?? e,
        ],
      );
    } catch (e, st) {
      logger.warn('enrichSelectedEmployees failed', e, st);
    }
  }

  /// Resolves the active staff set the same way for both seeding and
  /// assignee resolution.
  Future<List<EmployeeRecord>> _resolveActiveEmployees() =>
      ref.read(employeesRepositoryProvider).watchEmployees().first;

  Future<void> _loadClientIfNeeded(String clientId) async {
    final id = clientId.trim();
    if (id.isEmpty || state.client != null) return;
    // The clients read rule is admin-only, so skip this load for employees —
    // otherwise it just logs a permission-denied error.
    if (ref.exists(currentUserDocProvider)) {
      final role = ref.read(userRoleProvider).value ?? '';
      if (role.isNotEmpty && role != 'admin') return;
    }
    final logger = ref.read(loggerProvider);
    final clientsRepo = ref.read(clientsRepositoryProvider);
    try {
      final client = await clientsRepo.getClientById(id);
      // Check again after the await, since the user might have picked a client while this was loading.
      if (!ref.mounted) return;
      if (client == null || state.client != null) return;
      if (state.selectedClient == null && !state.clientCleared) {
        state = state.copyWith(
          client: client,
          selectedClient: client,
          // No-fixed-address clients always use custom mode.
          useCustomAddress:
              client.noFixedAddress ||
              appointment.address.trim() != client.address.trim(),
        );
      } else {
        state = state.copyWith(client: client);
      }
    } catch (e, st) {
      logger.warn('loadClientIfNeeded failed', e, st);
    }
  }

  void enterEditing() =>
      state = state.copyWith(isEditing: true, errors: const {});

  void exitEditing() => state = state.copyWith(isEditing: false);

  void selectDate(DateTime date) {
    state = state.copyWith(
      selectedDate: date,
      errors: withoutKey(state.errors, 'date'),
    );
  }

  void selectStartTime(TimeOfDay time) {
    state = state.copyWith(
      selectedStartTime: time,
      errors: withoutKey(state.errors, 'startTime'),
    );
  }

  void selectEndTime(TimeOfDay time) {
    state = state.copyWith(
      selectedEndTime: time,
      errors: withoutKey(state.errors, 'endTime'),
    );
  }

  void setStatus(String status) {
    state = state.copyWith(editingStatus: status);
  }

  void selectRepeat(RepeatInterval value) {
    state = state.copyWith(repeat: value);
  }

  // --- AppointmentFormConcerns adapters ---

  @override
  EventDetailsState applyFormUpdate(
    EventDetailsState current,
    AppointmentFormUpdate update,
  ) {
    var next = current.copyWith(
      clientResults: update.clientResults ?? current.clientResults,
      isSearchingClient: update.isSearchingClient ?? current.isSearchingClient,
      useCustomAddress: update.useCustomAddress ?? current.useCustomAddress,
      selectedEmployees: update.selectedEmployees ?? current.selectedEmployees,
      errors: update.errors ?? current.errors,
      newImages: update.pendingImages ?? current.newImages,
    );
    // Unlike the add flow, this state also tracks the loaded `client` and the
    // explicit-clear flag (which blocks the placeholder fallback in save()).
    if (update.selectedClient != null) {
      next = next.copyWith(
        selectedClient: update.selectedClient,
        client: update.selectedClient,
        clientCleared: false,
      );
    } else if (update.clearSelectedClient) {
      next = next.copyWith(
        selectedClient: null,
        client: null,
        clientCleared: true,
      );
    }
    return next;
  }

  @override
  int get usedImageCount =>
      state.existingImages.length + state.newImages.length;

  @override
  List<File> get pendingImages => state.newImages;

  void removeNewImage(int index) => removePendingImageAt(index);

  void removeExistingImage(int index) {
    final removed = state.existingImages[index];
    final remaining = [...state.existingImages]..removeAt(index);
    state = state.copyWith(
      existingImages: remaining,
      removedExistingImages: [...state.removedExistingImages, removed],
    );
  }

  /// Writes `status: 'done'`. If it fails, the widget layer builds a failure
  /// notice from the returned outcome.
  Future<EventDetailsActionOutcome> markAsDone(AppointmentRecord appointment) {
    return _setStatusOnRepo(appointment, 'done');
  }

  Future<EventDetailsActionOutcome> cancelAppointment(
    AppointmentRecord appointment,
  ) {
    return _setStatusOnRepo(appointment, 'cancelled');
  }

  Future<EventDetailsActionOutcome> _setStatusOnRepo(
    AppointmentRecord appointment,
    String status,
  ) async {
    final id = appointment.id;
    if (id == null) {
      return EventDetailsActionFailed(StateError('appointment has no id'));
    }
    // Reject a double-tap on the status write — same reentrancy guard save() uses.
    if (state.isSaving) return const EventDetailsActionBusy();
    state = state.copyWith(isSaving: true);
    final repo = ref.read(appointmentsRepositoryProvider);
    final logger = ref.read(loggerProvider);
    try {
      await repo.updateAppointmentStatus(id: id, status: status);
      // The live activity card gets ended server-side via the liveActivityCards
      // marker, so don't end it locally here.
      if (ref.mounted) state = state.copyWith(isSaving: false);
      return const EventDetailsActionOk();
    } catch (e, st) {
      logger.warn('APPT-STATUS updateAppointmentStatus($status) failed', e, st);
      if (ref.mounted) state = state.copyWith(isSaving: false);
      return EventDetailsActionFailed(e);
    }
  }

  /// Toggles the busy flag while a confirmation dialog is open to prevent duplicate prompts.
  void setSaving({required bool busy}) =>
      state = state.copyWith(isSaving: busy);

  /// Builds the final assignee list: the selected employees plus any original
  /// assignees that weren't in the picker, so we don't silently unassign them.
  Future<({List<String> ids, List<String> names})> _resolveAssignees(
    AppointmentRecord appointment,
  ) async {
    final activeEmployees = await _resolveActiveEmployees();
    return mergeRetainedAssignees(
      originalIds: appointment.employeeIds,
      originalNames: appointment.employeeNames,
      selectedIds: state.selectedEmployees.map((e) => e.id).toList(),
      selectedNames: state.selectedEmployees.map((e) => e.name).toList(),
      activeIds: activeEmployees.map((e) => e.id).toSet(),
    );
  }

  Future<EventDetailsSaveOutcome> save(
    AppointmentRecord appointment, {
    required String title,
    required String address,
    required String notes,
    required String materialsNeeded,
    bool applyToSeries = false,
    bool forceBusy = false,
  }) async {
    // Mark this in-flight before the seed-settle await, so a double-tap can't
    // start a concurrent save.
    if (state.isSaving) return const EventDetailsInvalid();

    // Bail out early if we're offline, before setting the flag — otherwise
    // Save just spins waiting for a server ack that isn't coming.
    if (ref.read(isOfflineProvider)) {
      return const EventDetailsFailed(SocketException('offline'));
    }
    state = state.copyWith(isSaving: true);

    // Resolve dependencies before the first await, so they survive the sheet
    // being dismissed (Riverpod 3).
    final repo = ref.read(appointmentsRepositoryProvider);
    final logger = ref.read(loggerProvider);
    // Only resolve the upload service if there are photos, so we skip
    // initializing FirebaseStorage otherwise.
    final uploader = state.newImages.isEmpty
        ? null
        : ref.read(appointmentImageUploadProvider);

    final invalid = await _settleAndValidate(appointment, title: title);
    if (invalid != null) return invalid;

    final id = appointment.id;
    if (id == null) {
      state = state.copyWith(isSaving: false);
      return EventDetailsFailed(
        StateError('Cannot save an appointment without an id.'),
      );
    }

    final start = combineDateAndTime(
      state.selectedDate,
      state.selectedStartTime,
    );
    final end = combineEndDateAndTime(
      state.selectedDate,
      state.selectedEndTime,
      state.selectedStartTime,
    );

    // Snapshot the photo state before writing, so it survives the sheet being dismissed.
    final removedImages = state.removedExistingImages;
    final newImages = state.newImages;

    try {
      if (!forceBusy) {
        final busy = await repo.findBusyEmployees(
          candidates: state.selectedEmployees,
          start: start,
          end: end,
          // Without this the job collides with itself and every one of its own
          // assignees reports as busy.
          excludeAppointmentId: id,
        );
        if (busy.isNotEmpty) {
          // Not an error — hand the decision back to the user. The flag has to
          // clear here or Save stays stuck after the dialog is dismissed.
          if (ref.mounted) state = state.copyWith(isSaving: false);
          return EventDetailsBusyEmployees(
            busyEmployees: busy,
            start: start,
            end: end,
          );
        }
      }

      final assignees = await _resolveAssignees(appointment);
      final updated = _buildUpdatedRecord(
        appointment,
        id: id,
        title: title,
        address: address,
        notes: notes,
        materialsNeeded: materialsNeeded,
        start: start,
        end: end,
        assignees: assignees,
      );

      final saved = await _applySeriesChange(
        appointment,
        repo: repo,
        updated: updated,
        id: id,
        start: start,
        end: end,
        applyToSeries: applyToSeries,
      );

      await _applyPhotoChanges(
        id: id,
        repo: repo,
        uploader: uploader,
        removedImages: removedImages,
        newImages: newImages,
      );

      if (ref.mounted) state = state.copyWith(isSaving: false);
      return saved;
    } catch (e, st) {
      logger.warn('APPT-SAVE saveChanges failed', e, st);
      if (ref.mounted) state = state.copyWith(isSaving: false);
      return EventDetailsFailed(e);
    }
  }

  /// Applies photo changes after the record write — this ordering matters.
  Future<void> _applyPhotoChanges({
    required String id,
    required AppointmentsRepository repo,
    required AppointmentImageUploadService? uploader,
    required List<AppointmentImage> removedImages,
    required List<File> newImages,
  }) async {
    // Use arrayRemove only for removed photos to avoid clobbering concurrent uploads.
    if (removedImages.isNotEmpty) {
      await repo.removeAppointmentPictures(id, removedImages);
    }

    // Update baseline for next edit.
    if (ref.mounted) state = state.copyWith(savedRepeat: state.repeat);

    // Clean up images only after the doc stops referencing them.
    await _deleteOrphanedImages(removedImages, tag: 'APPT-SAVE');

    if (newImages.isNotEmpty) {
      uploader?.uploadInBackground(appointmentId: id, newImages: newImages);
    }
  }

  /// Waits for the seed to settle, then validates the form. Returns a stop
  /// outcome if it's invalid, or null to keep going.
  Future<EventDetailsSaveOutcome?> _settleAndValidate(
    AppointmentRecord appointment, {
    required String title,
  }) async {
    // Wait for enrichment to finish, so assignee resolution reads a warm active-employee list.
    await _seedFuture;
    if (!ref.mounted) return const EventDetailsInvalid();

    final clientForValidation =
        state.selectedClient ??
        (!state.clientCleared && appointment.clientId.trim().isNotEmpty
            ? state.client ?? placeholderClient(appointment)
            : null);

    final errors = AppointmentFormValidator.validate(
      AppointmentFormInput(
        title: title,
        date: state.selectedDate,
        startTime: state.selectedStartTime,
        endTime: state.selectedEndTime,
        client: clientForValidation,
        selectedEmployees: state.selectedEmployees,
      ),
    );
    state = state.copyWith(errors: errors);
    if (errors.isNotEmpty) {
      state = state.copyWith(isSaving: false);
      return const EventDetailsInvalid();
    }
    return null;
  }

  // Build the edited record from the form fields and the resolved assignees.
  AppointmentRecord _buildUpdatedRecord(
    AppointmentRecord appointment, {
    required String id,
    required String title,
    required String address,
    required String notes,
    required String materialsNeeded,
    required DateTime start,
    required DateTime end,
    required ({List<String> ids, List<String> names}) assignees,
  }) {
    final pickedClient = state.selectedClient;
    return AppointmentRecord(
      id: id,
      title: title.trim(),
      startTime: start,
      endTime: end,
      clientId: pickedClient?.id ?? appointment.clientId,
      clientName: pickedClient?.displayName ?? appointment.clientName,
      clientPhone: pickedClient?.phone ?? appointment.clientPhone,
      address: address.trim(),
      employeeIds: assignees.ids,
      employeeNames: assignees.names,
      notes: notes.trim(),
      materialsNeeded: materialsNeeded.trim(),
      // Pictures are included here only for the outcome/UI — actual updates
      // go through append/remove instead.
      pictures: state.existingImages,
      status: state.editingStatus,
      repeat: state.repeat,
      seriesId: appointment.seriesId,
    );
  }

  // Apply the edit: rewrite the series if the repeat changed, propagate it if
  // applyToSeries is set, or otherwise just update the single appointment.
  Future<EventDetailsSaved> _applySeriesChange(
    AppointmentRecord appointment, {
    required AppointmentsRepository repo,
    required AppointmentRecord updated,
    required String id,
    required DateTime start,
    required DateTime end,
    required bool applyToSeries,
  }) async {
    final seriesEditor = AppointmentSeriesEditor(repo);
    if (state.repeat != state.savedRepeat) {
      final result = await seriesEditor.rewrite(
        updated: updated,
        appointment: appointment,
        id: id,
        start: start,
        end: end,
        repeat: state.repeat,
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

  /// Returns null on success, or the failure error otherwise. When
  /// [includeFuture] is set, this also deletes the series' future visits in
  /// one batch (done/cancelled visits are preserved).
  Future<Object?> deleteAppointment(
    AppointmentRecord appointment, {
    bool includeFuture = false,
  }) async {
    final id = appointment.id;
    if (id == null) {
      return StateError('Cannot delete an appointment without an id.');
    }
    state = state.copyWith(isSaving: true);
    // Resolve these before the first await, so they survive the sheet being dismissed.
    final repo = ref.read(appointmentsRepositoryProvider);
    final logger = ref.read(loggerProvider);
    try {
      final orphanedImages = <AppointmentImage>[...appointment.pictures];
      if (includeFuture && appointment.seriesId.isNotEmpty) {
        final series = await repo.getSeries(appointment.seriesId);
        final futureIds = futureSeriesIds(
          series,
          excludeId: id,
          after: appointment.startTime,
        );
        // Only the visits we're deleting contribute orphaned bytes — the
        // preserved visits keep their pictures.
        final futureIdSet = futureIds.toSet();
        for (final a in series) {
          if (a.id != null && futureIdSet.contains(a.id)) {
            orphanedImages.addAll(a.pictures);
          }
        }
        await repo.deleteAppointments([id, ...futureIds]);
      } else {
        await repo.deleteAppointment(id);
      }

      // Delete orphaned images after docs are gone.
      await _deleteOrphanedImages(orphanedImages, tag: 'APPT-DEL');

      if (ref.mounted) state = state.copyWith(isSaving: false);
      return null;
    } catch (e, st) {
      logger.warn('APPT-DEL deleteAppointment failed', e, st);
      if (ref.mounted) state = state.copyWith(isSaving: false);
      return e;
    }
  }

  /// Best-effort cleanup — if it fails, the orphaned bytes are harmless, so
  /// we just log it.
  Future<void> _deleteOrphanedImages(
    List<AppointmentImage> images, {
    required String tag,
  }) async {
    if (images.isEmpty || !ref.mounted) return;
    final storage = ref.read(imageStorageProvider);
    final logger = ref.read(loggerProvider);
    try {
      await storage.deleteImages(images);
    } catch (e, st) {
      logger.warn('$tag deleteImages failed (orphaned bytes)', e, st);
    }
  }
}

final eventDetailsControllerProvider = NotifierProvider.autoDispose
    .family<EventDetailsController, EventDetailsState, EventDetailsKey>(
      EventDetailsController.new,
    );

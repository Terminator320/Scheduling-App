import 'dart:io';

import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:scheduling/core/images/images_providers.dart';
import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/features/calendar/application/appointment_series_editor.dart';
import 'package:scheduling/features/calendar/application/appointments_providers.dart';
import 'package:scheduling/features/calendar/application/event_series_helpers.dart';
import 'package:scheduling/features/calendar/data/appointment_image_upload_service.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_image.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/calendar/domain/models/repeat_interval.dart';
import 'package:scheduling/features/calendar/domain/policies/appointment_form_validator.dart';
import 'package:scheduling/features/clients/application/clients_providers.dart';
import 'package:scheduling/features/clients/domain/models/client_record.dart';
import 'package:scheduling/features/clients/domain/policies/client_search_policy.dart';
import 'package:scheduling/features/employees/application/employees_providers.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';

part 'event_details_controller.freezed.dart';

@freezed
abstract class EventDetailsState with _$EventDetailsState {
  const factory EventDetailsState({
    required DateTime selectedDate,
    required TimeOfDay selectedStartTime,
    required TimeOfDay selectedEndTime,
    required String editingStatus,
    @Default(false) bool isEditing,
    @Default(RepeatInterval.none) RepeatInterval repeat,
    // Repeat currently stored on the doc — booking only fires on a change.
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
    // True once the user explicitly removed the client — blocks the
    // placeholder fallback in save() so clientRequired fires like the add flow.
    @Default(false) bool clientCleared,
    @Default(<String, AppointmentFormError>{})
    Map<String, AppointmentFormError> errors,
  }) = _EventDetailsState;
}

sealed class EventDetailsSaveOutcome {
  const EventDetailsSaveOutcome();
}

class EventDetailsInvalid extends EventDetailsSaveOutcome {
  const EventDetailsInvalid();
}

class EventDetailsSaved extends EventDetailsSaveOutcome {
  const EventDetailsSaved(
    this.appointment, {
    this.futureBookings = 0,
    this.removedBookings = 0,
    this.updatedSiblings = 0,
  });
  final AppointmentRecord appointment;

  /// Pre-booked repeat occurrences created alongside the save.
  final int futureBookings;

  /// Old future occurrences deleted by a series rewrite.
  final int removedBookings;

  /// Future series visits the edit was propagated to (apply-to-all).
  final int updatedSiblings;
}

class EventDetailsFailed extends EventDetailsSaveOutcome {
  const EventDetailsFailed(this.error);
  final Object error;
}

class EventDetailsController extends Notifier<EventDetailsState> {
  EventDetailsController(this.appointment);

  final AppointmentRecord appointment;

  // Completes when the active-employee seed has settled. save() awaits it
  // before validating/resolving, so a save fired before seeding resolves can't
  // read an empty selection — which would spuriously fail "employees required"
  // and, if the user toggled meanwhile, drop original assignees (visibility
  // keys on employeeIds).
  Future<void>? _seedFuture;

  @override
  EventDetailsState build() {
    Future.microtask(() => _loadClientIfNeeded(appointment.clientId));
    _seedFuture = Future.microtask(
      () => _seedSelectedEmployees(appointment.employeeIds),
    );
    return EventDetailsState(
      selectedDate: appointment.startTime,
      selectedStartTime: TimeOfDay.fromDateTime(appointment.startTime),
      selectedEndTime: TimeOfDay.fromDateTime(appointment.endTime),
      editingStatus: appointment.status,
      repeat: appointment.repeat,
      savedRepeat: appointment.repeat,
      existingImages: List.of(appointment.pictures),
    );
  }

  Future<void> _seedSelectedEmployees(List<String> employeeIds) async {
    if (employeeIds.isEmpty) return;
    try {
      final all = await _resolveActiveEmployees();
      final selected = all.where((e) => employeeIds.contains(e.id)).toList();
      if (state.selectedEmployees.isEmpty) {
        state = state.copyWith(selectedEmployees: selected);
      }
    } catch (e, st) {
      ref.read(loggerProvider).warn('seedSelectedEmployees failed', e, st);
    }
  }

  /// The active-staff set, resolved identically for seeding and assignee
  /// resolution — keeping the two in lockstep is a correctness requirement
  /// (CLAUDE.md). Prefer the already-live employees stream over opening a
  /// throwaway Firestore listener just to read one value; an empty/null cached
  /// value means the stream hasn't settled (authUid lag), not that there are
  /// zero active staff — so fall back to a fresh read.
  Future<List<EmployeeRecord>> _resolveActiveEmployees() async {
    final cached = ref.read(employeesStreamProvider).value;
    if (cached != null && cached.isNotEmpty) return cached;
    return ref.read(employeesRepositoryProvider).watchEmployees().first;
  }

  Future<void> _loadClientIfNeeded(String clientId) async {
    final id = clientId.trim();
    if (id.isEmpty || state.client != null) return;
    try {
      final client = await ref
          .read(clientsRepositoryProvider)
          .getClientById(id);
      // Re-check after the await: if the user picked (or cleared) a client
      // while the load was in flight, selectClient already set state.client —
      // don't clobber that selection with the appointment's original client.
      if (client == null || state.client != null) return;
      if (state.selectedClient == null && !state.clientCleared) {
        state = state.copyWith(
          client: client,
          selectedClient: client,
          // No-fixed-address clients always open in custom mode; otherwise a
          // stored address that differs from the client's is a custom one.
          useCustomAddress:
              client.noFixedAddress ||
              appointment.address.trim() != client.address.trim(),
        );
      } else {
        state = state.copyWith(client: client);
      }
    } catch (e, st) {
      ref.read(loggerProvider).warn('loadClientIfNeeded failed', e, st);
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

  Future<void> searchClients(String query) async {
    final trimmed = query.trim();
    if (!ClientSearchPolicy.shouldSearch(trimmed)) {
      state = state.copyWith(clientResults: const [], isSearchingClient: false);
      return;
    }
    state = state.copyWith(isSearchingClient: true);
    try {
      final results = await ref
          .read(clientsRepositoryProvider)
          .searchClients(trimmed);
      state = state.copyWith(clientResults: results, isSearchingClient: false);
    } catch (e, st) {
      ref.read(loggerProvider).warn('searchClients failed', e, st);
      state = state.copyWith(isSearchingClient: false);
    }
  }

  void selectClient(ClientRecord client) {
    state = state.copyWith(
      selectedClient: client,
      client: client,
      clientResults: const [],
      useCustomAddress: client.noFixedAddress || client.address.trim().isEmpty,
      clientCleared: false,
      errors: withoutKey(state.errors, 'client'),
    );
  }

  void clearClient() {
    state = state.copyWith(
      selectedClient: null,
      client: null,
      clientResults: const [],
      useCustomAddress: false,
      clientCleared: true,
    );
  }

  void setUseCustomAddress({required bool value}) {
    state = state.copyWith(useCustomAddress: value);
  }

  void toggleEmployee(EmployeeRecord employee) {
    final next = [...state.selectedEmployees];
    final idx = next.indexWhere((e) => e.id == employee.id);
    if (idx >= 0) {
      next.removeAt(idx);
    } else {
      next.add(employee);
    }
    state = state.copyWith(
      selectedEmployees: next,
      errors: next.isEmpty
          ? state.errors
          : withoutKey(state.errors, 'employees'),
    );
  }

  static const int maxImagesPerAppointment = 10;

  void addImages(List<File> files) {
    final used = state.existingImages.length + state.newImages.length;
    final remaining = maxImagesPerAppointment - used;
    if (remaining <= 0) return;
    final accepted = files.take(remaining).toList();
    state = state.copyWith(newImages: [...state.newImages, ...accepted]);
  }

  void removeNewImage(int index) {
    final next = [...state.newImages]..removeAt(index);
    state = state.copyWith(newImages: next);
  }

  void removeExistingImage(int index) {
    final removed = state.existingImages[index];
    final remaining = [...state.existingImages]..removeAt(index);
    state = state.copyWith(
      existingImages: remaining,
      removedExistingImages: [...state.removedExistingImages, removed],
    );
  }

  Future<bool> markAsDone(AppointmentRecord appointment) async {
    return _setStatusOnRepo(appointment, 'done');
  }

  Future<bool> cancelAppointment(AppointmentRecord appointment) async {
    return _setStatusOnRepo(appointment, 'cancelled');
  }

  Future<bool> _setStatusOnRepo(
    AppointmentRecord appointment,
    String status,
  ) async {
    final id = appointment.id;
    if (id == null) return false;
    state = state.copyWith(isSaving: true);
    try {
      await ref
          .read(appointmentsRepositoryProvider)
          .updateAppointmentStatus(id: id, status: status);
      state = state.copyWith(isSaving: false);
      return true;
    } catch (e, st) {
      ref
          .read(loggerProvider)
          .warn('updateAppointmentStatus($status) failed', e, st);
      state = state.copyWith(isSaving: false);
      return false;
    }
  }

  /// Toggles the busy flag from the UI while a confirmation dialog is open, so
  /// a second Save tap can't stack a duplicate prompt (the action buttons,
  /// which watch [EventDetailsState.isSaving], disable too).
  void setSaving({required bool busy}) =>
      state = state.copyWith(isSaving: busy);

  /// Builds the final assignee id/name lists for a save: the picker's active
  /// selection plus any original assignees that aren't in the active-employee
  /// list. Those were never shown in the picker (disabled/removed staff), so
  /// the user couldn't have deselected them — dropping them would silently
  /// unassign and change who can see this visit (visibility keys on
  /// `employeeIds`). [_resolveActiveEmployees] resolves the active set the same
  /// way seeding does, or a deselected employee would be mistaken for a
  /// never-shown one and re-added.
  Future<({List<String> ids, List<String> names})> _resolveAssignees(
    AppointmentRecord appointment,
  ) async {
    final activeEmployees = await _resolveActiveEmployees();
    final activeIds = activeEmployees.map((e) => e.id).toSet();
    final selectedIds = state.selectedEmployees.map((e) => e.id).toList();
    final selectedNames = state.selectedEmployees.map((e) => e.name).toList();
    final retainedIds = <String>[];
    final retainedNames = <String>[];
    for (var i = 0; i < appointment.employeeIds.length; i++) {
      final origId = appointment.employeeIds[i];
      if (!activeIds.contains(origId) && !selectedIds.contains(origId)) {
        retainedIds.add(origId);
        retainedNames.add(
          i < appointment.employeeNames.length
              ? appointment.employeeNames[i]
              : '',
        );
      }
    }
    return (
      ids: [...selectedIds, ...retainedIds],
      names: [...selectedNames, ...retainedNames],
    );
  }

  Future<EventDetailsSaveOutcome> save(
    AppointmentRecord appointment, {
    required String title,
    required String address,
    required String notes,
    required String materialsNeeded,
    bool applyToSeries = false,
  }) async {
    // Reentrancy guard: mark in-flight before the seed-settle await, so a
    // second tap during a cold-cache seed read can't start a concurrent save
    // (which would double-write a series rewrite). The Save button and its
    // call-site guard both read state.isSaving.
    if (state.isSaving) return const EventDetailsInvalid();
    state = state.copyWith(isSaving: true);

    // Let the active-employee seed settle before validating — otherwise a save
    // fired during the seed's read sees an empty selection and spuriously fails
    // "employees required" (or drops originals). Almost always already done.
    await _seedFuture;

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

    try {
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
        updated: updated,
        id: id,
        start: start,
        end: end,
        applyToSeries: applyToSeries,
      );
      // The doc now stores state.repeat — make it the new baseline.
      state = state.copyWith(savedRepeat: state.repeat);

      // Clean up images dropped in this edit only after the doc (which no
      // longer references them) has committed.
      await _deleteOrphanedImages(
        state.removedExistingImages,
        tag: 'APPT-SAVE',
      );

      if (state.newImages.isNotEmpty) {
        ref
            .read(appointmentImageUploadProvider)
            .uploadInBackground(
              appointmentId: id,
              newImages: state.newImages,
              existingImages: state.existingImages,
            );
      }

      state = state.copyWith(isSaving: false);
      return saved;
    } catch (e, st) {
      ref.read(loggerProvider).warn('APPT-SAVE saveChanges failed', e, st);
      state = state.copyWith(isSaving: false);
      return EventDetailsFailed(e);
    }
  }

  // Builds the edited AppointmentRecord from the form fields + resolved
  // assignees; the client falls back to the appointment's stored values when the
  // user didn't pick a new one.
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
      pictures: state.existingImages,
      status: state.editingStatus,
      repeat: state.repeat,
      seriesId: appointment.seriesId,
    );
  }

  // Persists the edit according to how the repeat changed: a full series rewrite
  // when the interval itself changed, a propagate across the series when
  // [applyToSeries] is set, otherwise a plain single-doc update. Returns the
  // resulting [EventDetailsSaved] outcome (the possibly-rewritten record plus the
  // one non-zero per-branch count for the result banner; the rest default to 0).
  Future<EventDetailsSaved> _applySeriesChange(
    AppointmentRecord appointment, {
    required AppointmentRecord updated,
    required String id,
    required DateTime start,
    required DateTime end,
    required bool applyToSeries,
  }) async {
    final seriesEditor = AppointmentSeriesEditor(
      ref.read(appointmentsRepositoryProvider),
    );
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
    await ref.read(appointmentsRepositoryProvider).updateAppointment(updated);
    return EventDetailsSaved(updated);
  }

  /// Returns null on success, or the error that caused the failure. With
  /// [includeFuture], also deletes the series' future visits (done/cancelled
  /// visits are preserved) in one atomic batch.
  Future<Object?> deleteAppointment(
    AppointmentRecord appointment, {
    bool includeFuture = false,
  }) async {
    final id = appointment.id;
    if (id == null) {
      return StateError('Cannot delete an appointment without an id.');
    }
    state = state.copyWith(isSaving: true);
    try {
      final repo = ref.read(appointmentsRepositoryProvider);
      final orphanedImages = <AppointmentImage>[...appointment.pictures];
      if (includeFuture && appointment.seriesId.isNotEmpty) {
        final series = await repo.getSeries(appointment.seriesId);
        final futureIds = futureSeriesIds(
          series,
          excludeId: id,
          after: appointment.startTime,
        );
        // Only the visits actually being deleted contribute orphaned bytes —
        // preserved past/terminal visits keep their pictures.
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

      // Clean up images only after the docs that referenced them are gone.
      await _deleteOrphanedImages(orphanedImages, tag: 'APPT-DEL');

      state = state.copyWith(isSaving: false);
      return null;
    } catch (e, st) {
      ref.read(loggerProvider).warn('APPT-DEL deleteAppointment failed', e, st);
      state = state.copyWith(isSaving: false);
      return e;
    }
  }

  /// Best-effort Storage cleanup for [images] the doc no longer references.
  /// A failure here only orphans bytes (harmless), so it's logged under [tag]
  /// — never rethrown — and must not fail the surrounding save/delete.
  Future<void> _deleteOrphanedImages(
    List<AppointmentImage> images, {
    required String tag,
  }) async {
    if (images.isEmpty) return;
    try {
      await ref.read(imageStorageProvider).deleteImages(images);
    } catch (e, st) {
      ref
          .read(loggerProvider)
          .warn('$tag deleteImages failed (orphaned bytes)', e, st);
    }
  }
}

final eventDetailsControllerProvider = NotifierProvider.autoDispose
    .family<EventDetailsController, EventDetailsState, AppointmentRecord>(
      EventDetailsController.new,
    );

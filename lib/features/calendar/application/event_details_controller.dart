import 'dart:io';

import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:scheduling/core/images/images_providers.dart';
import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/features/calendar/application/appointments_providers.dart';
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
import 'package:scheduling/shared/widgets/feedback/status_chip.dart'
    show AppointmentStatus;

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
  });
  final AppointmentRecord appointment;

  /// Pre-booked repeat occurrences created alongside the save.
  final int futureBookings;

  /// Old future occurrences deleted by a series rewrite.
  final int removedBookings;
}

class EventDetailsFailed extends EventDetailsSaveOutcome {
  const EventDetailsFailed(this.error);
  final Object error;
}

class EventDetailsController extends Notifier<EventDetailsState> {
  EventDetailsController(this.appointment);

  final AppointmentRecord appointment;

  @override
  EventDetailsState build() {
    Future.microtask(() => _loadClientIfNeeded(appointment.clientId));
    Future.microtask(() => _seedSelectedEmployees(appointment.employeeIds));
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
      // Prefer the already-live employees stream over opening a throwaway
      // Firestore listener just to read one value. An empty cached list is
      // treated as a miss — the provider emits const [] while authUid lags.
      final cached = ref.read(employeesStreamProvider).value;
      final all = cached == null || cached.isEmpty
          ? await ref.read(employeesRepositoryProvider).watchEmployees().first
          : cached;
      final selected = all.where((e) => employeeIds.contains(e.id)).toList();
      if (state.selectedEmployees.isEmpty) {
        state = state.copyWith(selectedEmployees: selected);
      }
    } catch (e, st) {
      ref.read(loggerProvider).warn('seedSelectedEmployees failed', e, st);
    }
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

  Future<EventDetailsSaveOutcome> save(
    AppointmentRecord appointment, {
    required String title,
    required String address,
    required String notes,
    required String materialsNeeded,
  }) async {
    final clientForValidation =
        state.selectedClient ??
        (!state.clientCleared && appointment.clientId.trim().isNotEmpty
            ? state.client ?? _placeholderClient(appointment)
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
    if (errors.isNotEmpty) return const EventDetailsInvalid();

    final id = appointment.id;
    if (id == null) {
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

    state = state.copyWith(isSaving: true);

    try {
      final pickedClient = state.selectedClient;
      var updated = AppointmentRecord(
        id: id,
        title: title.trim(),
        startTime: start,
        endTime: end,
        clientId: pickedClient?.id ?? appointment.clientId,
        clientName: pickedClient?.displayName ?? appointment.clientName,
        clientPhone: pickedClient?.phone ?? appointment.clientPhone,
        address: address.trim(),
        employeeIds: state.selectedEmployees.map((e) => e.id).toList(),
        employeeNames: state.selectedEmployees.map((e) => e.name).toList(),
        notes: notes.trim(),
        materialsNeeded: materialsNeeded.trim(),
        pictures: state.existingImages,
        status: state.editingStatus,
        repeat: state.repeat,
        seriesId: appointment.seriesId,
      );

      final repo = ref.read(appointmentsRepositoryProvider);
      var futureBookings = 0;
      var removedBookings = 0;
      if (state.repeat == state.savedRepeat) {
        await repo.updateAppointment(updated);
      } else {
        // The rule changed — rewrite the series like a real calendar: drop
        // the old future visits and book the new cadence in one atomic
        // batch. Done/cancelled visits are kept as records, and copies
        // start 'pending' without sharing pictures.
        final seriesId = appointment.seriesId.isEmpty
            ? id
            : appointment.seriesId;
        updated = updated.copyWith(seriesId: seriesId);
        final existing = appointment.seriesId.isEmpty
            ? const <AppointmentRecord>[]
            : await repo.getSeries(seriesId);
        final deleteIds = _futureSeriesIds(
          existing,
          excludeId: id,
          after: start,
        );
        final copies = [
          for (final copyStart in state.repeat.occurrenceStartsAfter(start))
            updated.copyWith(
              id: repo.newDocId(),
              startTime: copyStart,
              endTime: occurrenceEnd(
                originalStart: start,
                originalEnd: end,
                copyStart: copyStart,
              ),
              status: 'pending',
              pictures: const [],
            ),
        ];
        await repo.rewriteSeries(
          updated: updated,
          deleteIds: deleteIds,
          copies: copies,
        );
        futureBookings = copies.length;
        removedBookings = deleteIds.length;
      }
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
      return EventDetailsSaved(
        updated,
        futureBookings: futureBookings,
        removedBookings: removedBookings,
      );
    } catch (e, st) {
      ref.read(loggerProvider).warn('APPT-SAVE saveChanges failed', e, st);
      state = state.copyWith(isSaving: false);
      return EventDetailsFailed(e);
    }
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
        final futureIds = _futureSeriesIds(
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

/// Ids of the series visits after [after], skipping [excludeId] and any
/// visit already done or cancelled (those stay as records).
List<String> _futureSeriesIds(
  List<AppointmentRecord> series, {
  required String excludeId,
  required DateTime after,
}) => [
  for (final a in series)
    if (a.id != null &&
        a.id != excludeId &&
        a.startTime.isAfter(after) &&
        !AppointmentStatus.fromRaw(a.status).isTerminal)
      a.id!,
];

ClientRecord _placeholderClient(AppointmentRecord a) => ClientRecord(
  id: a.clientId,
  name: a.clientName,
  phone: a.clientPhone,
  address: a.address,
);

final eventDetailsControllerProvider = NotifierProvider.autoDispose
    .family<EventDetailsController, EventDetailsState, AppointmentRecord>(
      EventDetailsController.new,
    );

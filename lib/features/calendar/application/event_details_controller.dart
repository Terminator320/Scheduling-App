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
import 'package:scheduling/features/calendar/domain/policies/appointment_form_validator.dart';
import 'package:scheduling/features/clients/application/clients_providers.dart';
import 'package:scheduling/features/clients/domain/models/client_record.dart';
import 'package:scheduling/features/clients/domain/policies/client_search_policy.dart';
import 'package:scheduling/features/employees/application/employees_providers.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';

part 'event_details_controller.freezed.dart';

/// Form + view state for the appointment-details sheet. Owned by
/// `EventDetailsController` and watched from the widget shell + bodies.
///
/// `TextEditingController`s and `FocusNode`s stay in the widget — their
/// lifecycle ties to the widget's mount/unmount, not to this state.
@freezed
abstract class EventDetailsState with _$EventDetailsState {
  const factory EventDetailsState({
    required DateTime selectedDate,
    required TimeOfDay selectedStartTime,
    required TimeOfDay selectedEndTime,
    required String editingStatus,
    @Default(false) bool isEditing,
    @Default(<EmployeeRecord>[]) List<EmployeeRecord> selectedEmployees,
    @Default(<AppointmentImage>[]) List<AppointmentImage> existingImages,
    @Default(<AppointmentImage>[]) List<AppointmentImage> removedExistingImages,
    @Default(<File>[]) List<File> newImages,
    @Default(false) bool isSaving,
    ClientRecord? client,
    ClientRecord? selectedClient,
    @Default(<ClientRecord>[]) List<ClientRecord> clientResults,
    @Default(false) bool isSearchingClient,
    @Default(<String, AppointmentFormError>{})
    Map<String, AppointmentFormError> errors,
  }) = _EventDetailsState;
}

/// Result of `EventDetailsController.save` — encodes the three terminal
/// states the widget needs to react to.
sealed class EventDetailsSaveOutcome {
  const EventDetailsSaveOutcome();
}

/// Validation failed; `EventDetailsState.errors` holds per-field details.
class EventDetailsInvalid extends EventDetailsSaveOutcome {
  const EventDetailsInvalid();
}

/// Save succeeded. Widget should `Navigator.pop` with `appointment`.
/// Background photo upload has already been kicked off when relevant.
class EventDetailsSaved extends EventDetailsSaveOutcome {
  const EventDetailsSaved(this.appointment);
  final AppointmentRecord appointment;
}

/// Repo call threw. Widget should surface a SnackBar; controller has
/// already reset `isSaving` to false.
class EventDetailsFailed extends EventDetailsSaveOutcome {
  const EventDetailsFailed(this.error);
  final Object error;
}

/// State + actions for `details_edit_sheet`. Family-keyed by the
/// `AppointmentRecord` so each appointment opens with its own state slot.
class EventDetailsController
    extends AutoDisposeFamilyNotifier<EventDetailsState, AppointmentRecord> {
  @override
  EventDetailsState build(AppointmentRecord appointment) {
    // Seed async state after build() returns — direct awaits here would throw
    // because state mutations are illegal mid-build in Riverpod.
    Future.microtask(() => _loadClientIfNeeded(appointment.clientId));
    Future.microtask(() => _seedSelectedEmployees(appointment.employeeIds));
    return EventDetailsState(
      selectedDate: appointment.startTime,
      selectedStartTime: TimeOfDay.fromDateTime(appointment.startTime),
      selectedEndTime: TimeOfDay.fromDateTime(appointment.endTime),
      editingStatus: appointment.status,
      existingImages: List.of(appointment.pictures),
    );
  }

  Future<void> _seedSelectedEmployees(List<String> employeeIds) async {
    if (employeeIds.isEmpty) return;
    try {
      final all = await ref
          .read(employeesRepositoryProvider)
          .watchEmployees()
          .first;
      final selected = all.where((e) => employeeIds.contains(e.id)).toList();
      // Don't overwrite if the user has already toggled something.
      if (state.selectedEmployees.isEmpty) {
        state = state.copyWith(selectedEmployees: selected);
      }
    } catch (e, st) {
      // Sheet stays usable even if the employees stream errors out — log so
      // the silent fallback is visible in Crashlytics.
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
      if (client == null) return;
      // Don't overwrite a freshly-picked client mid-edit.
      if (state.selectedClient == null) {
        state = state.copyWith(client: client, selectedClient: client);
      } else {
        state = state.copyWith(client: client);
      }
    } catch (e, st) {
      // Keep the sheet usable even if the client doc fails to load — log so
      // the silent fallback is visible in Crashlytics.
      ref.read(loggerProvider).warn('loadClientIfNeeded failed', e, st);
    }
  }

  void enterEditing() =>
      state = state.copyWith(isEditing: true, errors: const {});

  void exitEditing() => state = state.copyWith(isEditing: false);

  void setSelectedEmployees(List<EmployeeRecord> employees) {
    state = state.copyWith(selectedEmployees: employees);
  }

  void selectDate(DateTime date) {
    state = state.copyWith(
      selectedDate: date,
      errors: _withoutKey(state.errors, 'date'),
    );
  }

  void selectStartTime(TimeOfDay time) {
    state = state.copyWith(
      selectedStartTime: time,
      errors: _withoutKey(state.errors, 'startTime'),
    );
  }

  void selectEndTime(TimeOfDay time) {
    state = state.copyWith(
      selectedEndTime: time,
      errors: _withoutKey(state.errors, 'endTime'),
    );
  }

  void setStatus(String status) {
    state = state.copyWith(editingStatus: status);
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
      errors: _withoutKey(state.errors, 'client'),
    );
  }

  void clearClient() {
    state = state.copyWith(
      selectedClient: null,
      client: null,
      clientResults: const [],
    );
  }

  void toggleEmployee(EmployeeRecord employee) {
    final current = state.selectedEmployees;
    final idx = current.indexWhere((e) => e.id == employee.id);
    final next = <EmployeeRecord>[...current];
    if (idx >= 0) {
      next.removeAt(idx);
    } else {
      next.add(employee);
    }
    state = state.copyWith(
      selectedEmployees: next,
      errors: next.isEmpty
          ? state.errors
          : _withoutKey(state.errors, 'employees'),
    );
  }

  /// Cap on attached images per appointment (existing + queued). Matches
  /// `AddEventController.maxImagesPerAppointment` so the cap is consistent
  /// across the create + edit paths.
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

  /// Marks the appointment as `done`. Returns true on success so the widget
  /// can `Navigator.pop`. On failure the widget shows a SnackBar.
  Future<bool> markAsDone(AppointmentRecord appointment) async {
    return _setStatusOnRepo(appointment, 'done');
  }

  /// Cancels the appointment (status = `cancelled`). Returns true on success.
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
      return true;
    } catch (e, st) {
      ref
          .read(loggerProvider)
          .warn('updateAppointmentStatus($status) failed', e, st);
      state = state.copyWith(isSaving: false);
      return false;
    }
  }

  /// Validates the form, updates Firestore, and (if applicable) deletes
  /// removed existing images and kicks off background upload of new ones.
  /// Pass the in-progress `TextEditingController` values from the widget.
  Future<EventDetailsSaveOutcome> save(
    AppointmentRecord appointment, {
    required String title,
    required String address,
    required String notes,
    required String materialsNeeded,
  }) async {
    // If the user hasn't re-selected a client, reconstruct one from the stored
    // appointment fields so the validator has something to check against.
    final clientForValidation =
        state.selectedClient ??
        (appointment.clientId.trim().isNotEmpty
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
      if (state.removedExistingImages.isNotEmpty) {
        await ref
            .read(imageStorageProvider)
            .deleteImages(state.removedExistingImages);
      }

      final pickedClient = state.selectedClient;
      final updated = AppointmentRecord(
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
      );

      await ref.read(appointmentsRepositoryProvider).updateAppointment(updated);

      if (state.newImages.isNotEmpty) {
        ref
            .read(appointmentImageUploadProvider)
            .uploadInBackground(
              appointmentId: id,
              newImages: state.newImages,
              existingImages: state.existingImages,
            );
      }

      return EventDetailsSaved(updated);
    } catch (e) {
      state = state.copyWith(isSaving: false);
      return EventDetailsFailed(e);
    }
  }

  /// Deletes the appointment. Returns true on success so the widget can
  /// `Navigator.pop`.
  Future<bool> deleteAppointment(AppointmentRecord appointment) async {
    final id = appointment.id;
    if (id == null) return false;
    state = state.copyWith(isSaving: true);
    try {
      await ref.read(appointmentsRepositoryProvider).deleteAppointment(id);
      return true;
    } catch (e, st) {
      ref.read(loggerProvider).warn('deleteAppointment failed', e, st);
      state = state.copyWith(isSaving: false);
      return false;
    }
  }
}

/// View-mode use only. Edit-mode flips `selectedClient` so the validator
/// always sees a real record for the client field.
ClientRecord _placeholderClient(AppointmentRecord a) => ClientRecord(
  id: a.clientId,
  name: a.clientName,
  phone: a.clientPhone,
  address: a.address,
);

final eventDetailsControllerProvider =
    AutoDisposeNotifierProviderFamily<
      EventDetailsController,
      EventDetailsState,
      AppointmentRecord
    >(EventDetailsController.new);

Map<String, AppointmentFormError> _withoutKey(
  Map<String, AppointmentFormError> errors,
  String key,
) {
  if (!errors.containsKey(key)) return errors;
  return Map<String, AppointmentFormError>.from(errors)..remove(key);
}

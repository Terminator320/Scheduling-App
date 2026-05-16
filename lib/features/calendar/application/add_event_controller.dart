import 'dart:io';

import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/features/calendar/application/appointments_providers.dart';
import 'package:scheduling/features/calendar/data/appointment_image_upload_service.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/calendar/domain/policies/appointment_form_validator.dart';
import 'package:scheduling/features/clients/application/clients_providers.dart';
import 'package:scheduling/features/clients/domain/models/client_record.dart';
import 'package:scheduling/features/clients/domain/policies/client_search_policy.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';

part 'add_event_controller.freezed.dart';

/// Form state for the new-appointment sheet. Owned by `AddEventController`
/// and watched from the widget shell.
///
/// `TextEditingController`s, `FocusNode`s, and the search-debounce timer
/// stay in the widget — they're UI primitives whose lifecycle ties to the
/// widget's mount/unmount, not to this state.
@freezed
abstract class AddEventState with _$AddEventState {
  const factory AddEventState({
    DateTime? selectedDate,
    TimeOfDay? selectedStartTime,
    TimeOfDay? selectedEndTime,
    @Default(false) bool endTimeWasPickedManually,
    ClientRecord? selectedClient,
    @Default(<ClientRecord>[]) List<ClientRecord> clientResults,
    @Default(false) bool isSearchingClient,
    @Default(false) bool useCustomAddress,
    @Default(<EmployeeRecord>[]) List<EmployeeRecord> selectedEmployees,
    @Default(<File>[]) List<File> selectedImages,
    @Default(false) bool isSubmitting,
    @Default(<String, AppointmentFormError>{})
    Map<String, AppointmentFormError> errors,
  }) = _AddEventState;
}

/// Result of `AddEventController.submit` — encodes the three terminal
/// states the widget needs to react to.
sealed class AddEventSubmitOutcome {
  const AddEventSubmitOutcome();
}

/// Validation failed; `AddEventState.errors` holds the per-field details.
class AddEventInvalid extends AddEventSubmitOutcome {
  const AddEventInvalid();
}

/// One or more selected employees already have a conflicting appointment in
/// the chosen window. The widget should show `showBusyConflictDialog` and
/// re-call `submit(forceBusy: true)` if the user confirms.
class AddEventBusyEmployees extends AddEventSubmitOutcome {
  const AddEventBusyEmployees({
    required this.busyEmployees,
    required this.start,
    required this.end,
  });
  final List<EmployeeRecord> busyEmployees;
  final DateTime start;
  final DateTime end;
}

/// Appointment was written to Firestore. The widget should `Navigator.pop`
/// with the returned `AppointmentRecord`. Background photo upload has
/// already been kicked off when relevant.
class AddEventSubmitted extends AddEventSubmitOutcome {
  const AddEventSubmitted(this.appointment);
  final AppointmentRecord appointment;
}

/// Repository call threw. Widget should surface a SnackBar and let the user
/// retry; controller has already reset `isSubmitting` to false.
class AddEventFailed extends AddEventSubmitOutcome {
  const AddEventFailed(this.error);
  final Object error;
}

/// State + actions for `add_appointment_sheet`. Family-keyed by the initial
/// date passed in by the caller so opening the sheet on different days
/// starts each form fresh (autoDispose tears state down on close).
class AddEventController
    extends AutoDisposeFamilyNotifier<AddEventState, DateTime?> {
  @override
  AddEventState build(DateTime? initialDate) {
    return AddEventState(selectedDate: initialDate);
  }

  void selectDate(DateTime date) {
    state = state.copyWith(
      selectedDate: date,
      errors: _withoutKey(state.errors, 'date'),
    );
  }

  /// Picking a start time auto-advances the end time by one hour, but only
  /// when the user hasn't manually picked the end yet.
  void selectStartTime(TimeOfDay time) {
    final auto = !state.endTimeWasPickedManually;
    state = state.copyWith(
      selectedStartTime: time,
      selectedEndTime: auto ? _addOneHour(time) : state.selectedEndTime,
      errors: _withoutKey(
        _withoutKey(state.errors, 'startTime'),
        auto ? 'endTime' : '_',
      ),
    );
  }

  void selectEndTime(TimeOfDay time) {
    state = state.copyWith(
      selectedEndTime: time,
      endTimeWasPickedManually: true,
      errors: _withoutKey(state.errors, 'endTime'),
    );
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
      clientResults: const [],
      useCustomAddress: false,
      errors: _withoutKey(state.errors, 'client'),
    );
  }

  void clearClient() {
    state = state.copyWith(
      selectedClient: null,
      clientResults: const [],
      useCustomAddress: false,
    );
  }

  void setUseCustomAddress(bool value) {
    state = state.copyWith(useCustomAddress: value);
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

  /// Cap on attached images per appointment. Prevents memory pressure on
  /// the compression/upload pipeline (each compressed image is held in RAM
  /// during `Future.wait` over `compressImages`).
  static const int maxImagesPerAppointment = 10;

  void addImages(List<File> files) {
    final remaining = maxImagesPerAppointment - state.selectedImages.length;
    if (remaining <= 0) return;
    final accepted = files.take(remaining).toList();
    state = state.copyWith(
      selectedImages: [...state.selectedImages, ...accepted],
    );
  }

  void removeImage(int index) {
    final next = [...state.selectedImages]..removeAt(index);
    state = state.copyWith(selectedImages: next);
  }

  /// Validates the form, checks for busy employees, and (if everything
  /// passes) writes the appointment to Firestore. Pass the in-progress
  /// values from the `TextEditingController`s as parameters — they live in
  /// the widget, not in state.
  ///
  /// `forceBusy: true` skips the busy-employees pre-check, which is what
  /// the widget passes after the user confirms `showBusyConflictDialog`.
  Future<AddEventSubmitOutcome> submit({
    required String title,
    required String address,
    required String notes,
    required String materialsNeeded,
    bool forceBusy = false,
  }) async {
    final errors = AppointmentFormValidator.validate(
      AppointmentFormInput(
        title: title,
        date: state.selectedDate,
        startTime: state.selectedStartTime,
        endTime: state.selectedEndTime,
        client: state.selectedClient,
        selectedEmployees: state.selectedEmployees,
      ),
    );
    state = state.copyWith(errors: errors);
    if (errors.isNotEmpty) return const AddEventInvalid();

    final start = combineDateAndTime(
      state.selectedDate!,
      state.selectedStartTime!,
    );
    final end = combineEndDateAndTime(
      state.selectedDate!,
      state.selectedEndTime!,
      state.selectedStartTime,
    );

    final repo = ref.read(appointmentsRepositoryProvider);

    if (!forceBusy) {
      final busy = await repo.findBusyEmployees(
        candidates: state.selectedEmployees,
        start: start,
        end: end,
      );
      if (busy.isNotEmpty) {
        return AddEventBusyEmployees(
          busyEmployees: busy,
          start: start,
          end: end,
        );
      }
    }

    state = state.copyWith(isSubmitting: true);

    try {
      final docId = repo.newDocId();
      final client = state.selectedClient!;
      final appointment = AppointmentRecord(
        id: docId,
        title: title.trim(),
        startTime: start,
        endTime: end,
        clientId: client.id,
        clientName: client.displayName,
        clientPhone: client.phone,
        address: address.trim(),
        employeeIds: state.selectedEmployees.map((e) => e.id).toList(),
        employeeNames: state.selectedEmployees.map((e) => e.name).toList(),
        notes: notes.trim(),
        materialsNeeded: materialsNeeded.trim(),
        // New appointments are pre-confirmed by the creator, not pending review.
        status: 'booked',
      );

      await repo.addAppointment(appointment);

      if (state.selectedImages.isNotEmpty) {
        ref
            .read(appointmentImageUploadProvider)
            .uploadInBackground(
              appointmentId: docId,
              newImages: state.selectedImages,
            );
      }

      return AddEventSubmitted(appointment);
    } catch (e, st) {
      ref.read(loggerProvider).warn('AddEventController.submit failed', e, st);
      state = state.copyWith(isSubmitting: false);
      return AddEventFailed(e);
    }
  }
}

final addEventControllerProvider =
    AutoDisposeNotifierProviderFamily<
      AddEventController,
      AddEventState,
      DateTime?
    >(AddEventController.new);

// ── helpers ─────────────────────────────────────────────────────────────

Map<String, AppointmentFormError> _withoutKey(
  Map<String, AppointmentFormError> errors,
  String key,
) {
  if (!errors.containsKey(key)) return errors;
  final next = Map<String, AppointmentFormError>.from(errors)..remove(key);
  return next;
}

// Wraps at the 24-hour boundary so appointments that start late at night
// can still auto-advance to the next hour without overflowing.
TimeOfDay _addOneHour(TimeOfDay time) {
  final totalMinutes = time.hour * 60 + time.minute + 60;
  final wrapped = totalMinutes % (24 * 60);
  return TimeOfDay(hour: wrapped ~/ 60, minute: wrapped % 60);
}

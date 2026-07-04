import 'dart:io';

import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/features/calendar/application/appointment_form_concerns.dart';
import 'package:scheduling/features/calendar/application/appointments_providers.dart';
import 'package:scheduling/features/calendar/data/appointment_image_upload_service.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/calendar/domain/models/repeat_interval.dart';
import 'package:scheduling/features/calendar/domain/policies/appointment_form_validator.dart';
import 'package:scheduling/features/calendar/utils/appointment_draft_defaults.dart';
import 'package:scheduling/features/clients/domain/models/client_record.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';

part 'add_event_controller.freezed.dart';

@freezed
abstract class AddEventState with _$AddEventState implements AppointmentFormFields {
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
    @Default(RepeatInterval.none) RepeatInterval repeat,
    @Default(<File>[]) List<File> selectedImages,
    @Default(false) bool isSubmitting,
    @Default(<String, AppointmentFormError>{})
    Map<String, AppointmentFormError> errors,
  }) = _AddEventState;
}

sealed class AddEventSubmitOutcome {
  const AddEventSubmitOutcome();
}

class AddEventInvalid extends AddEventSubmitOutcome {
  const AddEventInvalid();
}

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

class AddEventSubmitted extends AddEventSubmitOutcome {
  const AddEventSubmitted(this.appointment, {this.futureBookings = 0});
  final AppointmentRecord appointment;

  /// Pre-booked repeat occurrences created alongside [appointment].
  final int futureBookings;
}

class AddEventFailed extends AddEventSubmitOutcome {
  const AddEventFailed(this.error);
  final Object error;
}

class AddEventController extends Notifier<AddEventState>
    with AppointmentFormConcerns<AddEventState> {
  AddEventController(this.initialDate);

  final DateTime? initialDate;

  @override
  AddEventState build() {
    return AddEventState(selectedDate: initialDate);
  }

  // --- AppointmentFormConcerns adapters ---

  @override
  AddEventState applyFormUpdate(
    AddEventState current,
    AppointmentFormUpdate update,
  ) {
    var next = current.copyWith(
      clientResults: update.clientResults ?? current.clientResults,
      isSearchingClient: update.isSearchingClient ?? current.isSearchingClient,
      useCustomAddress: update.useCustomAddress ?? current.useCustomAddress,
      selectedEmployees: update.selectedEmployees ?? current.selectedEmployees,
      errors: update.errors ?? current.errors,
      selectedImages: update.pendingImages ?? current.selectedImages,
    );
    if (update.selectedClient != null) {
      next = next.copyWith(selectedClient: update.selectedClient);
    } else if (update.clearSelectedClient) {
      next = next.copyWith(selectedClient: null);
    }
    return next;
  }

  @override
  int get usedImageCount => state.selectedImages.length;

  @override
  List<File> get pendingImages => state.selectedImages;

  void removeImage(int index) => removePendingImageAt(index);

  void selectDate(DateTime date) {
    state = state.copyWith(
      selectedDate: date,
      errors: withoutKey(state.errors, 'date'),
    );
  }

  void selectStartTime(TimeOfDay time) {
    final auto = !state.endTimeWasPickedManually;
    var errors = withoutKey(state.errors, 'startTime');
    if (auto) errors = withoutKey(errors, 'endTime');
    state = state.copyWith(
      selectedStartTime: time,
      selectedEndTime: auto
          ? AppointmentDraftDefaults.defaultEndTime(time)
          : state.selectedEndTime,
      errors: errors,
    );
  }

  void selectEndTime(TimeOfDay time) {
    state = state.copyWith(
      selectedEndTime: time,
      endTimeWasPickedManually: true,
      errors: withoutKey(state.errors, 'endTime'),
    );
  }

  void selectRepeat(RepeatInterval value) {
    state = state.copyWith(repeat: value);
  }

  Future<AddEventSubmitOutcome> submit({
    required String title,
    required String address,
    required String notes,
    required String materialsNeeded,
    bool forceBusy = false,
  }) async {
    // Reentrancy guard: a second tap while a submit (including the conflict
    // check round-trip) is in flight must not create a duplicate appointment.
    if (state.isSubmitting) return const AddEventInvalid();
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
    // Resolved before the awaits — see searchClients.
    final logger = ref.read(loggerProvider);
    final uploader = ref.read(appointmentImageUploadProvider);
    // Snapshot everything read after an await: state on a disposed notifier
    // (sheet dismissed mid-submit) is unreadable.
    final images = state.selectedImages;
    final client = state.selectedClient!;
    final selectedEmployees = state.selectedEmployees;
    final repeat = state.repeat;

    // Mark in-flight before the conflict-check round-trip so the Save button
    // disables on the first tap and the guard above blocks a second tap.
    state = state.copyWith(isSubmitting: true);

    try {
      // Keep the conflict check inside the try: a throw here (offline /
      // permission-denied) must reset isSubmitting, or Save stays stuck
      // disabled and the reentrancy guard rejects every retry.
      if (!forceBusy) {
        final busy = await repo.findBusyEmployees(
          candidates: selectedEmployees,
          start: start,
          end: end,
        );
        if (busy.isNotEmpty) {
          // Hand off to the busy-confirm dialog — not an error — so clear the
          // in-flight flag and let the user decide whether to force.
          if (ref.mounted) state = state.copyWith(isSubmitting: false);
          return AddEventBusyEmployees(
            busyEmployees: busy,
            start: start,
            end: end,
          );
        }
      }

      final docId = repo.newDocId();
      final appointment = AppointmentRecord(
        id: docId,
        title: title.trim(),
        startTime: start,
        endTime: end,
        clientId: client.id,
        clientName: client.displayName,
        clientPhone: client.phone,
        address: address.trim(),
        employeeIds: selectedEmployees.map((e) => e.id).toList(),
        employeeNames: selectedEmployees.map((e) => e.name).toList(),
        notes: notes.trim(),
        materialsNeeded: materialsNeeded.trim(),
        repeat: repeat,
        seriesId: repeat == RepeatInterval.none ? '' : docId,
      );

      // Busy check covers only the first occurrence; repeats are months out.
      // Photos stay on the first visit only.
      final copies = [
        for (final copyStart in repeat.occurrenceStartsAfter(start))
          appointment.copyWith(
            id: repo.newDocId(),
            startTime: copyStart,
            endTime: occurrenceEnd(
              originalStart: start,
              originalEnd: end,
              copyStart: copyStart,
            ),
          ),
      ];

      if (copies.isEmpty) {
        await repo.addAppointment(appointment);
      } else {
        await repo.addAppointments([appointment, ...copies]);
      }

      if (images.isNotEmpty) {
        uploader.uploadInBackground(appointmentId: docId, newImages: images);
      }

      return AddEventSubmitted(appointment, futureBookings: copies.length);
    } catch (e, st) {
      logger.warn('APPT-CREATE submit failed', e, st);
      if (ref.mounted) state = state.copyWith(isSubmitting: false);
      return AddEventFailed(e);
    }
  }
}

final addEventControllerProvider = NotifierProvider.autoDispose
    .family<AddEventController, AddEventState, DateTime?>(
      AddEventController.new,
    );

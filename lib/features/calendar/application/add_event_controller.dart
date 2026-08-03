import 'dart:io';

import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:scheduling/core/connectivity/connectivity_providers.dart';
import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/core/utils/date_utils_helper.dart';
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
abstract class AddEventState
    with _$AddEventState
    implements AppointmentFormFields {
  const factory AddEventState({
    DateTime? selectedDate,
    DateTime? endDate,

    /// The user picked an end date explicitly, so it no longer mirrors the
    /// start — moving the start now SHIFTS it instead of collapsing the run.
    @Default(false) bool endDateTouched,
    TimeOfDay? selectedStartTime,
    TimeOfDay? selectedEndTime,
    @Default(false) bool endTimeWasPickedManually,
    ClientRecord? selectedClient,
    @Default(<ClientRecord>[]) List<ClientRecord> clientResults,
    @Default(false) bool isSearchingClient,
    @Default(false) bool useCustomAddress,
    @Default(false) bool isPersonal,
    @Default(false) bool isAllDay,
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
    return AddEventState(selectedDate: initialDate, endDate: initialDate);
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
      endDate: _shiftedEndDate(date),
      errors: withoutKey(withoutKey(state.errors, 'date'), 'endDate'),
    );
  }

  /// Where the end date lands when the start moves to [date].
  ///
  /// Untouched, it simply mirrors the start. Touched, the run keeps its
  /// LENGTH — a 5-day job stays 5 days rather than collapsing to one — which
  /// is why `endDateTouched` is tracked explicitly rather than inferred from
  /// the two dates being equal.
  DateTime _shiftedEndDate(DateTime date) {
    final previousStart = state.selectedDate;
    final previousEnd = state.endDate;
    if (!state.endDateTouched || previousStart == null || previousEnd == null) {
      return date;
    }
    final length = calendarDaysBetween(previousStart, previousEnd);
    return addCalendarDays(date, length < 0 ? 0 : length);
  }

  void selectEndDate(DateTime date) {
    state = state.copyWith(
      endDate: date,
      endDateTouched: true,
      errors: withoutKey(state.errors, 'endDate'),
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

  /// Turning this on drops any client already picked: the picker is hidden from
  /// here on, so a retained client would be saved invisibly.
  void setPersonal({required bool value}) {
    state = state.copyWith(
      isPersonal: value,
      selectedClient: value ? null : state.selectedClient,
      clientResults: value ? const [] : state.clientResults,
      useCustomAddress: !value && state.useCustomAddress,
      // The repeat picker is hidden for a personal job, so a value chosen
      // before the switch was flipped would silently pre-book a whole series.
      // Safe here because nothing is saved yet; the edit flow deliberately
      // keeps its repeat, where clearing it would rewrite a live series.
      repeat: value ? RepeatInterval.none : state.repeat,
      // "No time put in" is the default for a personal block, so it starts
      // all-day unless a time was already picked.
      isAllDay:
          value &&
          state.selectedStartTime == null &&
          state.selectedEndTime == null,
      errors: withoutKey(
        withoutKey(withoutKey(state.errors, 'client'), 'startTime'),
        'endTime',
      ),
    );
  }

  void setAllDay({required bool value}) {
    state = state.copyWith(
      isAllDay: value,
      errors: withoutKey(
        withoutKey(state.errors, 'startTime'),
        'endTime',
      ),
    );
  }

  Future<AddEventSubmitOutcome> submit({
    required String title,
    required String address,
    required String notes,
    required String materialsNeeded,
    bool forceBusy = false,
  }) async {
    // Guard against reentrancy: this blocks a double-tap during the conflict check and submit.
    if (state.isSubmitting) return const AddEventInvalid();
    final errors = AppointmentFormValidator.validate(
      AppointmentFormInput(
        title: title,
        date: state.selectedDate,
        endDate: state.endDate ?? state.selectedDate,
        startTime: state.selectedStartTime,
        endTime: state.selectedEndTime,
        client: state.selectedClient,
        selectedEmployees: state.selectedEmployees,
        isPersonal: state.isPersonal,
        isAllDay: state.isAllDay,
      ),
    );
    state = state.copyWith(errors: errors);
    if (errors.isNotEmpty) return const AddEventInvalid();

    // Bail out early if we're offline — otherwise Save just spins waiting for a server ack that never comes.
    if (ref.read(isOfflineProvider)) {
      return const AddEventFailed(SocketException('offline'));
    }

    final (:start, :end) = appointmentSpan(
      date: state.selectedDate!,
      endDate: state.endDate ?? state.selectedDate!,
      isAllDay: state.isAllDay,
      startTime: state.selectedStartTime,
      endTime: state.selectedEndTime,
    );

    final repo = ref.read(appointmentsRepositoryProvider);
    // Resolve these before any awaits, so we don't crash if the notifier gets disposed mid-await (Riverpod 3).
    final logger = ref.read(loggerProvider);
    final uploader = ref.read(appointmentImageUploadProvider);
    // Snapshot the state before the awaits, so it survives if the sheet gets dismissed mid-submit.
    final images = state.selectedImages;
    // Null for a personal job — the validator only demands a client otherwise.
    final client = state.selectedClient;
    final isPersonal = state.isPersonal;
    final selectedEmployees = state.selectedEmployees;
    final repeat = state.repeat;

    // Set the flag before the conflict check, so the Save button disables right away.
    state = state.copyWith(isSubmitting: true);

    try {
      // Keep the conflict check inside the try block, so an error there still resets the in-flight flag.
      if (!forceBusy) {
        final busy = await repo.findBusyEmployees(
          candidates: selectedEmployees,
          start: start,
          end: end,
        );
        if (busy.isNotEmpty) {
          // This isn't an error — let the user decide whether to force through the conflicts.
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
        clientId: client?.id ?? '',
        clientName: client?.displayName ?? '',
        clientPhone: client?.phone ?? '',
        // The address field is hidden for a personal job, so drop whatever the
        // controller still holds rather than saving a stale one.
        address: isPersonal ? '' : address.trim(),
        isPersonal: isPersonal,
        isAllDay: state.isAllDay,
        employeeIds: selectedEmployees.map((e) => e.id).toList(),
        employeeNames: selectedEmployees.map((e) => e.name).toList(),
        notes: notes.trim(),
        materialsNeeded: materialsNeeded.trim(),
        repeat: repeat,
        seriesId: repeat == RepeatInterval.none ? '' : docId,
      );

      // The conflict check only covers the first occurrence, and photos stay attached to that first visit.
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

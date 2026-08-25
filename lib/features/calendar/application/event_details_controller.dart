import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show listEquals;

import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:scheduling/core/connectivity/connectivity_providers.dart';
import 'package:scheduling/core/images/images_providers.dart';
import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/core/utils/date_utils_helper.dart';
import 'package:scheduling/features/auth/application/account_status_provider.dart';
import 'package:scheduling/features/calendar/application/appointment_form_concerns.dart';
import 'package:scheduling/features/calendar/application/appointments_providers.dart';
import 'package:scheduling/features/calendar/application/event_details_outcome.dart';
import 'package:scheduling/features/calendar/application/event_details_save_pipeline.dart';
import 'package:scheduling/features/calendar/application/event_series_helpers.dart';
import 'package:scheduling/features/calendar/data/appointment_image_upload_service.dart';
import 'package:scheduling/features/calendar/domain/appointment_day_slice.dart';
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
    required DateTime endDate,
    required TimeOfDay selectedStartTime,
    required TimeOfDay selectedEndTime,
    required String editingStatus,
    @Default(false) bool isEditing,

    /// An existing record already has a real end date, so unlike the add flow
    /// this starts true: moving the start date must preserve the run's LENGTH
    /// rather than collapse it to a single day.
    @Default(true) bool endDateTouched,
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
    @Default(false) bool isPersonal,
    @Default(false) bool isDayOff,
    @Default(false) bool isAllDay,
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

  /// The photo list this controller last put into [state], so the
  /// subcollection load can tell "the user has not touched these" from "they
  /// have". Compared BY VALUE: `existingImages` is a freezed collection getter
  /// that wraps the backing list in a NEW `EqualUnmodifiableListView` on every
  /// access, so an identity test could never be true and the read would always
  /// be discarded.
  List<AppointmentImage> _lastKnownImages = const [];

  @override
  EventDetailsState build() {
    // Re-seeded per build, so a rebuild while a read is in flight compares
    // against the list this build actually opened with.
    _lastKnownImages = const [];
    Future.microtask(() => _loadClientIfNeeded(appointment.clientId));
    Future.microtask(_loadStoredPictures);
    _seedFuture = Future.microtask(_enrichSelectedEmployees);
    return EventDetailsState(
      selectedDate: appointment.startTime,
      endDate: lastWorkDayOf(appointment),
      selectedStartTime: TimeOfDay.fromDateTime(appointment.startTime),
      selectedEndTime: TimeOfDay.fromDateTime(appointment.endTime),
      // storedRaw normalizes legacy/unknown status so save won't fail rules validation.
      editingStatus: AppointmentStatus.storedRaw(appointment.status),
      repeat: appointment.repeat,
      savedRepeat: appointment.repeat,
      isPersonal: appointment.isPersonal,
      isDayOff: appointment.isDayOff,
      isAllDay: appointment.isAllDay,
      // Seeded synchronously to avoid a race with the async load below — employee
      // visibility depends on employeeIds being set right away.
      selectedEmployees: _assigneesFromRecord(appointment),
    );
  }

  /// Reads this job's photos from `appointments/{id}/images`.
  ///
  /// The sheet opens with none: photos are not on the appointment document any
  /// more, so there is nothing to seed from and this read is the only source.
  /// It runs UNCONDITIONALLY — deliberately, and never gate it on
  /// `pictureCount`/`hasPictures` again. That counter's only writer is
  /// `recountAppointmentPictures`, which settles for 2 s before it even runs
  /// the aggregate, so a photo added seconds ago still reads as 0: the gate
  /// made a just-added photo invisible on reopen, and made a permanently
  /// failing parent write hide a job's photos forever. The counter stays the
  /// card indicator's cheap approximation, where being briefly behind costs
  /// nothing; the sheet pays one bounded `get` instead.
  ///
  /// Failure falls back to showing nothing rather than throwing: a photo strip
  /// that fails to load must not take the sheet down with it.
  Future<void> _loadStoredPictures() async {
    final id = appointment.id;
    if (id == null || id.isEmpty) return;
    final repo = ref.read(appointmentsRepositoryProvider);
    // Hoisted with `repo`: the `ref.mounted` check below proves disposal here
    // is real, and `ref.read` on a disposed notifier throws a StateError over
    // the failure it is trying to report.
    final logger = ref.read(loggerProvider);
    List<AppointmentImage> stored;
    try {
      stored = await repo.fetchAppointmentPictures(id);
    } catch (e, st) {
      logger.warn('APPT-IMG subcollection read failed', e, st);
      return;
    }
    if (stored.isEmpty || !ref.mounted) return;
    // Only adopt while the list is still exactly what this controller last put
    // there. A Storage-backed read is a real window, and the user can have
    // edited inside it - adopting then would silently restore what they
    // removed, and the next Save would act on a list they had already changed.
    // An emptiness test is NOT equivalent: with two loads in flight the first
    // adopts, a delete empties the list, and the second would put every photo
    // back.
    if (!listEquals(state.existingImages, _lastKnownImages)) return;
    state = state.copyWith(existingImages: _lastKnownImages = stored);
  }

  /// Builds placeholder employees from the stored ids and names. They get
  /// swapped for the full records once those load.
  static List<EmployeeRecord> _assigneesFromRecord(AppointmentRecord a) => [
    for (var i = 0; i < a.employeeIds.length; i++)
      EmployeeRecord(
        id: a.employeeIds[i],
        name: assigneeNameAt(a.employeeNames, i) ?? '',
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
      logger.warn('APPT-LOAD enrichSelectedEmployees failed', e, st);
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
      final docState = ref.read(currentUserDocProvider);
      if (docState.hasError) return;
      final doc = docState.isLoading
          ? await ref.read(currentUserDocProvider.future)
          : (docState.value ?? const <String, dynamic>{});
      if (!ref.mounted) return;
      final role = (doc['role'] ?? '').toString().trim();
      if (role != 'admin') return;
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
      logger.warn('APPT-LOAD loadClientIfNeeded failed', e, st);
    }
  }

  void enterEditing() =>
      state = state.copyWith(isEditing: true, errors: const {});

  void selectDate(DateTime date) {
    final length = calendarDaysBetween(state.selectedDate, state.endDate);
    state = state.copyWith(
      selectedDate: date,
      endDate: addCalendarDays(date, length < 0 ? 0 : length),
      errors: withoutKey(withoutKey(state.errors, 'date'), 'endDate'),
    );
  }

  void selectEndDate(DateTime date) {
    state = state.copyWith(
      endDate: date,
      endDateTouched: true,
      errors: withoutKey(state.errors, 'endDate'),
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

  void setAllDay({required bool value}) {
    state = state.copyWith(
      isAllDay: value,
      errors: withoutKey(withoutKey(state.errors, 'startTime'), 'endTime'),
    );
  }

  void setStatus(String status) {
    state = state.copyWith(editingStatus: status);
  }

  void selectRepeat(RepeatInterval value) {
    state = state.copyWith(repeat: value);
  }

  /// Marks the personal block as time off. Only reachable while the personal
  /// switch is on — see [setPersonal], which clears it on the way off.
  void setDayOff({required bool value}) {
    state = state.copyWith(isDayOff: value);
  }

  /// Flipping this on drops the client the same way the add flow does — the
  /// picker is hidden from here on, and `clientCleared` keeps `save()` from
  /// falling back to the stored one.
  void setPersonal({required bool value}) {
    state = state.copyWith(
      isPersonal: value,
      // Cleared on the way off for the same reason as the add flow: the chip
      // goes with the switch, so a surviving flag would be unreachable.
      isDayOff: value && state.isDayOff,
      selectedClient: value ? null : state.selectedClient,
      client: value ? null : state.client,
      clientCleared: value || state.clientCleared,
      clientResults: value ? const [] : state.clientResults,
      useCustomAddress: !value && state.useCustomAddress,
      // isAllDay is deliberately NOT cleared here. The all-day switch is shown
      // on every job now, not just personal ones, so the flag stays reachable
      // and repairable — clearing it would discard a deliberate choice.
      errors: withoutKey(state.errors, 'client'),
    );
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

  /// The write half of a save. Built per call so it closes over nothing.
  EventDetailsSavePipeline _pipeline() => EventDetailsSavePipeline(
    repo: ref.read(appointmentsRepositoryProvider),
    resolveStorage: () => ref.mounted ? ref.read(imageStorageProvider) : null,
    logger: ref.read(loggerProvider),
  );

  /// The final assignee list. The awaited active-employee read is the point —
  /// see [_resolveActiveEmployees].
  Future<({List<String> ids, List<String> names})> _resolveAssignees(
    AppointmentRecord appointment,
    EventDetailsSavePipeline pipeline,
  ) async {
    final activeEmployees = await _resolveActiveEmployees();
    return pipeline.resolveAssignees(
      appointment: appointment,
      selected: state.selectedEmployees,
      activeEmployees: activeEmployees,
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

    // Snapshot before the first await. The all-day switch stays live while a
    // save is in flight, and the instants below are DERIVED from this flag —
    // re-reading it afterwards could write `isAllDay: true` over a 09:00–17:00
    // window, which reads as "All day" on the card while the travel sweep skips
    // it and the crew gets no "time to leave" push.
    final isAllDay = state.isAllDay;

    // Resolve dependencies before the first await, so they survive the sheet
    // being dismissed (Riverpod 3).
    final repo = ref.read(appointmentsRepositoryProvider);
    final logger = ref.read(loggerProvider);
    final pipeline = _pipeline();
    // Only resolve the upload service if there are photos, so we skip
    // initializing FirebaseStorage otherwise.
    final uploader = state.newImages.isEmpty
        ? null
        : ref.read(appointmentImageUploadProvider);

    final invalid = await _settleAndValidate(
      appointment,
      title: title,
      isAllDay: isAllDay,
    );
    if (invalid != null) return invalid;

    final id = appointment.id;
    if (id == null) {
      state = state.copyWith(isSaving: false);
      return EventDetailsFailed(
        StateError('Cannot save an appointment without an id.'),
      );
    }

    final (:start, :end) = appointmentSpan(
      date: state.selectedDate,
      endDate: state.endDate,
      isAllDay: isAllDay,
      startTime: state.selectedStartTime,
      endTime: state.selectedEndTime,
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

      final assignees = await _resolveAssignees(appointment, pipeline);
      final updated = pipeline.buildUpdatedRecord(
        appointment,
        id: id,
        title: title,
        address: address,
        notes: notes,
        materialsNeeded: materialsNeeded,
        start: start,
        end: end,
        assignees: assignees,
        selectedClient: state.selectedClient,
        status: state.editingStatus,
        repeat: state.repeat,
        isPersonal: state.isPersonal,
        isDayOff: state.isDayOff,
        isAllDay: isAllDay,
      );

      final saved = await pipeline.applySeriesChange(
        appointment,
        updated: updated,
        id: id,
        start: start,
        end: end,
        applyToSeries: applyToSeries,
        repeat: state.repeat,
        savedRepeat: state.savedRepeat,
      );

      await pipeline.applyPhotoChanges(
        id: id,
        uploader: uploader,
        removedImages: removedImages,
        newImages: newImages,
        // The repeat baseline for the NEXT edit — state, so it stays here.
        onRecordWritten: () {
          if (ref.mounted) state = state.copyWith(savedRepeat: state.repeat);
        },
      );

      if (ref.mounted) state = state.copyWith(isSaving: false);
      return saved;
    } catch (e, st) {
      logger.warn('APPT-SAVE saveChanges failed', e, st);
      if (ref.mounted) state = state.copyWith(isSaving: false);
      return EventDetailsFailed(e);
    }
  }

  /// Waits for the seed to settle, then validates the form. Returns a stop
  /// outcome if it's invalid, or null to keep going.
  /// [isAllDay] is passed rather than re-read: it is the value [save]
  /// snapshotted, so the form is validated against the same flag the instants
  /// and the record are built from.
  Future<EventDetailsSaveOutcome?> _settleAndValidate(
    AppointmentRecord appointment, {
    required String title,
    required bool isAllDay,
  }) async {
    // Wait for enrichment to finish, so assignee resolution reads a warm active-employee list.
    await _seedFuture;
    if (!ref.mounted) return const EventDetailsInvalid();

    final clientForValidation = state.isPersonal
        ? null
        : state.selectedClient ??
              (!state.clientCleared && appointment.clientId.trim().isNotEmpty
                  ? state.client ?? placeholderClient(appointment)
                  : null);

    final errors = AppointmentFormValidator.validate(
      AppointmentFormInput(
        title: title,
        date: state.selectedDate,
        endDate: state.endDate,
        startTime: state.selectedStartTime,
        endTime: state.selectedEndTime,
        client: clientForValidation,
        selectedEmployees: state.selectedEmployees,
        isPersonal: state.isPersonal,
        isAllDay: isAllDay,
      ),
    );
    state = state.copyWith(errors: errors);
    if (errors.isNotEmpty) {
      state = state.copyWith(isSaving: false);
      return const EventDetailsInvalid();
    }
    return null;
  }

  /// Deletes the visit and returns a sealed outcome. When [includeFuture] is
  /// set, this also deletes the series' future visits in one batch
  /// (done/cancelled visits are preserved).
  ///
  /// It returns [EventDetailsActionOutcome] rather than a nullable error for
  /// the same reason the status setters do: `null` meant BOTH "deleted" and
  /// "skipped by the reentrancy guard", so a skipped delete announced
  /// "Appointment deleted" and closed the sheet without having written
  /// anything.
  Future<EventDetailsActionOutcome> deleteAppointment(
    AppointmentRecord appointment, {
    bool includeFuture = false,
  }) async {
    final id = appointment.id;
    if (id == null) {
      return EventDetailsActionFailed(
        StateError('Cannot delete an appointment without an id.'),
      );
    }
    // Reject a double-tap on the delete — same reentrancy guard save() and the
    // status writes use. Without it a second run pays getSeries and the batch
    // delete all over again.
    if (state.isSaving) return const EventDetailsActionBusy();
    state = state.copyWith(isSaving: true);
    // Resolve these before the first await, so they survive the sheet being dismissed.
    final repo = ref.read(appointmentsRepositoryProvider);
    final logger = ref.read(loggerProvider);
    try {
      // Photos are NOT cleaned up here. Deleting the appointment document fires
      // `cascadeDeleteAppointmentImages`, which removes both the photo
      // documents and the Storage objects under
      // `appointments/{id}/images/`. That moved server-side at the CONTRACT
      // step for a plain reason: this used to enumerate `appointment.pictures`
      // to know which objects to delete, and that array no longer exists — a
      // client that is not reading the subcollection cannot list what to
      // remove. The trigger also covers the series branch below (each deleted
      // document fires its own) and the bytes of a photo whose document link
      // never landed, which the array never could.
      if (includeFuture && appointment.seriesId.isNotEmpty) {
        final series = await repo.getSeries(appointment.seriesId);
        final futureIds = futureSeriesIds(
          series,
          excludeId: id,
          after: appointment.startTime,
        );
        await repo.deleteAppointments([id, ...futureIds]);
      } else {
        await repo.deleteAppointment(id);
      }

      if (ref.mounted) state = state.copyWith(isSaving: false);
      return const EventDetailsActionOk();
    } catch (e, st) {
      logger.warn('APPT-DEL deleteAppointment failed', e, st);
      if (ref.mounted) state = state.copyWith(isSaving: false);
      return EventDetailsActionFailed(e);
    }
  }
}

final eventDetailsControllerProvider = NotifierProvider.autoDispose
    .family<EventDetailsController, EventDetailsState, EventDetailsKey>(
      EventDetailsController.new,
    );

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scheduling/core/adaptive/adaptive_pickers.dart';
import 'package:scheduling/core/errors/error_cause.dart';
import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/core/notices/notice_service.dart';
import 'package:scheduling/core/theme/button_styles.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/core/utils/date_utils_helper.dart';
import 'package:scheduling/core/utils/debouncer.dart';
import 'package:scheduling/features/calendar/application/appointments_providers.dart';
import 'package:scheduling/features/calendar/application/event_details_controller.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/calendar/domain/policies/appointment_form_validator.dart';
import 'package:scheduling/features/calendar/domain/series_outlook.dart';
import 'package:scheduling/features/calendar/widgets/dialogs/busy_conflict_dialog.dart';
import 'package:scheduling/features/calendar/widgets/dialogs/delete_appointment_dialog.dart';
import 'package:scheduling/features/calendar/widgets/dialogs/series_scope_dialog.dart';
import 'package:scheduling/features/calendar/widgets/fields/repeat_interval_picker.dart';
import 'package:scheduling/features/calendar/widgets/sections/appointment_form_fields.dart';
import 'package:scheduling/features/calendar/widgets/sections/photo_picker_section.dart';
import 'package:scheduling/features/calendar/widgets/sheets/image_source_picker.dart';
import 'package:scheduling/features/calendar/widgets/sheets/inline_add_client_host.dart';
import 'package:scheduling/features/employees/application/employees_providers.dart';
import 'package:scheduling/features/maps/domain/address_parser.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/sheets/form_sheet_frame.dart';

class DetailsEditBody extends ConsumerStatefulWidget {
  const DetailsEditBody({
    required this.appointment,
    required this.controllers,
    required this.onSaved,
    required this.onClose,
    super.key,
  });

  final AppointmentRecord appointment;
  final AppointmentFormControllers controllers;
  final ValueChanged<AppointmentRecord> onSaved;
  final VoidCallback onClose;

  @override
  ConsumerState<DetailsEditBody> createState() => _DetailsEditBodyState();
}

class _DetailsEditBodyState extends ConsumerState<DetailsEditBody>
    with InlineAddClientHost {
  late final Debouncer _clientSearchDebounce;

  @override
  void initState() {
    super.initState();
    _clientSearchDebounce = Debouncer.tagged(
      kSearchDebounce,
      logger: ref.read(loggerProvider),
      tag: 'CLI-SEARCH debounced client search failed',
    );
  }

  @override
  void dispose() {
    _clientSearchDebounce.dispose();
    super.dispose();
  }

  // Debounce so comprehensive client search doesn't fire a Firestore read on every keystroke.
  void _onClientSearchChanged(String query) {
    final notifier = ref.read(
      eventDetailsControllerProvider(
        EventDetailsKey(widget.appointment),
      ).notifier,
    );
    if (query.trim().isEmpty) {
      _clientSearchDebounce.cancel();
      notifier.searchClients('');
      return;
    }
    _clientSearchDebounce.run(() => notifier.searchClients(query));
  }

  @override
  Widget build(BuildContext context) {
    final appointment = widget.appointment;
    final controllers = widget.controllers;
    final provider = eventDetailsControllerProvider(
      EventDetailsKey(appointment),
    );
    final state = ref.watch(provider);
    final notifier = ref.read(provider.notifier);
    final allEmployees =
        ref.watch(employeesStreamProvider).asData?.value ?? const [];
    // One length feeds both the flag and the label, so they can't disagree:
    // the run-length string is a plain interpolation, and a multi-day flag
    // paired with a length of 1 would render "1 days".
    final spanLength = runLengthDays(state.selectedDate, state.endDate);

    return FormSheetFrame(
      title: context.l10n.calendar_editAppointment,
      primaryLabel: context.l10n.common_saveChanges,
      isBusy: state.isSaving,
      onPrimary: () => _save(context, ref),
      onCancel: widget.onClose,
      children: [
        AppointmentFormFields(
          controllers: controllers,
          allEmployees: allEmployees,
          selectedClient: state.selectedClient,
          clientResults: state.clientResults,
          isSearchingClient: state.isSearchingClient,
          selectedEmployees: state.selectedEmployees,
          repeat: state.repeat,
          useCustomAddress: state.useCustomAddress,
          selectedDate: state.selectedDate,
          endDate: state.endDate,
          isPersonal: state.isPersonal,
          isAllDay: state.isAllDay,
          onAllDayChanged: (value) => notifier.setAllDay(value: value),
          // Offered only on a job that was already personal, so an ordinary
          // client visit can't be converted mid-life (which would wipe its
          // client).
          onPersonalChanged: appointment.isPersonal
              ? (value) => notifier.setPersonal(value: value)
              : null,
          errors: state.errors,
          employeeLabel: context.l10n.calendar_assignedEmployee,
          employeeRequired: false,
          materialsHint: context.l10n.calendar_eGPipeWrenchTapeCommaSeparated,
          editingStatus: state.editingStatus,
          onStatusChanged: notifier.setStatus,
          onRequestAddClient: requestAddClient,
          isMultiDay: spanLength > 1,
          isOvernight:
              !state.isAllDay &&
              isOvernightWindow(state.selectedStartTime, state.selectedEndTime),
          spanLength: spanLength,
          callbacks: AppointmentFormCallbacks(
            onSearchClients: _onClientSearchChanged,
            onSelectClient: notifier.selectClient,
            onClearClient: notifier.clearClient,
            onToggleEmployee: notifier.toggleEmployee,
            onSelectStartDate: (picked) =>
                _onStartDateSelected(notifier, picked),
            onSelectEndDate: (picked) => _onEndDateSelected(notifier, picked),
            onPickStartTime: () => _pickStartTime(context, state, notifier),
            onPickEndTime: () => _pickEndTime(context, state, notifier),
            onSelectRepeat: notifier.selectRepeat,
            onUseCustomAddress: (value) =>
                notifier.setUseCustomAddress(value: value),
          ),
          photosSection: _EditPhotosSection(appointment: appointment),
        ),
        const SizedBox(height: AppSpacing.sp24),
        // Destructive actions live in the footer, never in the bar.
        _DeleteButton(
          isSaving: state.isSaving,
          onDelete: () => _confirmDelete(context, ref),
        ),
      ],
    );
  }

  /// The date rows drop an inline month calendar down beneath themselves, so a
  /// date arrives already picked — no modal to await, no cancelled outcome.
  void _onStartDateSelected(EventDetailsController notifier, DateTime picked) {
    // No setState around the controller writes: the body watches the
    // controller provider and `selectDate` always emits a new state, so the
    // rebuild is already coming. This matches `_pickStartTime` below.
    widget.controllers.date.text = DateUtilsHelper.formatDate(picked);
    notifier.selectDate(picked);
    // selectDate shifts the end date to preserve the run's length, and the end
    // row renders the controller text — so it has to follow, or it goes stale.
    final shifted = ref
        .read(
          eventDetailsControllerProvider(EventDetailsKey(widget.appointment)),
        )
        .endDate;
    widget.controllers.endDate.text = DateUtilsHelper.formatDate(shifted);
  }

  void _onEndDateSelected(EventDetailsController notifier, DateTime picked) {
    widget.controllers.endDate.text = DateUtilsHelper.formatDate(picked);
    notifier.selectEndDate(picked);
  }

  Future<void> _pickStartTime(
    BuildContext context,
    EventDetailsState state,
    EventDetailsController notifier,
  ) async {
    final picked = await showAdaptiveTimePicker(
      context,
      initialTime: state.selectedStartTime,
    );
    if (picked == null || !context.mounted) return;
    widget.controllers.startTime.text = picked.format(context);
    notifier.selectStartTime(picked);
  }

  Future<void> _pickEndTime(
    BuildContext context,
    EventDetailsState state,
    EventDetailsController notifier,
  ) async {
    final picked = await showAdaptiveTimePicker(
      context,
      initialTime: state.selectedEndTime,
    );
    if (picked == null || !context.mounted) return;
    widget.controllers.endTime.text = picked.format(context);
    notifier.selectEndTime(picked);
  }

  /// The occurrences a "this and all future" save would touch. A failed count
  /// must never block the edit, so this degrades to an empty outlook and the
  /// dialog just renders without its consequence lines.
  Future<({int count, DateTime? last})> _seriesOutlook(
    WidgetRef ref,
    AppointmentRecord appointment,
  ) async {
    // Both reads happen before the await: this method promises to degrade to
    // an empty outlook rather than block the edit, and a `ref.read` in the
    // catch would defeat exactly that once the sheet has been dismissed
    // mid-fetch (Riverpod 3 throws on an unmounted consumer).
    final repository = ref.read(appointmentsRepositoryProvider);
    final logger = ref.read(loggerProvider);
    try {
      final series = await repository.getSeries(appointment.seriesId);
      return seriesOutlook(series, appointment.startTime);
    } on Object catch (e, st) {
      logger.warn('APPT-SAVE series outlook failed', e, st);
      return (count: 0, last: null);
    }
  }

  Future<void> _save(BuildContext context, WidgetRef ref) async {
    final appointment = widget.appointment;
    final provider = eventDetailsControllerProvider(
      EventDetailsKey(appointment),
    );
    final notifier = ref.read(provider.notifier);

    final state = ref.read(provider);
    if (state.isSaving) return; // a save (or its prompt) is already in flight

    final applyToSeries = await _resolveSeriesScope(context, ref, state);
    // null means the admin dismissed the scope dialog, or the sheet went away
    // while it was open — either way there is nothing to save.
    if (applyToSeries == null || !context.mounted) return;

    // An unnamed personal block saves as "Personal" — same rule as the add
    // flow, since the stored title is what every read surface falls back to.
    final title =
        widget.controllers.title.text.trim().isEmpty && state.isPersonal
        ? context.l10n.calendar_personal
        : widget.controllers.title.text;

    Future<EventDetailsSaveOutcome> attempt({bool forceBusy = false}) =>
        notifier.save(
          appointment,
          title: title,
          address: AddressParser.toCanonical(widget.controllers.address.text),
          notes: widget.controllers.notes.text,
          materialsNeeded: widget.controllers.materials.text,
          applyToSeries: applyToSeries,
          forceBusy: forceBusy,
        );

    var outcome = await attempt();
    if (!context.mounted) return;
    if (outcome is EventDetailsBusyEmployees) {
      final confirmed = await showBusyConflictDialog(
        context,
        busyEmployees: outcome.busyEmployees,
        start: outcome.start,
        end: outcome.end,
      );
      if (!confirmed || !context.mounted) return;
      outcome = await attempt(forceBusy: true);
      if (!context.mounted) return;
    }
    _announce(context, ref, outcome);
  }

  /// Asks whether an edit to a repeating visit applies to this visit only or
  /// to future ones too, and returns that as `applyToSeries`.
  ///
  /// **`null` means "stop"** — the admin dismissed the dialog, or the sheet was
  /// torn down while it was open. `false` is a real answer, not an absence.
  ///
  /// Split out of [_save] because it owns a busy-flag handoff of its own: the
  /// form is marked busy for the duration so a second tap cannot stack a
  /// duplicate dialog, and every exit from here — including the mounted bail —
  /// has to clear it before `save()` takes the flag over.
  ///
  /// Skipped entirely when the repeat RULE is what changed: that rewrites the
  /// whole series regardless, so there is nothing to ask.
  Future<bool?> _resolveSeriesScope(
    BuildContext context,
    WidgetRef ref,
    EventDetailsState state,
  ) async {
    final appointment = widget.appointment;
    if (appointment.seriesId.isEmpty || state.repeat != state.savedRepeat) {
      return false;
    }
    final provider = eventDetailsControllerProvider(
      EventDetailsKey(appointment),
    );
    // Busied for the whole dialog, so a second tap can't stack a duplicate.
    final notifier = ref.read(provider.notifier)..setSaving(busy: true);
    // One extra read per series edit — an admin action — so the dialog's
    // consequence line and button count are true rather than decorative.
    final outlook = await _seriesOutlook(ref, appointment);
    if (!context.mounted) {
      notifier.setSaving(busy: false);
      return null;
    }
    final choice = await showSeriesScopeDialog(
      context,
      title: context.l10n.calendar_applyChangesTo,
      contextLabel: context.l10n.calendar_repeatsEveryLabel(
        repeatIntervalLabel(context.l10n, state.repeat).toUpperCase(),
      ),
      thisOnlyLabel: context.l10n.calendar_editThisVisitOnly,
      thisAndFutureLabel: context.l10n.calendar_editThisAndFutureVisits,
      thisOnlyDetail: context.l10n.calendar_thisVisitKeepsSeries(
        DateUtilsHelper.formatDate(appointment.startTime),
      ),
      thisAndFutureDetail: outlook.last == null
          ? null
          : context.l10n.calendar_remainingVisitsThrough(
              outlook.count,
              DateUtilsHelper.formatDate(outlook.last!),
            ),
      primaryLabelFor: (choice) => choice == SeriesScopeChoice.thisOnly
          ? context.l10n.calendar_saveThisVisit
          : context.l10n.calendar_saveNVisits(outlook.count),
    );
    // Reset before the mounted guard — the notifier is context-free, and
    // bailing while still busy would wedge a surviving controller.
    notifier.setSaving(busy: false);
    if (!context.mounted || choice == null) return null;
    return choice == SeriesScopeChoice.thisAndFuture;
  }

  /// Turns a settled save outcome into the one notice it earns.
  ///
  /// Both no-op outcomes surface NOTHING: `Invalid` is already shown as field
  /// errors, and `BusyEmployees` was resolved above — the dialog either forced
  /// a retry or the admin backed out.
  void _announce(
    BuildContext context,
    WidgetRef ref,
    EventDetailsSaveOutcome outcome,
  ) {
    switch (outcome) {
      case EventDetailsInvalid() || EventDetailsBusyEmployees():
        return;
      case EventDetailsSaved(
        :final appointment,
        :final futureBookings,
        :final removedBookings,
        :final updatedSiblings,
      ):
        final l10n = context.l10n;
        final message = futureBookings > 0
            ? l10n.calendar_changesSavedWithRepeats(futureBookings)
            : removedBookings > 0
            ? l10n.calendar_changesSavedWithRemoved(removedBookings)
            : updatedSiblings > 0
            ? l10n.calendar_changesAppliedToSeries(updatedSiblings)
            : l10n.common_appointmentChangesSaved;
        ref.read(noticeServiceProvider).success(message);
        widget.onSaved(appointment);
      case EventDetailsFailed(:final error):
        ref
            .read(noticeServiceProvider)
            .error(
              composeErrorNotice(
                context,
                intro: context.l10n.error_introSaveAppointment,
                error: error,
              ),
            );
    }
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final appointment = widget.appointment;
    // Busied for the whole dialog, so a second tap can't stack a duplicate —
    // the same handoff [_resolveSeriesScope] does.
    final notifier = ref.read(
      eventDetailsControllerProvider(EventDetailsKey(appointment)).notifier,
    )..setSaving(busy: true);
    final choice = await showDeleteAppointmentDialog(
      context,
      isSeries: appointment.seriesId.isNotEmpty,
    );
    // Cleared before the mounted guard (the notifier is context-free, and
    // bailing while busy would wedge a surviving controller) and before the
    // call below, which now refuses while the flag is set.
    notifier.setSaving(busy: false);
    if (choice == null || !context.mounted) return;
    final outcome = await notifier.deleteAppointment(
      appointment,
      includeFuture: choice == SeriesScopeChoice.thisAndFuture,
    );
    if (!context.mounted) return;
    switch (outcome) {
      // A delete skipped by the reentrancy guard wrote nothing, so it must
      // announce nothing — neither the success notice nor an error.
      case EventDetailsActionBusy():
        return;
      case EventDetailsActionOk():
        ref
            .read(noticeServiceProvider)
            .success(context.l10n.common_appointmentDeleted);
        widget.onClose();
      case EventDetailsActionFailed(:final error):
        ref
            .read(noticeServiceProvider)
            .error(
              composeErrorNotice(
                context,
                intro: context.l10n.error_introDeleteAppointment,
                error: error,
              ),
            );
    }
  }
}

class _DeleteButton extends StatelessWidget {
  const _DeleteButton({required this.isSaving, required this.onDelete});

  final bool isSaving;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => OutlinedButton(
    style: destructiveOutlinedButtonStyle(
      context,
      minimumSize: const Size(double.infinity, 48),
    ),
    onPressed: isSaving ? null : onDelete,
    child: Text(context.l10n.calendar_deleteAppointment),
  );
}

class _EditPhotosSection extends ConsumerWidget {
  const _EditPhotosSection({required this.appointment});

  final AppointmentRecord appointment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = eventDetailsControllerProvider(
      EventDetailsKey(appointment),
    );
    final existingImages = ref.watch(provider.select((s) => s.existingImages));
    final newImages = ref.watch(provider.select((s) => s.newImages));
    final notifier = ref.read(provider.notifier);
    return PhotoPickerSection(
      existingImages: existingImages,
      newImages: newImages,
      isEditing: true,
      onPickImages: () async {
        final picked = await pickAppointmentImages(context, ref);
        // The longest await in the app — an OS action sheet and then the
        // camera/Photos picker. The notifier is autoDispose.family, so
        // calling it after this view was torn down under the picker throws a
        // StateError out of an unawaited callback, filed as FATAL.
        if (!context.mounted) return;
        if (picked.isNotEmpty) notifier.addImages(picked);
      },
      onRemoveExisting: notifier.removeExistingImage,
      onRemoveNew: notifier.removeNewImage,
    );
  }
}

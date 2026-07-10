import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scheduling/core/animations/animated_loading_button.dart';
import 'package:scheduling/core/errors/error_cause.dart';
import 'package:scheduling/core/notices/notice_service.dart';
import 'package:scheduling/core/theme/button_styles.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/core/utils/date_utils_helper.dart';
import 'package:scheduling/core/utils/debouncer.dart';
import 'package:scheduling/features/calendar/application/event_details_controller.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/calendar/utils/adaptive_pickers.dart';
import 'package:scheduling/features/calendar/utils/appointment_draft_defaults.dart';
import 'package:scheduling/features/calendar/widgets/dialogs/delete_appointment_dialog.dart';
import 'package:scheduling/features/calendar/widgets/dialogs/series_scope_dialog.dart';
import 'package:scheduling/features/calendar/widgets/sections/appointment_form_fields.dart';
import 'package:scheduling/features/calendar/widgets/sections/photo_picker_section.dart';
import 'package:scheduling/features/calendar/widgets/sheets/image_source_picker.dart';
import 'package:scheduling/features/calendar/widgets/sheets/inline_add_client_host.dart';
import 'package:scheduling/features/employees/application/employees_providers.dart';
import 'package:scheduling/features/maps/domain/address_parser.dart';
import 'package:scheduling/l10n/l10n.dart';

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
  final _clientSearchDebounce = Debouncer(const Duration(milliseconds: 300));

  @override
  void dispose() {
    _clientSearchDebounce.dispose();
    super.dispose();
  }

  // Mirrors the add sheet: debounce so the comprehensive client search doesn't
  // fire a Firestore read on every keystroke.
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
    final theme = Theme.of(context);
    final appointment = widget.appointment;
    final controllers = widget.controllers;
    final provider = eventDetailsControllerProvider(
      EventDetailsKey(appointment),
    );
    final state = ref.watch(provider);
    final notifier = ref.read(provider.notifier);
    final allEmployees =
        ref.watch(employeesStreamProvider).asData?.value ?? const [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // --- Header ---
        Text(
          context.l10n.calendar_editAppointment,
          style: theme.textTheme.headlineLarge,
        ),
        const SizedBox(height: AppSpacing.sp16),
        const Divider(height: 1),
        const SizedBox(height: AppSpacing.sp16),
        // --- Shared form fields ---
        AppointmentFormFields(
          controllers: controllers,
          allEmployees: allEmployees,
          selectedClient: state.selectedClient,
          clientResults: state.clientResults,
          isSearchingClient: state.isSearchingClient,
          selectedEmployees: state.selectedEmployees,
          repeat: state.repeat,
          useCustomAddress: state.useCustomAddress,
          errors: state.errors,
          employeeLabel: context.l10n.calendar_assignedEmployee,
          employeeRequired: false,
          materialsHint: context.l10n.calendar_eGPipeWrenchTapeCommaSeparated,
          editingStatus: state.editingStatus,
          onStatusChanged: notifier.setStatus,
          onSearchClients: _onClientSearchChanged,
          onSelectClient: notifier.selectClient,
          onClearClient: notifier.clearClient,
          onRequestAddClient: requestAddClient,
          onToggleEmployee: notifier.toggleEmployee,
          onPickDate: () => _pickDate(context, state, notifier),
          onPickStartTime: () => _pickStartTime(context, state, notifier),
          onPickEndTime: () => _pickEndTime(context, state, notifier),
          onSelectRepeat: notifier.selectRepeat,
          onUseCustomAddress: (value) =>
              notifier.setUseCustomAddress(value: value),
          photosSection: _EditPhotosSection(appointment: appointment),
        ),
        const SizedBox(height: AppSpacing.sp24),
        // --- Actions ---
        _ActionButtons(
          isSaving: state.isSaving,
          onSave: () => _save(context, ref),
          onDelete: () => _confirmDelete(context, ref),
        ),
      ],
    );
  }

  Future<void> _pickDate(
    BuildContext context,
    EventDetailsState state,
    EventDetailsController notifier,
  ) async {
    final picked = await showAdaptiveDatePicker(
      context,
      initialDate: state.selectedDate,
      firstDate: AppointmentDraftDefaults.datePickerFirstDate,
      lastDate: AppointmentDraftDefaults.datePickerLastDate,
    );
    if (picked == null) return;
    widget.controllers.date.text = DateUtilsHelper.formatDate(picked);
    notifier.selectDate(picked);
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

  Future<void> _save(BuildContext context, WidgetRef ref) async {
    final appointment = widget.appointment;
    final provider = eventDetailsControllerProvider(
      EventDetailsKey(appointment),
    );
    final notifier = ref.read(provider.notifier);

    // Editing a repeating visit asks whether to apply the changes to this
    // visit only or to this and the future visits — mirroring delete. Changing
    // the repeat rule itself always rewrites the series, so it skips the prompt.
    final state = ref.read(provider);
    if (state.isSaving) return; // a save (or its prompt) is already in flight
    var applyToSeries = false;
    if (appointment.seriesId.isNotEmpty && state.repeat == state.savedRepeat) {
      // Busy the form while the prompt is open so a second tap can't stack a
      // duplicate dialog; reset before save() takes over the flag.
      notifier.setSaving(busy: true);
      final choice = await showSeriesScopeDialog(
        context,
        title: context.l10n.calendar_editAppointment,
        message: context.l10n.calendar_editSeriesScopeMessage,
        thisOnlyLabel: context.l10n.calendar_editThisVisitOnly,
        thisAndFutureLabel: context.l10n.calendar_editThisAndFutureVisits,
      );
      // Reset before the mounted guard — the notifier is context-free, and
      // bailing while still busy would wedge a surviving controller.
      notifier.setSaving(busy: false);
      if (!context.mounted || choice == null) return;
      applyToSeries = choice == SeriesScopeChoice.thisAndFuture;
    }

    final outcome = await notifier.save(
      appointment,
      title: widget.controllers.title.text,
      address: AddressParser.toCanonical(widget.controllers.address.text),
      notes: widget.controllers.notes.text,
      materialsNeeded: widget.controllers.materials.text,
      applyToSeries: applyToSeries,
    );
    if (!context.mounted) return;
    switch (outcome) {
      case EventDetailsInvalid():
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
                tag: 'APPT-SAVE',
                error: error,
              ),
            );
    }
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final appointment = widget.appointment;
    final choice = await showDeleteAppointmentDialog(
      context,
      isSeries: appointment.seriesId.isNotEmpty,
    );
    if (choice == null || !context.mounted) return;
    final notifier = ref.read(
      eventDetailsControllerProvider(EventDetailsKey(appointment)).notifier,
    );
    final error = await notifier.deleteAppointment(
      appointment,
      includeFuture: choice == SeriesScopeChoice.thisAndFuture,
    );
    if (!context.mounted) return;
    if (error == null) {
      ref
          .read(noticeServiceProvider)
          .success(context.l10n.common_appointmentDeleted);
      widget.onClose();
    } else {
      ref
          .read(noticeServiceProvider)
          .error(
            composeErrorNotice(
              context,
              intro: context.l10n.error_introDeleteAppointment,
              tag: 'APPT-DEL',
              error: error,
            ),
          );
    }
  }
}

class _ActionButtons extends StatelessWidget {
  const _ActionButtons({
    required this.isSaving,
    required this.onSave,
    required this.onDelete,
  });

  final bool isSaving;
  final VoidCallback onSave;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AnimatedLoadingButton(
          label: context.l10n.common_saveChanges,
          isLoading: isSaving,
          onPressed: onSave,
          height: 48,
        ),
        const SizedBox(height: AppSpacing.sp8),
        OutlinedButton(
          style: destructiveOutlinedButtonStyle(
            context,
            minimumSize: const Size(double.infinity, 48),
          ),
          onPressed: isSaving ? null : onDelete,
          child: Text(context.l10n.calendar_deleteAppointment),
        ),
      ],
    );
  }
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
        if (picked.isNotEmpty) notifier.addImages(picked);
      },
      onRemoveExisting: notifier.removeExistingImage,
      onRemoveNew: notifier.removeNewImage,
    );
  }
}

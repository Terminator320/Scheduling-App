import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scheduling/core/errors/error_cause.dart';
import 'package:scheduling/core/notices/notice_service.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/core/utils/date_utils_helper.dart';
import 'package:scheduling/core/validators/text_limits.dart';
import 'package:scheduling/features/calendar/application/event_details_controller.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/calendar/domain/policies/appointment_form_validator.dart';
import 'package:scheduling/features/calendar/utils/appointment_form_error_text.dart';
import 'package:scheduling/features/calendar/utils/cupertino_time_picker.dart';
import 'package:scheduling/features/calendar/widgets/fields/appointment_status_picker.dart';
import 'package:scheduling/features/calendar/widgets/fields/employee_picker.dart';
import 'package:scheduling/features/calendar/widgets/sections/photo_picker_section.dart';
import 'package:scheduling/features/calendar/widgets/sheets/image_source_picker.dart';
import 'package:scheduling/features/clients/widgets/fields/client_search_field.dart';
import 'package:scheduling/features/employees/application/employees_providers.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';
import 'package:scheduling/features/maps/domain/address_parser.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/dialogs/confirm_dialog.dart';
import 'package:scheduling/shared/widgets/fields/address_autocomplete_field.dart';
import 'package:scheduling/shared/widgets/fields/form_helpers.dart';
import 'package:scheduling/shared/widgets/fields/labeled_text_field.dart';
import 'package:scheduling/shared/widgets/sheets/sheet_widgets.dart';

class DetailsEditControllers {
  const DetailsEditControllers({
    required this.title,
    required this.date,
    required this.startTime,
    required this.endTime,
    required this.clientSearch,
    required this.address,
    required this.notes,
    required this.materials,
  });

  final TextEditingController title;
  final TextEditingController date;
  final TextEditingController startTime;
  final TextEditingController endTime;
  final TextEditingController clientSearch;
  final TextEditingController address;
  final TextEditingController notes;
  final TextEditingController materials;
}

class DetailsEditBody extends ConsumerWidget {
  const DetailsEditBody({
    required this.appointment,
    required this.controllers,
    required this.onSaved,
    required this.onClose,
    super.key,
  });

  final AppointmentRecord appointment;
  final DetailsEditControllers controllers;
  final ValueChanged<AppointmentRecord> onSaved;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final state = ref.watch(eventDetailsControllerProvider(appointment));
    final notifier = ref.read(
      eventDetailsControllerProvider(appointment).notifier,
    );
    final allEmployees =
        ref.watch(employeesStreamProvider).asData?.value ?? const [];

    String? err(String key) => _errorFor(context, state.errors, key);

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
        // --- Title, client & employees ---
        _ClientSection(
          controllers: controllers,
          state: state,
          notifier: notifier,
          allEmployees: allEmployees,
          err: err,
        ),
        const SizedBox(height: AppSpacing.sp16),
        // --- Date, time & status ---
        _ScheduleSection(
          controllers: controllers,
          state: state,
          notifier: notifier,
          err: err,
          onPickDate: () => _pickDate(context, state, notifier),
          onPickStart: () => _pickStartTime(context, state, notifier),
          onPickEnd: () => _pickEndTime(context, state, notifier),
        ),
        const SizedBox(height: AppSpacing.sp16),
        // --- Address ---
        SheetFocusScroll(
          child: AddressAutocompleteField(
            controller: controllers.address,
            optional: true,
          ),
        ),
        const SizedBox(height: AppSpacing.sp16),
        // --- Materials & notes ---
        SheetFocusScroll(
          child: LabeledTextField(
            label: context.l10n.calendar_materialsNeeded,
            hint: context.l10n.calendar_eGPipeWrenchTapeCommaSeparated,
            controller: controllers.materials,
            optional: true,
            maxLines: 2,
            maxLength: TextLimits.appointmentMaterials,
          ),
        ),
        const SizedBox(height: AppSpacing.sp16),
        SheetFocusScroll(
          child: LabeledTextField(
            label: context.l10n.calendar_notes,
            hint: context.l10n.calendar_typeTheNoteHere,
            controller: controllers.notes,
            optional: true,
            maxLines: 2,
            maxLength: TextLimits.appointmentNotes,
            showCounter: true,
          ),
        ),
        const SizedBox(height: AppSpacing.sp16),
        // --- Photos ---
        formLabel(context, context.l10n.calendar_pictures, optional: true),
        _EditPhotosSection(appointment: appointment),
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
    final picked = await showDatePicker(
      context: context,
      initialDate: state.selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    controllers.date.text = DateUtilsHelper.formatDate(picked);
    notifier.selectDate(picked);
  }

  Future<void> _pickStartTime(
    BuildContext context,
    EventDetailsState state,
    EventDetailsController notifier,
  ) async {
    final picked = await showCupertinoTimePicker(
      context,
      initialTime: state.selectedStartTime,
    );
    if (picked == null || !context.mounted) return;
    controllers.startTime.text = picked.format(context);
    notifier.selectStartTime(picked);
  }

  Future<void> _pickEndTime(
    BuildContext context,
    EventDetailsState state,
    EventDetailsController notifier,
  ) async {
    final picked = await showCupertinoTimePicker(
      context,
      initialTime: state.selectedEndTime,
    );
    if (picked == null || !context.mounted) return;
    controllers.endTime.text = picked.format(context);
    notifier.selectEndTime(picked);
  }

  Future<void> _save(BuildContext context, WidgetRef ref) async {
    final notifier = ref.read(
      eventDetailsControllerProvider(appointment).notifier,
    );
    final outcome = await notifier.save(
      appointment,
      title: controllers.title.text,
      address: AddressParser.toCanonical(controllers.address.text),
      notes: controllers.notes.text,
      materialsNeeded: controllers.materials.text,
    );
    if (!context.mounted) return;
    switch (outcome) {
      case EventDetailsInvalid():
        return;
      case EventDetailsSaved(:final appointment):
        ref
            .read(noticeServiceProvider)
            .success(context.l10n.common_appointmentChangesSaved);
        onSaved(appointment);
      case EventDetailsFailed():
        ref
            .read(noticeServiceProvider)
            .error(context.l10n.error_somethingWentWrongSavingChanges);
    }
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showConfirmDialog(
      context,
      title: context.l10n.calendar_deleteAppointment,
      message: context.l10n.calendar_areYouSureYouWantToDeleteThisJob,
      confirmLabel: context.l10n.common_delete,
    );
    if (!confirmed || !context.mounted) return;
    final notifier = ref.read(
      eventDetailsControllerProvider(appointment).notifier,
    );
    final error = await notifier.deleteAppointment(appointment);
    if (!context.mounted) return;
    if (error == null) {
      ref
          .read(noticeServiceProvider)
          .success(context.l10n.common_appointmentDeleted);
      onClose();
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

class _ClientSection extends StatelessWidget {
  const _ClientSection({
    required this.controllers,
    required this.state,
    required this.notifier,
    required this.allEmployees,
    required this.err,
  });

  final DetailsEditControllers controllers;
  final EventDetailsState state;
  final EventDetailsController notifier;
  final List<EmployeeRecord> allEmployees;
  final String? Function(String) err;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SheetFocusScroll(
          child: LabeledTextField(
            label: context.l10n.calendar_serviceTitle,
            hint: context.l10n.calendar_eGPlumbingRepair,
            controller: controllers.title,
            required: true,
            maxLength: TextLimits.appointmentTitle,
            errorText: err('title'),
          ),
        ),
        const SizedBox(height: AppSpacing.sp16),
        formLabel(context, context.l10n.calendar_client, required: true),
        SheetFocusScroll(
          child: ClientSearchField(
            controller: controllers.clientSearch,
            selectedClient: state.selectedClient,
            results: state.clientResults,
            isSearching: state.isSearchingClient,
            onChanged: notifier.searchClients,
            onSelect: (c) {
              controllers.clientSearch.text = c.displayName;
              controllers.address.text = AddressParser.canonicalToDisplay(
                c.address,
              );
              notifier.selectClient(c);
            },
            onClear: () {
              controllers.clientSearch.clear();
              controllers.address.clear();
              notifier.clearClient();
            },
            errorText: err('client'),
          ),
        ),
        const SizedBox(height: AppSpacing.sp16),
        formLabel(context, context.l10n.calendar_assignedEmployee),
        const SizedBox(height: 6),
        EmployeePicker(
          allEmployees: allEmployees,
          selectedEmployees: state.selectedEmployees,
          hasError: state.errors.containsKey('employees'),
          onToggle: notifier.toggleEmployee,
        ),
        if (state.errors.containsKey('employees'))
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Text(
              err('employees') ?? '',
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
            ),
          ),
      ],
    );
  }
}

class _ScheduleSection extends StatelessWidget {
  const _ScheduleSection({
    required this.controllers,
    required this.state,
    required this.notifier,
    required this.err,
    required this.onPickDate,
    required this.onPickStart,
    required this.onPickEnd,
  });

  final DetailsEditControllers controllers;
  final EventDetailsState state;
  final EventDetailsController notifier;
  final String? Function(String) err;
  final VoidCallback onPickDate;
  final VoidCallback onPickStart;
  final VoidCallback onPickEnd;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SheetFocusScroll(
          child: LabeledTextField(
            label: context.l10n.calendar_date,
            hint: context.l10n.calendar_selectDate,
            controller: controllers.date,
            required: true,
            readOnly: true,
            errorText: err('date'),
            suffixIcon: const Icon(Icons.calendar_today_outlined, size: 18),
            onTap: onPickDate,
          ),
        ),
        const SizedBox(height: AppSpacing.sp16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SheetFocusScroll(
                child: LabeledTextField(
                  label: context.l10n.calendar_startTime,
                  hint: context.l10n.calendar_start,
                  controller: controllers.startTime,
                  required: true,
                  readOnly: true,
                  errorText: err('startTime'),
                  onTap: onPickStart,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sp12),
            Expanded(
              child: SheetFocusScroll(
                child: LabeledTextField(
                  label: context.l10n.calendar_endTime,
                  hint: context.l10n.calendar_end,
                  controller: controllers.endTime,
                  required: true,
                  readOnly: true,
                  errorText: err('endTime'),
                  onTap: onPickEnd,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sp16),
        formLabel(context, context.l10n.calendar_appointmentStatus),
        const SizedBox(height: 6),
        AppointmentStatusPicker(
          currentStatus: state.editingStatus,
          onChanged: notifier.setStatus,
        ),
      ],
    );
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
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton(
          style: FilledButton.styleFrom(
            minimumSize: const Size(double.infinity, 48),
          ),
          onPressed: isSaving ? null : onSave,
          child: isSaving
              ? SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: scheme.onPrimary,
                  ),
                )
              : Text(context.l10n.common_saveChanges),
        ),
        const SizedBox(height: AppSpacing.sp8),
        OutlinedButton(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(double.infinity, 48),
            foregroundColor: scheme.error,
            side: BorderSide(color: scheme.error),
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
    final provider = eventDetailsControllerProvider(appointment);
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

String? _errorFor(
  BuildContext context,
  Map<String, AppointmentFormError> errors,
  String field,
) {
  final key = errors[field];
  return key == null ? null : appointmentFormErrorText(context, key);
}

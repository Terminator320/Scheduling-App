import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/images/images_providers.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/core/utils/date_utils_helper.dart';
import 'package:scheduling/core/utils/l10n_extensions.dart';
import 'package:scheduling/features/calendar/application/event_details_controller.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/calendar/domain/policies/appointment_form_validator.dart';
import 'package:scheduling/features/calendar/utils/cupertino_time_picker.dart';
import 'package:scheduling/features/calendar/widgets/appointment_status_picker.dart';
import 'package:scheduling/features/calendar/widgets/employee_picker.dart';
import 'package:scheduling/features/calendar/widgets/photo_picker_section.dart';
import 'package:scheduling/features/clients/widgets/client_search_field.dart';
import 'package:scheduling/features/employees/application/employees_providers.dart';
import 'package:scheduling/shared/widgets/address_autocomplete_field.dart';
import 'package:scheduling/shared/widgets/form_helpers.dart';
import 'package:scheduling/shared/widgets/labeled_text_field.dart';
import 'package:scheduling/shared/widgets/sheet_widgets.dart';

/// Bundle of `TextEditingController`s the shell owns and forwards to the
/// edit body. Keeping these in the shell means the body can be a stateless
/// `ConsumerWidget` while the lifecycle stays tied to the sheet's mount.
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

/// Editable body of `EventDetailsSheet`. Stateless w.r.t. UI primitives —
/// receives the shell's controllers via [controllers] and dispatches every
/// other change through [eventDetailsControllerProvider].
///
/// `onClose` is wired by the shell to `Navigator.pop`. `onSaved` receives
/// the saved record so the shell can pop with it as the result.
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
    final scheme = theme.colorScheme;
    final state = ref.watch(eventDetailsControllerProvider(appointment));
    final notifier =
        ref.read(eventDetailsControllerProvider(appointment).notifier);
    final allEmployees =
        ref.watch(employeesStreamProvider).asData?.value ?? const [];

    String? err(String key) => _errorFor(context, state.errors, key);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(context.l10n.editAppointment, style: theme.textTheme.headlineLarge),
        const SizedBox(height: AppSpacing.sp16),
        const Divider(height: 1),
        const SizedBox(height: AppSpacing.sp16),
        SheetFocusScroll(
          child: LabeledTextField(
            label: context.l10n.serviceTitle,
            hint: context.l10n.eGPlumbingRepair,
            controller: controllers.title,
            required: true,
            errorText: err('title'),
          ),
        ),
        const SizedBox(height: AppSpacing.sp16),
        formLabel(context, context.l10n.client, required: true),
        SheetFocusScroll(
          child: ClientSearchField(
            controller: controllers.clientSearch,
            selectedClient: state.selectedClient,
            results: state.clientResults,
            isSearching: state.isSearchingClient,
            onChanged: notifier.searchClients,
            onSelect: (c) {
              controllers.clientSearch.text = c.displayName;
              controllers.address.text = c.address;
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
        formLabel(context, context.l10n.assignedEmployee),
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
        const SizedBox(height: AppSpacing.sp16),
        SheetFocusScroll(
          child: LabeledTextField(
            label: context.l10n.date,
            hint: context.l10n.selectDate,
            controller: controllers.date,
            required: true,
            readOnly: true,
            errorText: err('date'),
            suffixIcon: const Icon(Icons.calendar_today_outlined, size: 18),
            onTap: () => _pickDate(context, state, notifier),
          ),
        ),
        const SizedBox(height: AppSpacing.sp16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SheetFocusScroll(
                child: LabeledTextField(
                  label: context.l10n.startTime,
                  hint: context.l10n.start,
                  controller: controllers.startTime,
                  required: true,
                  readOnly: true,
                  errorText: err('startTime'),
                  onTap: () => _pickStartTime(context, state, notifier),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sp12),
            Expanded(
              child: SheetFocusScroll(
                child: LabeledTextField(
                  label: context.l10n.endTime,
                  hint: context.l10n.end,
                  controller: controllers.endTime,
                  required: true,
                  readOnly: true,
                  errorText: err('endTime'),
                  onTap: () => _pickEndTime(context, state, notifier),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sp16),
        formLabel(context, context.l10n.appointmentStatus),
        const SizedBox(height: 6),
        AppointmentStatusPicker(
          currentStatus: state.editingStatus,
          onChanged: notifier.setStatus,
        ),
        const SizedBox(height: AppSpacing.sp16),
        SheetFocusScroll(
          child: AddressAutocompleteField(
            controller: controllers.address,
            optional: true,
          ),
        ),
        const SizedBox(height: AppSpacing.sp16),
        SheetFocusScroll(
          child: LabeledTextField(
            label: context.l10n.materialsNeeded,
            hint: context.l10n.eGPipeWrenchTapeCommaSeparated,
            controller: controllers.materials,
            optional: true,
            maxLines: 2,
          ),
        ),
        const SizedBox(height: AppSpacing.sp16),
        SheetFocusScroll(
          child: LabeledTextField(
            label: context.l10n.notes,
            hint: context.l10n.typeTheNoteHere,
            controller: controllers.notes,
            optional: true,
            maxLines: 2,
          ),
        ),
        const SizedBox(height: AppSpacing.sp16),
        formLabel(context, context.l10n.pictures, optional: true),
        PhotoPickerSection(
          existingImages: state.existingImages,
          newImages: state.newImages,
          isEditing: true,
          onPickImages: () async {
            final picker = ref.read(imagePickerProvider);
            final picked = await picker.pickMultiImages();
            if (picked.isNotEmpty) notifier.addImages(picked);
          },
          onRemoveExisting: notifier.removeExistingImage,
          onRemoveNew: notifier.removeNewImage,
        ),
        const SizedBox(height: AppSpacing.sp24),
        FilledButton(
          style: FilledButton.styleFrom(
            minimumSize: const Size(double.infinity, 46),
          ),
          onPressed: state.isSaving ? null : () => _save(context, ref),
          child: state.isSaving
              ? SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: scheme.onPrimary,
                  ),
                )
              : Text(context.l10n.saveChanges),
        ),
        const SizedBox(height: AppSpacing.sp8),
        OutlinedButton(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(double.infinity, 44),
            foregroundColor: scheme.error,
            side: BorderSide(color: scheme.error),
          ),
          onPressed:
              state.isSaving ? null : () => _confirmDelete(context, ref),
          child: Text(context.l10n.deleteAppointment),
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
    final notifier =
        ref.read(eventDetailsControllerProvider(appointment).notifier);
    final outcome = await notifier.save(
      appointment,
      title: controllers.title.text,
      address: controllers.address.text,
      notes: controllers.notes.text,
      materialsNeeded: controllers.materials.text,
    );
    if (!context.mounted) return;
    switch (outcome) {
      case EventDetailsInvalid():
        return;
      case EventDetailsSaved(:final appointment):
        onSaved(appointment);
      case EventDetailsFailed():
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.somethingWentWrongSavingChanges)),
        );
    }
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.deleteAppointment),
        content: Text(context.l10n.areYouSureYouWantToDeleteThisJob),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: Text(context.l10n.delete),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final notifier =
        ref.read(eventDetailsControllerProvider(appointment).notifier);
    final ok = await notifier.deleteAppointment(appointment);
    if (!context.mounted) return;
    if (ok) {
      onClose();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.somethingWentWrong)),
      );
    }
  }
}

String? _errorFor(
  BuildContext context,
  Map<String, AppointmentFormError> errors,
  String field,
) {
  final key = errors[field];
  if (key == null) return null;
  return switch (key) {
    AppointmentFormError.titleRequired => context.l10n.titleIsRequired,
    AppointmentFormError.dateRequired => context.l10n.pleaseSelectADate,
    AppointmentFormError.startTimeRequired =>
      context.l10n.pleaseSelectAStartTime,
    AppointmentFormError.endTimeRequired => context.l10n.pleaseSelectAnEndTime,
    AppointmentFormError.endTimeMustBeAfterStart =>
      context.l10n.mustBeAfterStartTime,
    AppointmentFormError.clientRequired => context.l10n.pleaseSelectAClient,
    AppointmentFormError.employeesRequired =>
      context.l10n.pleaseSelectAtLeastOneEmployee,
  };
}

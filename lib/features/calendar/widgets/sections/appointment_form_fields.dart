import 'package:flutter/material.dart';

import 'package:scheduling/core/layout/breakpoints.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/core/validators/text_limits.dart';
import 'package:scheduling/features/calendar/domain/models/job_template.dart';
import 'package:scheduling/features/calendar/domain/models/repeat_interval.dart';
import 'package:scheduling/features/calendar/domain/policies/appointment_form_validator.dart';
import 'package:scheduling/features/calendar/utils/appointment_form_error_text.dart';
import 'package:scheduling/features/calendar/widgets/fields/appointment_address_field.dart';
import 'package:scheduling/features/calendar/widgets/fields/appointment_status_picker.dart';
import 'package:scheduling/features/calendar/widgets/fields/employee_picker.dart';
import 'package:scheduling/features/calendar/widgets/fields/repeat_interval_picker.dart';
import 'package:scheduling/features/clients/domain/models/client_record.dart';
import 'package:scheduling/features/clients/widgets/fields/client_search_field.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';
import 'package:scheduling/features/maps/domain/address_parser.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/fields/form_helpers.dart';
import 'package:scheduling/shared/widgets/fields/labeled_text_field.dart';
import 'package:scheduling/shared/widgets/sheets/sheet_widgets.dart';

/// The eight text controllers an appointment form drives (shared by add and edit to keep field sets in sync).
class AppointmentFormControllers {
  const AppointmentFormControllers({
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

  /// Disposes every owned controller. Call from the State that created them.
  void dispose() {
    title.dispose();
    date.dispose();
    startTime.dispose();
    endTime.dispose();
    clientSearch.dispose();
    address.dispose();
    notes.dispose();
    materials.dispose();
  }
}

/// Shared appointment form field stack for add and edit flows; the status
/// block renders only when [editingStatus]/[onStatusChanged] are provided.
class AppointmentFormFields extends StatelessWidget {
  const AppointmentFormFields({
    required this.controllers,
    required this.allEmployees,
    required this.selectedClient,
    required this.clientResults,
    required this.isSearchingClient,
    required this.selectedEmployees,
    required this.repeat,
    required this.useCustomAddress,
    required this.errors,
    required this.employeeLabel,
    required this.employeeRequired,
    required this.materialsHint,
    required this.photosSection,
    required this.onSearchClients,
    required this.onSelectClient,
    required this.onClearClient,
    required this.onToggleEmployee,
    required this.onPickDate,
    required this.onPickStartTime,
    required this.onPickEndTime,
    required this.onSelectRepeat,
    required this.onUseCustomAddress,
    super.key,
    this.editingStatus,
    this.onStatusChanged,
    this.onRequestAddClient,
    this.onApplyTemplate,
  });

  final AppointmentFormControllers controllers;
  final List<EmployeeRecord> allEmployees;
  final ClientRecord? selectedClient;
  final List<ClientRecord> clientResults;
  final bool isSearchingClient;
  final List<EmployeeRecord> selectedEmployees;
  final RepeatInterval repeat;
  final bool useCustomAddress;
  final Map<String, AppointmentFormError> errors;
  final String employeeLabel;
  final bool employeeRequired;
  final String materialsHint;
  final Widget photosSection;

  final ValueChanged<String> onSearchClients;
  final ValueChanged<ClientRecord> onSelectClient;
  final VoidCallback onClearClient;
  final ValueChanged<EmployeeRecord> onToggleEmployee;
  final VoidCallback onPickDate;
  final VoidCallback onPickStartTime;
  final VoidCallback onPickEndTime;
  final ValueChanged<RepeatInterval> onSelectRepeat;
  final ValueChanged<bool> onUseCustomAddress;

  /// Edit flow only. When null, the status block is omitted (add flow).
  final String? editingStatus;
  final ValueChanged<String>? onStatusChanged;

  /// Opens the add-client sheet and auto-selects the created client (null hides the affordance).
  final Future<ClientRecord?> Function(String initialName)? onRequestAddClient;

  /// Add flow only; one-tap job-template chips render above the title (null hides chips for edit flow).
  final ValueChanged<JobTemplate>? onApplyTemplate;

  String? _err(BuildContext context, String field) {
    final key = errors[field];
    return key == null ? null : appointmentFormErrorText(context, key);
  }

  void _selectClient(ClientRecord client) {
    controllers.clientSearch.text = client.displayName;
    controllers.address.text = AddressParser.canonicalToDisplay(client.address);
    onSelectClient(client);
  }

  void _clearClient() {
    controllers.clientSearch.clear();
    controllers.address.clear();
    onClearClient();
  }

  Future<void> _addNewClient() async {
    final created = await onRequestAddClient!(
      controllers.clientSearch.text.trim(),
    );
    if (created == null) return;
    _selectClient(created);
  }

  void _switchToCustomAddress() {
    controllers.address.clear();
    onUseCustomAddress(true);
  }

  void _useClientAddress() {
    final client = selectedClient;
    if (client == null) return;
    controllers.address.text = AddressParser.canonicalToDisplay(client.address);
    onUseCustomAddress(false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ..._templatesSection(context, l10n),
        ..._whoSection(context, l10n),
        ..._scheduleSection(context, l10n),
        ..._detailsSection(context, l10n),
      ],
    );
  }

  /// Quick-fill job-template chips — add flow only.
  List<Widget> _templatesSection(BuildContext context, AppLocalizations l10n) {
    if (onApplyTemplate == null) return const [];
    return [
      formLabel(context, l10n.calendar_jobTemplatesLabel, optional: true),
      const SizedBox(height: AppSpacing.sp4),
      Wrap(
        spacing: AppSpacing.sp8,
        runSpacing: AppSpacing.sp8,
        children: [
          for (final template in JobTemplate.values)
            ActionChip(
              label: Text(jobTemplateLabel(l10n, template)),
              onPressed: () => onApplyTemplate!(template),
            ),
        ],
      ),
      const SizedBox(height: AppSpacing.sp16),
    ];
  }

  /// Service title, client picker and employee picker.
  List<Widget> _whoSection(BuildContext context, AppLocalizations l10n) => [
    // --- Service title ---
    SheetFocusScroll(
      child: LabeledTextField(
        label: l10n.calendar_serviceTitle,
        hint: l10n.calendar_eGPlumbingRepair,
        controller: controllers.title,
        required: true,
        textCapitalization: TextCapitalization.sentences,
        textInputAction: TextInputAction.next,
        maxLength: TextLimits.appointmentTitle,
        errorText: _err(context, 'title'),
      ),
    ),
    const SizedBox(height: AppSpacing.sp16),
    // --- Client ---
    formLabel(context, l10n.calendar_client, required: true),
    SheetFocusScroll(
      child: ClientSearchField(
        controller: controllers.clientSearch,
        selectedClient: selectedClient,
        results: clientResults,
        isSearching: isSearchingClient,
        onChanged: onSearchClients,
        onSelect: _selectClient,
        onClear: _clearClient,
        errorText: _err(context, 'client'),
        onAddNew: onRequestAddClient == null ? null : _addNewClient,
      ),
    ),
    const SizedBox(height: AppSpacing.sp16),
    // --- Employees ---
    formLabel(context, employeeLabel, required: employeeRequired),
    const SizedBox(height: AppSpacing.sp4),
    EmployeePicker(
      allEmployees: allEmployees,
      selectedEmployees: selectedEmployees,
      onToggle: onToggleEmployee,
      errorText: _err(context, 'employees'),
    ),
    const SizedBox(height: AppSpacing.sp16),
  ];

  /// Date, start/end time, status (edit flow only) and repeat.
  List<Widget> _scheduleSection(BuildContext context, AppLocalizations l10n) {
    final showStatus = editingStatus != null && onStatusChanged != null;
    final isNarrowPhone = context.isNarrowWidth;

    final startTimeField = SheetFocusScroll(
      child: LabeledTextField(
        label: l10n.calendar_startTime,
        hint: l10n.calendar_start,
        controller: controllers.startTime,
        required: true,
        readOnly: true,
        errorText: _err(context, 'startTime'),
        onTap: onPickStartTime,
      ),
    );
    final endTimeField = SheetFocusScroll(
      child: LabeledTextField(
        label: l10n.calendar_endTime,
        hint: l10n.calendar_end,
        controller: controllers.endTime,
        required: true,
        readOnly: true,
        errorText: _err(context, 'endTime'),
        onTap: onPickEndTime,
      ),
    );

    return [
      // --- Date ---
      SheetFocusScroll(
        child: LabeledTextField(
          label: l10n.calendar_date,
          hint: l10n.calendar_selectDate,
          controller: controllers.date,
          required: true,
          readOnly: true,
          suffixIcon: const Icon(Icons.calendar_today_outlined, size: 18),
          errorText: _err(context, 'date'),
          onTap: onPickDate,
        ),
      ),
      const SizedBox(height: AppSpacing.sp16),
      // --- Start / end time ---
      if (isNarrowPhone)
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            startTimeField,
            const SizedBox(height: AppSpacing.sp16),
            endTimeField,
          ],
        )
      else
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: startTimeField),
            const SizedBox(width: AppSpacing.sp12),
            Expanded(child: endTimeField),
          ],
        ),
      const SizedBox(height: AppSpacing.sp16),
      // --- Status (edit flow only) ---
      if (showStatus) ...[
        formLabel(context, l10n.calendar_appointmentStatus),
        const SizedBox(height: AppSpacing.sp4),
        AppointmentStatusPicker(
          currentStatus: editingStatus!,
          onChanged: onStatusChanged!,
        ),
        const SizedBox(height: AppSpacing.sp16),
      ],
      // --- Repeat ---
      formLabel(context, l10n.calendar_repeat, optional: true),
      RepeatIntervalPicker(current: repeat, onChanged: onSelectRepeat),
      const SizedBox(height: AppSpacing.sp16),
    ];
  }

  /// Address, notes, materials and the host-supplied photos slot.
  List<Widget> _detailsSection(BuildContext context, AppLocalizations l10n) => [
    // --- Address ---
    AppointmentAddressField(
      selectedClient: selectedClient,
      useCustomAddress: useCustomAddress,
      addressController: controllers.address,
      onSwitchToCustom: _switchToCustomAddress,
      onUseClientAddress: _useClientAddress,
    ),
    const SizedBox(height: AppSpacing.sp16),
    // --- Notes ---
    SheetFocusScroll(
      child: LabeledTextField(
        label: l10n.calendar_notes,
        hint: l10n.calendar_typeTheNoteHere,
        controller: controllers.notes,
        optional: true,
        textCapitalization: TextCapitalization.sentences,
        maxLines: 2,
        maxLength: TextLimits.appointmentNotes,
        showCounter: true,
      ),
    ),
    const SizedBox(height: AppSpacing.sp16),
    // --- Materials ---
    SheetFocusScroll(
      child: LabeledTextField(
        label: l10n.calendar_materialsNeeded,
        hint: materialsHint,
        controller: controllers.materials,
        optional: true,
        textCapitalization: TextCapitalization.sentences,
        maxLines: 2,
        maxLength: TextLimits.appointmentMaterials,
      ),
    ),
    const SizedBox(height: AppSpacing.sp16),
    // --- Photos ---
    formLabel(context, l10n.calendar_pictures, optional: true),
    photosSection,
  ];
}

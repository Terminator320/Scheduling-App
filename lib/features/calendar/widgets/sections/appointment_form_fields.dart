import 'package:flutter/material.dart';

import 'package:scheduling/core/layout/breakpoints.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/core/validators/text_limits.dart';
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

/// The eight text controllers an appointment form drives. Owned (and disposed)
/// by the State that builds the form; shared by the add sheet and the edit
/// body so the field set can't drift between them.
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

/// The shared appointment form field stack (title, client, employees, date,
/// time, status, repeat, address, notes, materials, photos), used by
/// both the add-appointment sheet and the edit-details body. It renders the
/// fields and owns the client/address controller-text wiring; the host wires
/// the rest through callbacks and supplies its own header, photos slot, and
/// action buttons (which differ between add and edit).
///
/// The status block renders only when [editingStatus]/[onStatusChanged] are
/// provided (edit flow); the add flow omits it.
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // --- Service title ---
        SheetFocusScroll(
          child: LabeledTextField(
            label: l10n.calendar_serviceTitle,
            hint: l10n.calendar_eGPlumbingRepair,
            controller: controllers.title,
            required: true,
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
            maxLines: 2,
            maxLength: TextLimits.appointmentMaterials,
          ),
        ),
        const SizedBox(height: AppSpacing.sp16),
        // --- Photos ---
        formLabel(context, l10n.calendar_pictures, optional: true),
        photosSection,
      ],
    );
  }
}

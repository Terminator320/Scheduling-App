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
import 'package:scheduling/shared/widgets/cards/sheet_panel.dart';
import 'package:scheduling/shared/widgets/fields/form_helpers.dart';
import 'package:scheduling/shared/widgets/fields/labeled_text_field.dart';
import 'package:scheduling/shared/widgets/fields/sheet_field_row.dart';
import 'package:scheduling/shared/widgets/sheets/sheet_widgets.dart';

/// The eight text controllers an appointment form drives. Shared between the add and edit flows so their field sets stay in sync.
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

/// Shared appointment form field stack for the add and edit flows. The status
/// block only renders when both [editingStatus] and [onStatusChanged] are provided.
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
    required this.isPersonal,
    required this.isAllDay,
    required this.onAllDayChanged,
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
    this.onPersonalChanged,
  });

  final AppointmentFormControllers controllers;
  final List<EmployeeRecord> allEmployees;
  final ClientRecord? selectedClient;
  final List<ClientRecord> clientResults;
  final bool isSearchingClient;
  final List<EmployeeRecord> selectedEmployees;
  final RepeatInterval repeat;
  final bool useCustomAddress;

  /// Personal job: time blocked off for the crew rather than a client visit.
  /// Hides the client picker, address, materials, photos, repeat and the
  /// template chips, and drops the client and title from validation.
  final bool isPersonal;

  /// No time was put in, so the block owns the whole day: the start/end rows
  /// are hidden and the record saves midnight → 23:59. Only offered on a
  /// personal job, and on by default there.
  final bool isAllDay;
  final ValueChanged<bool> onAllDayChanged;

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

  /// Opens the add-client sheet and auto-selects the created client. Pass null to hide the affordance entirely.
  final Future<ClientRecord?> Function(String initialName)? onRequestAddClient;

  /// Add flow only — renders one-tap job-template chips above the title. Null hides the chips, which is how the edit flow uses this.
  final ValueChanged<JobTemplate>? onApplyTemplate;

  /// Renders the personal-job switch. Null hides it: the edit flow only offers
  /// it on a job that is ALREADY personal, so an ordinary client visit can't be
  /// turned into one halfway through its life.
  final ValueChanged<bool>? onPersonalChanged;

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

  void _setPersonal(bool value) {
    // Clear the text fields the switch hides, so nothing stale is left in a
    // controller the user can no longer see. Photos are deliberately NOT
    // cleared here — dropping already-uploaded images off a flick of a switch
    // is destructive and can't be undone from this form.
    if (value) {
      controllers.clientSearch.clear();
      controllers.address.clear();
      controllers.materials.clear();
    }
    onPersonalChanged!(value);
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

  /// Quick-fill job-template chips — add flow only, and never on a personal
  /// job: every template names a plumbing service.
  List<Widget> _templatesSection(BuildContext context, AppLocalizations l10n) {
    if (onApplyTemplate == null || isPersonal) return const [];
    return [
      _SectionLabel(l10n.calendar_sectionTemplates),
      const SizedBox(height: AppSpacing.sp8),
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

  /// Service title, the personal-job switch, client picker and employee picker.
  List<Widget> _whoSection(BuildContext context, AppLocalizations l10n) => [
    _SectionLabel(l10n.calendar_sectionWho),
    const SizedBox(height: AppSpacing.sp8),
    // --- Personal job ---
    if (onPersonalChanged != null) ...[
      _PersonalJobSwitch(value: isPersonal, onChanged: _setPersonal),
      const SizedBox(height: AppSpacing.sp16),
    ],
    // --- Service title ---
    SheetFocusScroll(
      child: LabeledTextField(
        label: l10n.calendar_serviceTitle,
        // A personal block doesn't have to be named — left blank it saves as
        // "Personal", which is what the card and the off-screen mirrors read.
        hint: isPersonal ? l10n.calendar_personal : l10n.calendar_eGPlumbingRepair,
        controller: controllers.title,
        required: !isPersonal,
        optional: isPersonal,
        textCapitalization: TextCapitalization.sentences,
        textInputAction: TextInputAction.next,
        maxLength: TextLimits.appointmentTitle,
        errorText: _err(context, 'title'),
      ),
    ),
    const SizedBox(height: AppSpacing.sp16),
    // --- Client (a personal job has none) ---
    if (!isPersonal) ...[
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
    ],
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

    // Dates and times are pickers, not text entry, so they render as panel rows
    // rather than readOnly TextFields. Free-text fields keep LabeledTextField,
    // which owns the error shake and the clear button.
    final startRow = SheetFieldRow(
      label: l10n.calendar_startTime,
      value: controllers.startTime.text,
      placeholder: l10n.calendar_start,
      accent: true,
      useMonoValue: true,
      errorText: _err(context, 'startTime'),
      onTap: onPickStartTime,
    );
    final endRow = SheetFieldRow(
      label: l10n.calendar_endTime,
      value: controllers.endTime.text,
      placeholder: l10n.calendar_end,
      accent: true,
      useMonoValue: true,
      errorText: _err(context, 'endTime'),
      onTap: onPickEndTime,
    );

    return [
      _SectionLabel(l10n.calendar_sectionSchedule),
      const SizedBox(height: AppSpacing.sp8),
      SheetPanel(
        children: [
          // --- All day (personal jobs only) — first row of the panel, since
          // it decides whether the time rows below it exist at all.
          if (isPersonal)
            _AllDaySwitch(value: isAllDay, onChanged: onAllDayChanged),
          SheetFieldRow(
            label: l10n.calendar_date,
            value: controllers.date.text,
            placeholder: l10n.calendar_selectDate,
            accent: true,
            useMonoValue: true,
            errorText: _err(context, 'date'),
            onTap: onPickDate,
            trailing: const Icon(Icons.calendar_today_outlined, size: 18),
          ),
          // An all-day block has no times to show — the date row is the whole
          // schedule, and an empty child here would leave a stray divider.
          // Start and end otherwise share one row until the screen is too
          // narrow to read both.
          if (isAllDay)
            ...const <Widget>[]
          else if (isNarrowPhone) ...[
            startRow,
            endRow,
          ] else
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: startRow),
                  const VerticalDivider(width: 1),
                  Expanded(child: endRow),
                ],
              ),
            ),
          // --- Repeat: same panel as the date and times, so everything about
          // when the job happens reads as one block. Not offered on a personal
          // job.
          if (!isPersonal)
            RepeatIntervalPicker(current: repeat, onChanged: onSelectRepeat),
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
    ];
  }

  /// Address, notes, materials and the host-supplied photos slot.
  List<Widget> _detailsSection(BuildContext context, AppLocalizations l10n) => [
    _SectionLabel(l10n.calendar_sectionDetails),
    const SizedBox(height: AppSpacing.sp8),
    // --- Address (a personal job has none) ---
    if (!isPersonal) ...[
      AppointmentAddressField(
        selectedClient: selectedClient,
        useCustomAddress: useCustomAddress,
        addressController: controllers.address,
        onSwitchToCustom: _switchToCustomAddress,
        onUseClientAddress: _useClientAddress,
      ),
      const SizedBox(height: AppSpacing.sp16),
    ],
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
    // --- Materials and photos (job-site fields; a personal block has none) ---
    if (!isPersonal) ...[
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
      formLabel(context, l10n.calendar_pictures, optional: true),
      photosSection,
    ],
  ];
}

/// Marks the job as personal time rather than a client visit. Mirrors the
/// client form's "no fixed address" switch, which gates a field the same way.
class _PersonalJobSwitch extends StatelessWidget {
  const _PersonalJobSwitch({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Material(
    type: MaterialType.transparency,
    child: SwitchListTile.adaptive(
      contentPadding: EdgeInsets.zero,
      title: Text(context.l10n.calendar_personalJob),
      subtitle: Text(context.l10n.calendar_personalJobHint),
      value: value,
      activeTrackColor: Theme.of(context).colorScheme.primary,
      onChanged: onChanged,
    ),
  );
}

/// Turns the block into a whole-day one. Personal jobs only — a client visit
/// always has a time. Lives inside the schedule `SheetPanel`, so it carries the
/// same 15/13 padding its sibling rows do rather than a ListTile's own.
class _AllDaySwitch extends StatelessWidget {
  const _AllDaySwitch({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: () => onChanged(!value),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(15, 9, 13, 9),
          child: Row(
            children: [
              // No explanatory subtitle — "All day" says it.
              Expanded(
                child: Text(
                  context.l10n.calendar_allDay,
                  style: theme.textTheme.titleSmall,
                ),
              ),
              const SizedBox(width: AppSpacing.sp8),
              Switch.adaptive(
                value: value,
                activeTrackColor: theme.colorScheme.primary,
                onChanged: onChanged,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Mono all-caps section header inside the form sheet. The ARB values are
/// already uppercase, matching the rest of the redesign's mono labels.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: Theme.of(context).monoType.label);
}

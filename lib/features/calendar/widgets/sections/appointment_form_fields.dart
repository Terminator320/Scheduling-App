import 'package:flutter/material.dart';

import 'package:scheduling/core/layout/breakpoints.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/core/validators/text_limits.dart';
import 'package:scheduling/features/calendar/domain/models/job_template.dart';
import 'package:scheduling/features/calendar/domain/models/repeat_interval.dart';
import 'package:scheduling/features/calendar/domain/policies/appointment_form_validator.dart';
import 'package:scheduling/features/calendar/utils/appointment_draft_defaults.dart';
import 'package:scheduling/features/calendar/utils/appointment_form_error_text.dart';
import 'package:scheduling/features/calendar/widgets/fields/appointment_address_field.dart';
import 'package:scheduling/features/calendar/widgets/fields/appointment_date_rows.dart';
import 'package:scheduling/features/calendar/widgets/fields/appointment_status_picker.dart';
import 'package:scheduling/features/calendar/widgets/fields/employee_picker.dart';
import 'package:scheduling/features/calendar/widgets/fields/repeat_interval_picker.dart';
import 'package:scheduling/features/clients/domain/models/client_record.dart';
import 'package:scheduling/features/clients/widgets/fields/client_search_field.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';
import 'package:scheduling/features/feature_tour/domain/tour_step_id.dart';
import 'package:scheduling/features/maps/domain/address_parser.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/cards/sheet_panel.dart';
import 'package:scheduling/shared/widgets/fields/form_helpers.dart';
import 'package:scheduling/shared/widgets/fields/labeled_text_field.dart';
import 'package:scheduling/shared/widgets/fields/sheet_field_row.dart';
import 'package:scheduling/shared/widgets/primitives/mono_section_label.dart';
import 'package:scheduling/shared/widgets/sheets/sheet_widgets.dart';

/// The nine text controllers an appointment form drives. Shared between the add and edit flows so their field sets stay in sync.
class AppointmentFormControllers {
  const AppointmentFormControllers({
    required this.title,
    required this.date,
    required this.endDate,
    required this.startTime,
    required this.endTime,
    required this.clientSearch,
    required this.address,
    required this.notes,
    required this.materials,
  });

  final TextEditingController title;
  final TextEditingController date;
  final TextEditingController endDate;
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
    endDate.dispose();
    startTime.dispose();
    endTime.dispose();
    clientSearch.dispose();
    address.dispose();
    notes.dispose();
    materials.dispose();
  }
}

/// The ten pickers an appointment form drives, grouped the same way
/// [AppointmentFormControllers] groups its nine controllers.
///
/// Every one of these is REQUIRED and always supplied by both call sites, so
/// this buys readability rather than safety — a missing one was already a
/// compile error. What it removes is ten near-identical lines from a
/// 35-parameter constructor, and the temptation to answer "which of these does
/// the edit flow not pass?" by reading all thirty-five.
///
/// The OPTIONAL callbacks deliberately stay on the widget: `onApplyTemplate`,
/// `onPersonalChanged`, `onStatusChanged` and `onRequestAddClient` are each
/// null on one flow and not the other, and that nullability is the thing a
/// reader needs to see at the call site.
class AppointmentFormCallbacks {
  const AppointmentFormCallbacks({
    required this.onSearchClients,
    required this.onSelectClient,
    required this.onClearClient,
    required this.onToggleEmployee,
    required this.onSelectStartDate,
    required this.onSelectEndDate,
    required this.onPickStartTime,
    required this.onPickEndTime,
    required this.onSelectRepeat,
    required this.onUseCustomAddress,
  });

  final ValueChanged<String> onSearchClients;
  final ValueChanged<ClientRecord> onSelectClient;
  final VoidCallback onClearClient;
  final ValueChanged<EmployeeRecord> onToggleEmployee;

  /// The dates arrive already picked: the rows drop an inline month calendar
  /// down beneath themselves rather than opening a modal picker, so there is
  /// no "cancelled" outcome for a host to handle.
  final ValueChanged<DateTime> onSelectStartDate;
  final ValueChanged<DateTime> onSelectEndDate;

  final VoidCallback onPickStartTime;
  final VoidCallback onPickEndTime;
  final ValueChanged<RepeatInterval> onSelectRepeat;
  final ValueChanged<bool> onUseCustomAddress;
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
    required this.selectedDate,
    required this.endDate,
    required this.isPersonal,
    required this.isAllDay,
    required this.onAllDayChanged,
    required this.errors,
    required this.employeeLabel,
    required this.employeeRequired,
    required this.materialsHint,
    required this.photosSection,
    required this.callbacks,
    super.key,
    this.isMultiDay = false,
    this.isOvernight = false,
    this.spanLength = 1,
    this.editingStatus,
    this.onStatusChanged,
    this.onRequestAddClient,
    this.onApplyTemplate,
    this.onPersonalChanged,
    this.tourWrap,
  });

  final AppointmentFormControllers controllers;
  final List<EmployeeRecord> allEmployees;
  final ClientRecord? selectedClient;
  final List<ClientRecord> clientResults;
  final bool isSearchingClient;
  final List<EmployeeRecord> selectedEmployees;
  final RepeatInterval repeat;
  final bool useCustomAddress;

  /// The dates behind the two date rows' text. The rows render the
  /// controllers' formatted strings; these drive the inline month calendar's
  /// selection and the month it opens on. Null while a field is still empty.
  final DateTime? selectedDate;
  final DateTime? endDate;

  /// Personal job: time blocked off for the crew rather than a client visit.
  /// Hides the client picker, materials, photos, repeat and the template
  /// chips, and drops the client and title from validation. The address stays,
  /// marked optional — a personal block can still have somewhere to be.
  final bool isPersonal;

  /// No time was put in, so the block owns the whole day: the start/end rows
  /// are hidden and the record saves midnight → 23:59.
  final bool isAllDay;
  final ValueChanged<bool> onAllDayChanged;

  /// True when this job runs more than one day — drives the daily-window
  /// qualifier on the time labels and the run length beside the end date.
  final bool isMultiDay;

  /// True when the daily window crosses midnight, so the run counts nights.
  final bool isOvernight;

  /// Run length in days (or nights). 1 for a single-day job.
  final int spanLength;

  final Map<String, AppointmentFormError> errors;
  final String employeeLabel;
  final bool employeeRequired;
  final String materialsHint;
  final Widget photosSection;

  /// Wraps a section as its feature-tour step. Injected by the ADD sheet
  /// only — the edit flow has no walkthrough, and passes null, which leaves
  /// every section untouched.
  final Widget Function(TourStepId id, Widget child)? tourWrap;

  /// The ten always-present pickers. See [AppointmentFormCallbacks].
  final AppointmentFormCallbacks callbacks;

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
    callbacks.onSelectClient(client);
  }

  void _clearClient() {
    controllers.clientSearch.clear();
    controllers.address.clear();
    callbacks.onClearClient();
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
    // controller the user can no longer see. Photos are not cleared: dropping
    // already-uploaded images off a flick of a switch is destructive and can't
    // be undone from this form.
    //
    // The ADDRESS stays, because a personal block may well have somewhere to
    // be — EXCEPT when it is the client's own address. `_selectClient` writes
    // that into the controller, and until then it renders as a read-only pill,
    // so the admin never typed it and it belongs to a client this block is no
    // longer for. Both halves of the test matter: with no client selected the
    // field is the editable one, so whatever it holds was typed by hand and
    // must survive — including an address entered before the switch was
    // flipped.
    if (value) {
      controllers.clientSearch.clear();
      controllers.materials.clear();
      if (selectedClient != null && !useCustomAddress) {
        controllers.address.clear();
      }
    }
    onPersonalChanged!(value);
  }

  void _switchToCustomAddress() {
    controllers.address.clear();
    callbacks.onUseCustomAddress(true);
  }

  void _useClientAddress() {
    final client = selectedClient;
    if (client == null) return;
    controllers.address.text = AddressParser.canonicalToDisplay(client.address);
    callbacks.onUseCustomAddress(false);
  }

  /// Wraps [child] as [id]'s tour step, or leaves it alone when the host
  /// injected no tour.
  Widget _tour(TourStepId id, Widget child) =>
      tourWrap?.call(id, child) ?? child;

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
      MonoSectionLabel(l10n.calendar_sectionTemplates),
      const SizedBox(height: AppSpacing.sp8),
      _tour(
        TourStepId.apptTemplates,
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
      ),
      const SizedBox(height: AppSpacing.sp16),
    ];
  }

  /// Service title, the personal-job switch, client picker and employee picker.
  List<Widget> _whoSection(BuildContext context, AppLocalizations l10n) => [
    MonoSectionLabel(l10n.calendar_sectionWho),
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
        hint: isPersonal
            ? l10n.calendar_personal
            : l10n.calendar_eGPlumbingRepair,
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
      _tour(
        TourStepId.apptClient,
        SheetFocusScroll(
          child: ClientSearchField(
            controller: controllers.clientSearch,
            selectedClient: selectedClient,
            results: clientResults,
            isSearching: isSearchingClient,
            onChanged: callbacks.onSearchClients,
            onSelect: _selectClient,
            onClear: _clearClient,
            errorText: _err(context, 'client'),
            onAddNew: onRequestAddClient == null ? null : _addNewClient,
          ),
        ),
      ),
      const SizedBox(height: AppSpacing.sp16),
    ],
    // --- Employees ---
    formLabel(context, employeeLabel, required: employeeRequired),
    const SizedBox(height: AppSpacing.sp4),
    _tour(
      TourStepId.apptCrew,
      EmployeePicker(
        allEmployees: allEmployees,
        selectedEmployees: selectedEmployees,
        onToggle: callbacks.onToggleEmployee,
        errorText: _err(context, 'employees'),
      ),
    ),
    const SizedBox(height: AppSpacing.sp16),
  ];

  /// Start/end date, start/end time, status (edit flow only) and repeat.
  List<Widget> _scheduleSection(BuildContext context, AppLocalizations l10n) {
    final showStatus = editingStatus != null && onStatusChanged != null;
    final isNarrowPhone = context.isNarrowWidth;

    // Dates and times are pickers, not text entry, so they render as panel rows
    // rather than readOnly TextFields. Free-text fields keep LabeledTextField,
    // which owns the error shake and the clear button.
    //
    // Built on demand: an all-day block has no times, and the rows are not
    // constructed for one.
    List<Widget> timeRows() {
      final startRow = SheetFieldRow(
        // Once the job runs past one day the two times describe a window
        // repeated on every day of the run, not a single span.
        label: !isMultiDay
            ? l10n.calendar_startTime
            : (isOvernight
                  ? l10n.calendar_startTimeEachNight
                  : l10n.calendar_startTimeEachDay),
        value: controllers.startTime.text,
        placeholder: l10n.calendar_start,
        accent: true,
        useMonoValue: true,
        errorText: _err(context, 'startTime'),
        onTap: callbacks.onPickStartTime,
      );
      final endRow = SheetFieldRow(
        label: !isMultiDay
            ? l10n.calendar_endTime
            : (isOvernight
                  ? l10n.calendar_endTimeNextMorning
                  : l10n.calendar_endTimeEachDay),
        value: controllers.endTime.text,
        placeholder: l10n.calendar_end,
        accent: true,
        useMonoValue: true,
        errorText: _err(context, 'endTime'),
        onTap: callbacks.onPickEndTime,
      );
      // Start and end share one row until the screen is too narrow to read both.
      if (isNarrowPhone) return [startRow, endRow];
      return [
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
      ];
    }

    return [
      MonoSectionLabel(l10n.calendar_sectionSchedule),
      const SizedBox(height: AppSpacing.sp8),
      _tour(
        TourStepId.apptSchedule,
        SheetPanel(
          children: [
            // --- All day — first row of the panel, since it decides whether
            // the time rows below it exist at all. Offered on every job: a
            // client visit can genuinely run whole days too.
            _AllDaySwitch(value: isAllDay, onChanged: onAllDayChanged),
            _dateRows(context, l10n),
            // An all-day block has no times to show — the date rows are the
            // whole schedule.
            if (!isAllDay) ...timeRows(),
            // --- Repeat: same panel as the date and times, so everything
            // about when the job happens reads as one block. Not offered on a
            // personal job.
            if (!isPersonal)
              RepeatIntervalPicker(
                current: repeat,
                onChanged: callbacks.onSelectRepeat,
              ),
          ],
        ),
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

  /// Start and end date, as ONE panel row that drops the month down beneath
  /// itself. It is a single child of the panel rather than two, because the
  /// dropdown belongs to the pair — see [AppointmentDateRows], which owns the
  /// open/closed state and the divider between the two rows.
  Widget _dateRows(BuildContext context, AppLocalizations l10n) =>
      AppointmentDateRows(
        startValue: controllers.date.text,
        endValue: controllers.endDate.text,
        startDate: selectedDate,
        endDate: endDate,
        firstDate: AppointmentDraftDefaults.datePickerFirstDate,
        lastDate: AppointmentDraftDefaults.datePickerLastDate,
        startError: _err(context, 'date'),
        endError: _err(context, 'endDate'),
        endTrailingLabel: !isMultiDay
            ? null
            : (isOvernight
                  ? l10n.calendar_spanNights(spanLength)
                  : l10n.calendar_spanDays(spanLength)),
        onStartDateSelected: callbacks.onSelectStartDate,
        onEndDateSelected: callbacks.onSelectEndDate,
      );

  /// Address, notes, materials and the host-supplied photos slot.
  ///
  /// The body is one Column rather than spread widgets so the tour has a
  /// single target for the whole section — the step describes all four
  /// fields, and highlighting only the first would misdescribe it. The
  /// Column is stretch-aligned like its parent, so the layout is unchanged.
  List<Widget> _detailsSection(BuildContext context, AppLocalizations l10n) => [
    MonoSectionLabel(l10n.calendar_sectionDetails),
    const SizedBox(height: AppSpacing.sp8),
    _tour(
      TourStepId.apptDetails,
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: _detailsBody(context, l10n),
      ),
    ),
  ];

  List<Widget> _detailsBody(BuildContext context, AppLocalizations l10n) => [
    // --- Address. Offered on a personal job too, where it is OPTIONAL: a
    // dentist appointment or a supply run still happens somewhere, and the
    // crew wants directions to it. Marked optional there so the blank state
    // reads as deliberate rather than unfinished.
    AppointmentAddressField(
      selectedClient: selectedClient,
      useCustomAddress: useCustomAddress,
      addressController: controllers.address,
      optional: isPersonal,
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
      // No subtitle: the WHO section already carries enough on one screen
      // (owner call, 2026-08-05). Turning the switch on visibly removes the
      // client picker and relaxes the address to optional, which explains
      // itself better than a line of hint text.
      title: Text(context.l10n.calendar_personalJob),
      value: value,
      activeTrackColor: Theme.of(context).colorScheme.primary,
      onChanged: onChanged,
    ),
  );
}

/// Turns the block into a whole-day one. Offered on every job — a client visit
/// can run whole days too. Lives inside the schedule `SheetPanel`, so it takes
/// the panel's horizontal inset; the vertical is tighter than a `SheetFieldRow`'s
/// because a switch is taller than a label-over-value pair and the row would
/// otherwise tower over the date row beneath it.
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

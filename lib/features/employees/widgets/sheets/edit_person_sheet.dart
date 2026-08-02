import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/adaptive/adaptive_action_sheet.dart';
import 'package:scheduling/core/connectivity/connectivity_providers.dart';
import 'package:scheduling/core/errors/error_cause.dart';
import 'package:scheduling/core/notices/notice_service.dart';
import 'package:scheduling/core/theme/button_styles.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/core/validators/text_limits.dart';
import 'package:scheduling/features/employees/application/employee_form_controller.dart';
import 'package:scheduling/features/employees/application/employee_schedule_providers.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';
import 'package:scheduling/features/employees/domain/models/job_title.dart';
import 'package:scheduling/features/employees/domain/policies/crew_color_policy.dart';
import 'package:scheduling/features/employees/domain/policies/employee_form_validator.dart';
import 'package:scheduling/features/employees/domain/policies/employee_name_policy.dart';
import 'package:scheduling/features/employees/domain/policies/work_schedule_policy.dart';
import 'package:scheduling/features/employees/widgets/fields/employee_color_grid.dart';
import 'package:scheduling/features/employees/widgets/fields/job_title_chips.dart';
import 'package:scheduling/features/employees/widgets/fields/working_days_picker.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/cards/sheet_panel.dart';
import 'package:scheduling/shared/widgets/dialogs/confirm_dialog.dart';
import 'package:scheduling/shared/widgets/fields/labeled_text_field.dart';
import 'package:scheduling/shared/widgets/fields/sheet_field_row.dart';
import 'package:scheduling/shared/widgets/primitives/mono_section_label.dart';
import 'package:scheduling/shared/widgets/sheets/app_bottom_sheet.dart';
import 'package:scheduling/shared/widgets/sheets/form_sheet_frame.dart';
import 'package:scheduling/shared/widgets/sheets/sheet_widgets.dart';

/// The daily cap options: no cap, then 1–12, which covers any real crew day.
const _kMaxJobsOptions = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12];

/// Opens the edit-person sheet. Resolves to the saved record, or null when the
/// sheet was cancelled.
///
/// A nullable record is enough because a person is never removed here (owner
/// decision 2026-08-02) — there is no third "they are gone" state.
Future<EmployeeRecord?> showEditPersonSheet(
  BuildContext context,
  EmployeeRecord employee, {
  required Set<int> usedColors,
}) => showAppBottomSheet<EmployeeRecord>(
  context,
  builder: (_) => EditPersonSheet(employee: employee, usedColors: usedColors),
);

class EditPersonSheet extends ConsumerStatefulWidget {
  const EditPersonSheet({
    required this.employee,
    super.key,
    this.usedColors = const {},
  });

  final EmployeeRecord employee;
  final Set<int> usedColors;

  @override
  ConsumerState<EditPersonSheet> createState() => _EditPersonSheetState();
}

class _EditPersonSheetState extends ConsumerState<EditPersonSheet> {
  late final TextEditingController _firstNameController;
  late final TextEditingController _lastNameController;
  late final TextEditingController _emailController;
  late final TextEditingController _phoneController;
  late final TextEditingController _emergencyController;

  late JobTitle _jobTitle;
  late List<bool> _workingDays;
  late int _workStartMinutes;
  late int _workEndMinutes;
  // Picked from an action sheet, not typed. 0 means no cap.
  late int _maxJobsPerDay;
  late int _selectedColor;
  late bool _onCall;
  late bool _isAdmin;
  late bool _isDisabled;
  final Map<String, String?> errors = {};

  @override
  void initState() {
    super.initState();
    final e = widget.employee;
    // A legacy doc has the whole name in `name` and nothing in first/last.
    // Seeding First with it keeps the stored name visible and editable, and
    // composeEmployeeName then preserves it on save.
    final hasSplitName =
        e.firstName.trim().isNotEmpty || e.lastName.trim().isNotEmpty;
    _firstNameController = TextEditingController(
      text: hasSplitName ? e.firstName : e.name,
    );
    _lastNameController = TextEditingController(text: e.lastName);
    _emailController = TextEditingController(text: e.email);
    _phoneController = TextEditingController(text: e.phone);
    _emergencyController = TextEditingController(text: e.emergencyContact);

    _jobTitle = e.jobTitle;
    _workingDays = normalizeWorkingDays(e.workingDays);
    _workStartMinutes = e.workStartMinutes;
    _workEndMinutes = e.workEndMinutes;
    _maxJobsPerDay = e.maxJobsPerDay;
    _selectedColor = e.color.toARGB32();
    _onCall = e.onCall;
    _isAdmin = e.isAdmin;
    _isDisabled = e.isDisabled;
  }

  @override
  void dispose() {
    for (final controller in [
      _firstNameController,
      _lastNameController,
      _emailController,
      _phoneController,
      _emergencyController,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _clearError(String key) {
    if (errors[key] == null) return;
    setState(() => errors[key] = null);
  }

  bool _validate(String composedName) {
    final next = EmployeeFormValidator.validate(
      l10n: context.l10n,
      name: composedName.trim(),
      email: _emailController.text.trim(),
      workStartMinutes: _workStartMinutes,
      workEndMinutes: _workEndMinutes,
    );
    setState(() {
      errors
        ..clear()
        ..addAll(next);
    });
    return next.values.every((e) => e == null);
  }

  Future<void> _pickTime({required bool isStart}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: minutesToTimeOfDay(
        isStart ? _workStartMinutes : _workEndMinutes,
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isStart) {
        _workStartMinutes = timeOfDayToMinutes(picked);
      } else {
        _workEndMinutes = timeOfDayToMinutes(picked);
      }
      errors['hours'] = null;
    });
  }

  Future<void> _pickMaxJobs() async {
    final l10n = context.l10n;
    final picked = await showAdaptiveActionSheet<int>(
      context,
      title: l10n.employees_maxJobsPerDay,
      actions: [
        for (final option in _kMaxJobsOptions)
          AdaptiveSheetAction(
            label: option == 0 ? l10n.employees_noCap : '$option',
            value: option,
          ),
      ],
    );
    if (picked == null || !mounted) return;
    setState(() => _maxJobsPerDay = picked);
  }

  Future<void> _save() async {
    final composedName = composeEmployeeName(
      firstName: _firstNameController.text,
      lastName: _lastNameController.text,
      fallback: widget.employee.name,
    );
    if (!_validate(composedName)) return;

    // Fail fast offline, or Save spins until we reconnect.
    if (ref.read(isOfflineProvider)) {
      ref
          .read(noticeServiceProvider)
          .error(
            composeErrorNotice(
              context,
              intro: context.l10n.error_introSaveEmployee,
              tag: 'EMP-SAVE',
              error: const SocketException('offline'),
            ),
          );
      return;
    }

    final updated = widget.employee.copyWith(
      name: composedName,
      firstName: _firstNameController.text.trim(),
      lastName: _lastNameController.text.trim(),
      email: _emailController.text.trim().toLowerCase(),
      phone: _phoneController.text.trim(),
      color: Color(_selectedColor),
      role: _isAdmin ? 'admin' : 'employee',
      jobTitle: _jobTitle,
      workingDays: _workingDays,
      workStartMinutes: _workStartMinutes,
      workEndMinutes: _workEndMinutes,
      maxJobsPerDay: _maxJobsPerDay,
      onCall: _onCall,
      emergencyContact: _emergencyController.text.trim(),
    );

    final outcome = await ref
        .read(employeeFormControllerProvider.notifier)
        .updateEmployee(updated);
    if (!mounted) return;

    switch (outcome) {
      case EmployeeUpdated():
        ref
            .read(noticeServiceProvider)
            .success(context.l10n.common_changesSaved);
        Navigator.pop(context, updated);
      case EmployeeEmailInUse(:final failure):
        setState(() => errors['email'] = failure.toLocalizedMessage(context));
      case EmployeeSaveFailed(:final error):
        ref
            .read(noticeServiceProvider)
            .error(
              composeErrorNotice(
                context,
                intro: context.l10n.error_introSaveEmployee,
                tag: 'EMP-SAVE',
                error: error,
              ),
            );
      case EmployeeInvited():
        // Unreachable from the edit path; the sealed family forces the branch.
        break;
    }
  }

  Future<void> _confirmToggleStatus() async {
    final l10n = context.l10n;
    final actionLabel = _isDisabled
        ? l10n.employees_enableEmployee
        : l10n.employees_disableEmployee;
    final confirmed = await showConfirmDialog(
      context,
      title: actionLabel,
      message: _isDisabled
          ? l10n.employees_enableEmployeeConfirmBody
          : l10n.employees_disableEmployeeConfirmBody,
      confirmLabel: actionLabel,
      destructive: !_isDisabled,
    );
    if (!mounted || !confirmed) return;

    final outcome = await ref
        .read(employeeFormControllerProvider.notifier)
        .setEmployeeStatus(docId: widget.employee.id, disable: !_isDisabled);
    if (!mounted) return;

    switch (outcome) {
      case EmployeeStatusChanged():
        setState(() => _isDisabled = !_isDisabled);
        ref
            .read(noticeServiceProvider)
            .success(
              _isDisabled
                  ? l10n.employees_employeeDisabledSuccessfully
                  : l10n.employees_employeeEnabledSuccessfully,
            );
      case EmployeeStatusChangeFailed(:final error):
        ref
            .read(noticeServiceProvider)
            .error(
              composeErrorNotice(
                context,
                intro: l10n.error_introChangeEmployeeStatus,
                tag: 'EMP-STATUS',
                error: error,
              ),
            );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final materialL10n = MaterialLocalizations.of(context);
    final activity = ref.watch(employeeFormControllerProvider);

    return FormSheetFrame(
      title: l10n.employees_editPerson,
      primaryLabel: l10n.common_save,
      isBusy: activity.isSaving,
      onPrimary: _save,
      children: [
        MonoSectionLabel(l10n.employees_sectionDetails),
        const SizedBox(height: AppSpacing.sp8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SheetFocusScroll(
                child: LabeledTextField(
                  key: const Key('firstName'),
                  label: l10n.employees_firstName,
                  controller: _firstNameController,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  maxLength: TextLimits.firstName,
                  errorText: errors['name'],
                  onChanged: (_) => _clearError('name'),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sp12),
            Expanded(
              child: SheetFocusScroll(
                child: LabeledTextField(
                  key: const Key('lastName'),
                  label: l10n.employees_lastName,
                  controller: _lastNameController,
                  optional: true,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  maxLength: TextLimits.lastName,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sp16),
        SheetFocusScroll(
          child: LabeledTextField(
            key: const Key('email'),
            label: l10n.employees_workEmail,
            controller: _emailController,
            required: true,
            keyboard: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            maxLength: TextLimits.email,
            errorText: errors['email'],
            onChanged: (_) => _clearError('email'),
          ),
        ),
        const SizedBox(height: AppSpacing.sp16),
        SheetFocusScroll(
          child: LabeledTextField(
            label: l10n.employees_phoneNumber,
            controller: _phoneController,
            optional: true,
            keyboard: TextInputType.phone,
            maxLength: TextLimits.phone,
          ),
        ),
        const SizedBox(height: AppSpacing.sp24),
        MonoSectionLabel(l10n.employees_sectionRole),
        const SizedBox(height: AppSpacing.sp8),
        JobTitleChips(
          value: _jobTitle,
          onChanged: (next) => setState(() => _jobTitle = next),
        ),
        const SizedBox(height: AppSpacing.sp24),
        MonoSectionLabel(l10n.employees_sectionColour),
        const SizedBox(height: AppSpacing.sp8),
        EmployeeColorGrid(
          selectedColor: _selectedColor,
          usedColors: widget.usedColors,
          onColorSelected: (value) => setState(() => _selectedColor = value),
        ),
        const SizedBox(height: AppSpacing.sp8),
        Text(
          l10n.employees_coloursLeft(
            availableCrewColorCount(widget.usedColors),
          ),
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.palette.textTertiary,
          ),
        ),
        const SizedBox(height: AppSpacing.sp24),
        MonoSectionLabel(l10n.employees_sectionAvailability),
        const SizedBox(height: AppSpacing.sp8),
        SheetPanel(
          children: [
            _PanelRow(
              label: l10n.employees_workingDays,
              child: WorkingDaysPicker(
                workingDays: _workingDays,
                onChanged: (next) => setState(() => _workingDays = next),
              ),
            ),
            SheetFieldRow(
              label: l10n.employees_startsAt,
              value: materialL10n.formatTimeOfDay(
                minutesToTimeOfDay(_workStartMinutes),
              ),
              useMonoValue: true,
              accent: true,
              onTap: () => _pickTime(isStart: true),
            ),
            SheetFieldRow(
              label: l10n.employees_endsAt,
              value: materialL10n.formatTimeOfDay(
                minutesToTimeOfDay(_workEndMinutes),
              ),
              useMonoValue: true,
              accent: true,
              errorText: errors['hours'],
              onTap: () => _pickTime(isStart: false),
            ),
            SheetFieldRow(
              label: l10n.employees_maxJobsPerDay,
              value: _maxJobsPerDay == 0
                  ? l10n.employees_noCap
                  : '$_maxJobsPerDay',
              useMonoValue: true,
              onTap: _pickMaxJobs,
            ),
            _PanelRow(
              label: l10n.employees_onCall,
              trailing: Switch.adaptive(
                value: _onCall,
                activeTrackColor: theme.colorScheme.primary,
                onChanged: (value) => setState(() => _onCall = value),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sp16),
        // Free-text stays a LabeledTextField, outside the panel — it owns the
        // error shake and the clear button a panel row has neither of.
        SheetFocusScroll(
          child: LabeledTextField(
            label: l10n.employees_emergencyContact,
            controller: _emergencyController,
            optional: true,
            maxLength: TextLimits.employeeEmergencyContact,
          ),
        ),
        const SizedBox(height: AppSpacing.sp24),
        MonoSectionLabel(l10n.employees_sectionAccess),
        const SizedBox(height: AppSpacing.sp8),
        SwitchListTile.adaptive(
          key: const Key('adminAccess'),
          value: _isAdmin,
          activeTrackColor: theme.colorScheme.primary,
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.employees_adminAccess),
          subtitle: Text(l10n.employees_adminAccessDescription),
          onChanged: (value) => setState(() => _isAdmin = value),
        ),
        const SizedBox(height: AppSpacing.sp24),
        _StatusFooter(
          employeeId: widget.employee.id,
          isDisabled: _isDisabled,
          isBusy: activity.isTogglingStatus,
          onToggle: _confirmToggleStatus,
        ),
      ],
    );
  }
}

/// A panel row that is not a picker — a label beside arbitrary content
/// (the working-day strip) or a trailing control (the on-call switch).
class _PanelRow extends StatelessWidget {
  const _PanelRow({required this.label, this.child, this.trailing});

  final String label;
  final Widget? child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelText = Text(
      label,
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sp16,
        vertical: AppSpacing.sp12,
      ),
      child: trailing != null
          ? Row(
              children: [
                Expanded(child: labelText),
                const SizedBox(width: AppSpacing.sp8),
                trailing!,
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                labelText,
                const SizedBox(height: AppSpacing.sp8),
                child!,
              ],
            ),
    );
  }
}

/// Disable / re-enable, with the count of jobs a human still has to move.
///
/// P4 reassigns nothing — the spec's words are "availability changes notify,
/// a human moves the work". The count is information, not an action.
class _StatusFooter extends ConsumerWidget {
  const _StatusFooter({
    required this.employeeId,
    required this.isDisabled,
    required this.isBusy,
    required this.onToggle,
  });

  final String employeeId;
  final bool isDisabled;
  final bool isBusy;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final futureJobs = ref.watch(futureAssignmentCountProvider(employeeId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          style: destructiveOutlinedButtonStyle(
            context,
            minimumSize: const Size(double.infinity, 48),
          ),
          onPressed: isBusy ? null : onToggle,
          icon: Icon(
            isDisabled ? Icons.lock_open_outlined : Icons.block_outlined,
            size: 18,
          ),
          label: Text(
            isDisabled
                ? l10n.employees_enableEmployee
                : l10n.employees_disableEmployee,
          ),
        ),
        // Only meaningful before disabling — after, the work has already been
        // left assigned and the caption would be nagging about the past.
        if (!isDisabled && futureJobs.hasValue)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sp8),
            child: Text(
              l10n.employees_disableReassignCaption(futureJobs.requireValue),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.palette.textTertiary,
              ),
            ),
          ),
      ],
    );
  }
}

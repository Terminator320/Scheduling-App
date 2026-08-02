import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/errors/error_cause.dart';
import 'package:scheduling/core/notices/notice_service.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/core/validators/phone_format.dart';
import 'package:scheduling/core/validators/text_limits.dart';
import 'package:scheduling/features/employees/application/employee_form_controller.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';
import 'package:scheduling/features/employees/domain/models/job_title.dart';
import 'package:scheduling/features/employees/domain/policies/crew_color_policy.dart';
import 'package:scheduling/features/employees/domain/policies/employee_form_validator.dart';
import 'package:scheduling/features/employees/domain/policies/employee_name_policy.dart';
import 'package:scheduling/features/employees/widgets/dialogs/signup_code_dialog.dart';
import 'package:scheduling/features/employees/widgets/fields/employee_color_grid.dart';
import 'package:scheduling/features/employees/widgets/fields/job_title_chips.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/feedback/warning_note.dart';
import 'package:scheduling/shared/widgets/fields/labeled_text_field.dart';
import 'package:scheduling/shared/widgets/primitives/mono_section_label.dart';
import 'package:scheduling/shared/widgets/sheets/app_bottom_sheet.dart';
import 'package:scheduling/shared/widgets/sheets/form_sheet_frame.dart';
import 'package:scheduling/shared/widgets/sheets/sheet_widgets.dart';

/// Opens the invite sheet. Resolves to `true` once the invite is created and
/// the admin has dismissed the signup-code dialog, null otherwise.
///
/// Deliberately NOT returning the created record: the invite is written
/// server-side by `createEmployeeInvite`, so the client never holds the doc id.
/// The roster picks it up from the live users stream.
Future<bool?> showInvitePersonSheet(
  BuildContext context, {
  required Set<int> usedColors,
}) => showAppBottomSheet<bool>(
  context,
  builder: (_) => InvitePersonSheet(usedColors: usedColors),
);

class InvitePersonSheet extends ConsumerStatefulWidget {
  const InvitePersonSheet({super.key, this.usedColors = const {}});

  final Set<int> usedColors;

  @override
  ConsumerState<InvitePersonSheet> createState() => _InvitePersonSheetState();
}

class _InvitePersonSheetState extends ConsumerState<InvitePersonSheet> {
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();

  JobTitle _jobTitle = JobTitle.unset;
  late int _selectedColor;
  bool _isAdmin = false;
  final Map<String, String?> errors = {};

  @override
  void initState() {
    super.initState();
    // Seed the first colour nobody holds, so the default pick is not a
    // duplicate the admin has to notice and change.
    _selectedColor = AppColors.crewPalette
        .firstWhere(
          (c) => !widget.usedColors.contains(c.toARGB32()),
          orElse: () => AppColors.crewPalette.first,
        )
        .toARGB32();
  }

  @override
  void dispose() {
    for (final controller in [
      _firstNameController,
      _lastNameController,
      _emailController,
      _phoneController,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _clearError(String key) {
    if (errors[key] == null) return;
    setState(() => errors[key] = null);
  }

  Future<void> _save() async {
    // Both halves are required here: an invite with no name produces a roster
    // row with nothing to identify.
    final composedName = composeEmployeeName(
      firstName: _firstNameController.text,
      lastName: _lastNameController.text,
      fallback: '',
    );
    final nextErrors = EmployeeFormValidator.validate(
      l10n: context.l10n,
      firstName: _firstNameController.text,
      lastName: _lastNameController.text,
      email: _emailController.text.trim(),
      requireLastName: true,
    );
    setState(() {
      errors
        ..clear()
        ..addAll(nextErrors);
    });
    if (nextErrors.values.any((e) => e != null)) return;

    if (guardedOffline(
      context,
      ref,
      intro: context.l10n.error_introSaveEmployee,
      tag: 'EMP-CREATE',
    )) {
      return;
    }

    final outcome = await ref
        .read(employeeFormControllerProvider.notifier)
        .inviteEmployee(
          EmployeeRecord(
            id: '',
            name: composedName,
            firstName: _firstNameController.text.trim(),
            lastName: _lastNameController.text.trim(),
            email: _emailController.text.trim().toLowerCase(),
            phone: _phoneController.text.trim(),
            color: Color(_selectedColor),
            role: _isAdmin ? 'admin' : 'employee',
            jobTitle: _jobTitle,
          ),
        );
    if (!mounted) return;

    switch (outcome) {
      case EmployeeInvited(:final code):
        await showSignupCodeDialog(
          context,
          name: _firstNameController.text.trim(),
          code: code,
        );
        if (!mounted) return;
        Navigator.pop(context, true);
      case EmployeeEmailInUse(:final failure):
        setState(() => errors['email'] = failure.toLocalizedMessage(context));
      case EmployeeSaveFailed(:final error):
        ref
            .read(noticeServiceProvider)
            .error(
              composeErrorNotice(
                context,
                intro: context.l10n.error_introSaveEmployee,
                tag: 'EMP-CREATE',
                error: error,
              ),
            );
      case EmployeeUpdated():
        // Unreachable from the invite path; the sealed family forces the
        // branch.
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final activity = ref.watch(employeeFormControllerProvider);

    return FormSheetFrame(
      title: l10n.employees_invitePerson,
      primaryLabel: l10n.employees_sendInvite,
      isBusy: activity.isSaving,
      onPrimary: _save,
      children: [
        ..._detailsSection(theme, l10n),
        ..._roleSection(theme, l10n),
        ..._colourSection(theme, l10n),
        ..._accessSection(theme, l10n),
      ],
    );
  }

  List<Widget> _detailsSection(ThemeData theme, AppLocalizations l10n) => [
    MonoSectionLabel(l10n.employees_sectionDetails),
    const SizedBox(height: AppSpacing.sp8),
    SheetFocusScroll(
      child: LabeledTextField(
        key: const Key('firstName'),
        label: l10n.employees_firstName,
        controller: _firstNameController,
        required: true,
        textCapitalization: TextCapitalization.words,
        textInputAction: TextInputAction.next,
        maxLength: TextLimits.employeeNameHalf,
        errorText: errors['name'],
        onChanged: (_) => _clearError('name'),
      ),
    ),
    const SizedBox(height: AppSpacing.sp16),
    SheetFocusScroll(
      child: LabeledTextField(
        key: const Key('lastName'),
        label: l10n.employees_lastName,
        controller: _lastNameController,
        required: true,
        textCapitalization: TextCapitalization.words,
        textInputAction: TextInputAction.next,
        maxLength: TextLimits.employeeNameHalf,
        errorText: errors['lastName'],
        onChanged: (_) => _clearError('lastName'),
      ),
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
        inputFormatters: const [PhoneInputFormatter()],
        maxLength: TextLimits.phone,
      ),
    ),
    const SizedBox(height: AppSpacing.sp24),
  ];

  List<Widget> _roleSection(ThemeData theme, AppLocalizations l10n) => [
    MonoSectionLabel(l10n.employees_sectionRole),
    const SizedBox(height: AppSpacing.sp8),
    JobTitleChips(
      value: _jobTitle,
      onChanged: (next) => setState(() => _jobTitle = next),
    ),
    const SizedBox(height: AppSpacing.sp24),
  ];

  List<Widget> _colourSection(ThemeData theme, AppLocalizations l10n) => [
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
  ];

  List<Widget> _accessSection(ThemeData theme, AppLocalizations l10n) => [
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
    WarningNote(message: context.l10n.employees_invitedNote),
  ];
}

/// The amber advisory under the form. Warning-toned on purpose — the account

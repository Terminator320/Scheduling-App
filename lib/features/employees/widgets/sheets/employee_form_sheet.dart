import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scheduling/core/animations/animated_loading_button.dart';
import 'package:scheduling/core/errors/error_cause.dart';
import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/core/notices/notice_service.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/core/validators/text_limits.dart';
import 'package:scheduling/features/employees/application/employees_providers.dart';
import 'package:scheduling/features/employees/domain/employees_failure.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';
import 'package:scheduling/features/employees/widgets/fields/employee_color_picker_row.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/feedback/status_chip.dart';
import 'package:scheduling/shared/widgets/fields/form_helpers.dart';
import 'package:scheduling/shared/widgets/fields/labeled_text_field.dart';
import 'package:scheduling/shared/widgets/primitives/busy_button_icon.dart';
import 'package:scheduling/shared/widgets/primitives/entity_form_header.dart';
import 'package:scheduling/shared/widgets/sheets/sheet_widgets.dart';

class EmployeeFormSheet extends ConsumerStatefulWidget {
  const EmployeeFormSheet({
    super.key,
    this.employee,
    this.usedColors = const {},
  });

  final EmployeeRecord? employee;
  final Set<int> usedColors;

  @override
  ConsumerState<EmployeeFormSheet> createState() => _EmployeeFormSheetState();
}

class _EmployeeFormSheetState extends ConsumerState<EmployeeFormSheet> {
  late final TextEditingController _nameController;
  late final TextEditingController _emailController;
  late final TextEditingController _phoneController;

  late bool _isAdmin;
  late int _selectedColor;
  late bool _isDisabled;
  bool _isSaving = false;
  bool _isTogglingStatus = false;
  final Map<String, String?> _errors = {};

  bool get _isEdit => widget.employee != null;

  @override
  void initState() {
    super.initState();
    final e = widget.employee;
    _nameController = TextEditingController(text: e?.name ?? '');
    _emailController = TextEditingController(text: e?.email ?? '');
    _phoneController = TextEditingController(text: e?.phone ?? '');
    _isAdmin = e?.isAdmin ?? false;
    _isDisabled = e?.isDisabled ?? false;
    _selectedColor =
        e?.color.toARGB32() ?? AppColors.employeePalette.first.toARGB32();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  bool _validate() {
    final errors = <String, String?>{};
    if (_nameController.text.trim().isEmpty) {
      errors['name'] = context.l10n.error_nameAndEmailAreRequired;
    }
    if (_emailController.text.trim().isEmpty) {
      errors['email'] = context.l10n.error_nameAndEmailAreRequired;
    }
    setState(() {
      _errors
        ..clear()
        ..addAll(errors);
    });
    return errors.isEmpty;
  }

  Future<void> _save() async {
    if (!_validate()) return;

    setState(() => _isSaving = true);

    final repo = ref.read(employeesRepositoryProvider);
    final notices = ref.read(noticeServiceProvider);
    try {
      final name = _nameController.text.trim();
      final email = _emailController.text.trim().toLowerCase();
      final phone = _phoneController.text.trim();
      final colorValue = _selectedColor.toString();

      if (_isEdit) {
        await repo.updateEmployee(
          docId: widget.employee!.id,
          name: name,
          email: email,
          phone: phone,
          colorValue: colorValue,
          isAdmin: _isAdmin,
        );
      } else {
        await repo.addEmployee(
          name: name,
          email: email,
          phone: phone,
          colorValue: colorValue,
        );
      }

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e, st) {
      if (e is EmployeesFailureEmailAlreadyExists) {
        if (!mounted) return;
        setState(() => _errors['email'] = e.toLocalizedMessage(context));
      } else {
        ref.read(loggerProvider).warn('EMP-CREATE saveEmployee failed', e, st);
        if (!mounted) return;
        notices.error(
          composeErrorNotice(
            context,
            intro: context.l10n.error_introSaveEmployee,
            tag: 'EMP-CREATE',
            error: e,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _toggleStatus() async {
    setState(() => _isTogglingStatus = true);
    final repo = ref.read(employeesRepositoryProvider);
    try {
      if (_isDisabled) {
        await repo.reactivateEmployee(widget.employee!.id);
      } else {
        await repo.deactivateEmployee(widget.employee!.id);
      }
      if (mounted) setState(() => _isDisabled = !_isDisabled);
    } catch (e, st) {
      ref
          .read(loggerProvider)
          .warn('EMP-STATUS toggleEmployeeStatus failed', e, st);
      if (!mounted) return;
      ref
          .read(noticeServiceProvider)
          .error(
            composeErrorNotice(
              context,
              intro: context.l10n.error_introChangeEmployeeStatus,
              tag: 'EMP-STATUS',
              error: e,
            ),
          );
    } finally {
      if (mounted) setState(() => _isTogglingStatus = false);
    }
  }

  Widget _buildEditHeader() {
    final e = widget.employee!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        EntityFormHeader(
          name: e.name,
          avatarColor: e.color,
          status: StatusChip(
            status: _isDisabled
                ? AppointmentStatus.disabled
                : AppointmentStatus.active,
          ),
        ),
        const SizedBox(height: AppSpacing.sp16),
        const Divider(height: 1),
      ],
    );
  }

  Widget _buildPermissionsCard(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        formLabel(context, context.l10n.employees_permissions),
        Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(AppRadius.r12),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sp12,
            vertical: 10,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.employees_adminAccess,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      context.l10n.employees_adminAccessDescription,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: _isAdmin,
                onChanged: (v) => setState(() => _isAdmin = v),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAccountStatusSection(ThemeData theme) {
    final scheme = theme.colorScheme;
    final statusColors = theme.statusColors;
    final toggleForeground = _isDisabled
        ? statusColors.onSuccessContainer
        : statusColors.onWarningContainer;
    final toggleBorder = _isDisabled
        ? statusColors.success
        : statusColors.warning;
    final toggleIcon = _isDisabled
        ? Icons.check_circle_outline
        : Icons.block_outlined;
    final toggleLabel = _isDisabled
        ? context.l10n.employees_reEnableAccount
        : context.l10n.employees_disableAccount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 1),
        const SizedBox(height: AppSpacing.sp16),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.l10n.employees_accountStatus,
                    // NOTE: source size 13 is between bodySmall (12) and
                    // bodyMedium (14); bodySmall is the nearer role.
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    context.l10n.employees_accountStatusDescription,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sp8),
            StatusChip(
              status: _isDisabled
                  ? AppointmentStatus.disabled
                  : AppointmentStatus.active,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sp12),
        OutlinedButton.icon(
          onPressed: _isTogglingStatus ? null : _toggleStatus,
          icon: BusyButtonIcon(
            isBusy: _isTogglingStatus,
            icon: toggleIcon,
            iconSize: 14,
            color: toggleForeground,
          ),
          label: Text(toggleLabel, style: TextStyle(color: toggleForeground)),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(double.infinity, 44),
            side: BorderSide(color: toggleBorder),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.r8),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sp8),
        Text(
          _isDisabled
              ? context.l10n.employees_reEnableAccountNote
              : context.l10n.employees_disableAccountNote,
          textAlign: TextAlign.center,
          style: theme.textTheme.labelSmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = _isEdit
        ? context.l10n.employees_editEmployee
        : context.l10n.employees_inviteEmployee;
    final submitLabel = _isEdit
        ? context.l10n.common_saveChanges
        : context.l10n.employees_sendInvite;

    return FormSheetScaffold(
      title: title,
      children: [
        const SizedBox(height: AppSpacing.sp16),
        const Divider(height: 1),
        if (_isEdit) ...[
          const SizedBox(height: AppSpacing.sp4),
          _buildEditHeader(),
          const SizedBox(height: 14),
        ] else
          const SizedBox(height: 20),
        ..._buildIdentityFields(),
        // Admin access is grantable only after activation — an invited
        // admin can't self-activate (firestore.rules), so the toggle is
        // edit-only.
        if (_isEdit) ...[
          const SizedBox(height: AppSpacing.sp16),
          _buildPermissionsCard(theme),
        ],
        const SizedBox(height: AppSpacing.sp12),
        EmployeeColorPickerRow(
          selectedColor: _selectedColor,
          onColorChanged: (value) => setState(() => _selectedColor = value),
          required: !_isEdit,
          usedColors: widget.usedColors,
        ),
        const SizedBox(height: AppSpacing.sp16),
        AnimatedLoadingButton(
          label: submitLabel,
          isLoading: _isSaving,
          onPressed: _save,
          height: 48,
        ),
        if (_isEdit) ...[
          const SizedBox(height: AppSpacing.sp16),
          _buildAccountStatusSection(theme),
        ],
      ],
    );
  }

  List<Widget> _buildIdentityFields() {
    return [
      SheetFocusScroll(
        child: LabeledTextField(
          label: context.l10n.employees_name,
          controller: _nameController,
          required: !_isEdit,
          maxLength: TextLimits.personName,
          errorText: _errors['name'],
          onChanged: (_) {
            if (_errors['name'] != null) {
              setState(() => _errors['name'] = null);
            }
          },
        ),
      ),
      const SizedBox(height: AppSpacing.sp12),
      SheetFocusScroll(
        child: LabeledTextField(
          label: context.l10n.common_email,
          controller: _emailController,
          keyboard: TextInputType.emailAddress,
          required: !_isEdit,
          maxLength: TextLimits.email,
          errorText: _errors['email'],
          onChanged: (_) {
            if (_errors['email'] != null) {
              setState(() => _errors['email'] = null);
            }
          },
        ),
      ),
      const SizedBox(height: AppSpacing.sp12),
      SheetFocusScroll(
        child: LabeledTextField(
          label: context.l10n.employees_phoneNumber,
          controller: _phoneController,
          keyboard: TextInputType.phone,
          optional: true,
          maxLength: TextLimits.phone,
        ),
      ),
    ];
  }
}

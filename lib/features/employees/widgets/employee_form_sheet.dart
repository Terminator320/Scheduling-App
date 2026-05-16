import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/notices/notice_service.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/core/utils/l10n_extensions.dart';
import 'package:scheduling/core/validators/text_limits.dart';
import 'package:scheduling/features/employees/application/employees_providers.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';
import 'package:scheduling/features/employees/widgets/employee_color_picker_row.dart';
import 'package:scheduling/shared/widgets/app_avatar.dart';
import 'package:scheduling/shared/widgets/form_helpers.dart';
import 'package:scheduling/shared/widgets/labeled_text_field.dart';
import 'package:scheduling/shared/widgets/sheet_widgets.dart';
import 'package:scheduling/shared/widgets/status_chip.dart';

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
      errors['name'] = context.l10n.nameAndEmailAreRequired;
    }
    if (_emailController.text.trim().isEmpty) {
      errors['email'] = context.l10n.nameAndEmailAreRequired;
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
          isAdmin: _isAdmin,
        );
      }

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      final isDuplicate = e.toString().contains(
        'Employee email already exists',
      );
      if (isDuplicate) {
        setState(
          () => _errors['email'] =
              context.l10n.anEmployeeWithThisEmailAlreadyExists,
        );
      }
      notices.error(
        isDuplicate
            ? context.l10n.anEmployeeWithThisEmailAlreadyExists
            : context.l10n.couldNotCreateEmployee,
      );
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
    } finally {
      if (mounted) setState(() => _isTogglingStatus = false);
    }
  }

  Widget _buildEditHeader(ThemeData theme) {
    final e = widget.employee!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            AppAvatar(name: e.name, color: e.color, size: AvatarSize.lg),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  e.name,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                StatusChip(
                  status: _isDisabled
                      ? AppointmentStatus.disabled
                      : AppointmentStatus.active,
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        const Divider(height: 1),
      ],
    );
  }

  Widget _buildPermissionsCard(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        formLabel(context, context.l10n.permissions),
        Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(AppRadius.r12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.adminAccess,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      context.l10n.adminAccessDescription,
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 1),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.l10n.accountStatus,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    context.l10n.accountStatusDescription,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            StatusChip(
              status: _isDisabled
                  ? AppointmentStatus.disabled
                  : AppointmentStatus.active,
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_isDisabled)
          OutlinedButton.icon(
            onPressed: _isTogglingStatus ? null : _toggleStatus,
            icon: _isTogglingStatus
                ? SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: statusColors.onSuccessContainer,
                    ),
                  )
                : Icon(
                    Icons.check_circle_outline,
                    size: 14,
                    color: statusColors.onSuccessContainer,
                  ),
            label: Text(
              context.l10n.reEnableAccount,
              style: TextStyle(color: statusColors.onSuccessContainer),
            ),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 44),
              side: BorderSide(color: statusColors.success),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.r8),
              ),
            ),
          )
        else
          OutlinedButton.icon(
            onPressed: _isTogglingStatus ? null : _toggleStatus,
            icon: _isTogglingStatus
                ? SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: statusColors.onWarningContainer,
                    ),
                  )
                : Icon(
                    Icons.block_outlined,
                    size: 14,
                    color: statusColors.onWarningContainer,
                  ),
            label: Text(
              context.l10n.disableAccount,
              style: TextStyle(color: statusColors.onWarningContainer),
            ),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 44),
              side: BorderSide(color: statusColors.warning),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.r8),
              ),
            ),
          ),
        const SizedBox(height: 8),
        Text(
          _isDisabled
              ? context.l10n.reEnableAccountNote
              : context.l10n.disableAccountNote,
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
        ? context.l10n.editEmployee
        : context.l10n.inviteEmployee;
    final submitLabel = _isEdit
        ? context.l10n.saveChanges
        : context.l10n.sendInvite;

    return DraggableSheetFrame(
      builder: (sheetContext, scrollController) {
        return ListView(
          controller: scrollController,
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 12,
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 24,
          ),
          children: [
            const SheetHandle(),
            const SizedBox(height: 16),
            Text(title, style: theme.textTheme.headlineLarge),
            const SizedBox(height: 16),
            const Divider(height: 1),
            if (_isEdit) ...[
              const SizedBox(height: 4),
              _buildEditHeader(theme),
              const SizedBox(height: 14),
            ] else
              const SizedBox(height: 20),
            SheetFocusScroll(
              child: LabeledTextField(
                label: context.l10n.name2,
                controller: _nameController,
                required: !_isEdit,
                maxLength: TextLimits.personName,
                errorText: _errors['name'],
                onChanged: (_) {
                  if (_errors['name'] != null)
                    setState(() => _errors['name'] = null);
                },
              ),
            ),
            const SizedBox(height: 12),
            SheetFocusScroll(
              child: LabeledTextField(
                label: context.l10n.email,
                controller: _emailController,
                keyboard: TextInputType.emailAddress,
                required: !_isEdit,
                maxLength: TextLimits.email,
                errorText: _errors['email'],
                onChanged: (_) {
                  if (_errors['email'] != null)
                    setState(() => _errors['email'] = null);
                },
              ),
            ),
            const SizedBox(height: 12),
            SheetFocusScroll(
              child: LabeledTextField(
                label: context.l10n.phoneNumber,
                controller: _phoneController,
                keyboard: TextInputType.phone,
                optional: true,
                maxLength: TextLimits.phone,
              ),
            ),
            const SizedBox(height: 16),
            _buildPermissionsCard(theme),
            const SizedBox(height: 12),
            EmployeeColorPickerRow(
              selectedColor: _selectedColor,
              onColorChanged: (value) => setState(() => _selectedColor = value),
              required: !_isEdit,
              usedColors: widget.usedColors,
            ),
            const SizedBox(height: 16),
            FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
              ),
              onPressed: _isSaving ? null : _save,
              child: _isSaving
                  ? SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: theme.colorScheme.onPrimary,
                      ),
                    )
                  : Text(submitLabel),
            ),
            if (_isEdit) ...[
              const SizedBox(height: 16),
              _buildAccountStatusSection(theme),
            ],
          ],
        );
      },
    );
  }
}

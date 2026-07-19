import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scheduling/core/errors/error_cause.dart';
import 'package:scheduling/core/layout/breakpoints.dart';
import 'package:scheduling/core/notices/notice_service.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/features/employees/application/employee_form_controller.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/dialogs/confirm_dialog.dart';
import 'package:scheduling/shared/widgets/feedback/user_status_chip.dart';
import 'package:scheduling/shared/widgets/primitives/busy_button_icon.dart';
import 'package:scheduling/shared/widgets/sheets/sheet_widgets.dart';

class EmployeeDetailsView extends ConsumerStatefulWidget {
  const EmployeeDetailsView({
    required this.employee,
    required this.isCurrentUserAdmin,
    required this.onAction,
    super.key,
    this.scrollController,
    this.showHandle = false,
    this.bottomPadding = 24,
  });

  final EmployeeRecord employee;
  final bool isCurrentUserAdmin;

  /// Receives the action name (`'edit'`, `'deleted'`, `'enabled'`,
  /// `'disabled'`) so the host sheet/pane can react.
  final ValueChanged<String> onAction;
  final ScrollController? scrollController;
  final bool showHandle;
  final double bottomPadding;

  @override
  ConsumerState<EmployeeDetailsView> createState() =>
      _EmployeeDetailsViewState();
}

class _EmployeeDetailsViewState extends ConsumerState<EmployeeDetailsView> {
  Future<void> _confirmDelete() async {
    final confirmed = await showConfirmDialog(
      context,
      title: context.l10n.employees_deleteEmployee,
      message: context.l10n.employees_areYouSureYouWantToDeleteThisEmployee,
      confirmLabel: context.l10n.common_delete,
    );
    if (!mounted || !confirmed) return;
    final outcome = await ref
        .read(employeeFormControllerProvider.notifier)
        .deleteEmployee(widget.employee.id);
    if (!mounted) return;
    switch (outcome) {
      case EmployeeDeleted():
        widget.onAction('deleted');
      case EmployeeDeleteFailed(:final error):
        ref
            .read(noticeServiceProvider)
            .error(
              composeErrorNotice(
                context,
                intro: context.l10n.error_introDeleteEmployee,
                tag: 'EMP-DEL',
                error: error,
              ),
            );
    }
  }

  Future<void> _confirmDisable() async {
    final isDisabled = widget.employee.isDisabled;
    final actionLabel = isDisabled
        ? context.l10n.employees_enableEmployee
        : context.l10n.employees_disableEmployee;
    final confirmed = await showConfirmDialog(
      context,
      title: actionLabel,
      message: isDisabled
          ? context.l10n.employees_enableEmployeeConfirmBody
          : context.l10n.employees_disableEmployeeConfirmBody,
      confirmLabel: actionLabel,
      destructive: !isDisabled,
    );
    if (!mounted || !confirmed) return;
    final outcome = await ref
        .read(employeeFormControllerProvider.notifier)
        .setEmployeeStatus(docId: widget.employee.id, disable: !isDisabled);
    if (!mounted) return;
    switch (outcome) {
      case EmployeeStatusChanged():
        widget.onAction(isDisabled ? 'enabled' : 'disabled');
      case EmployeeStatusChangeFailed(:final error):
        ref
            .read(noticeServiceProvider)
            .error(
              composeErrorNotice(
                context,
                intro: context.l10n.error_introChangeEmployeeStatus,
                tag: 'EMP-STATUS',
                error: error,
              ),
            );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDisabled = widget.employee.isDisabled;
    final activity = ref.watch(employeeFormControllerProvider);
    final stackedHeader = context.isCompact;

    final headerTitle = Text(
      context.l10n.employees_employeeDetails,
      style: theme.textTheme.headlineLarge,
    );
    final statusChip = UserStatusChip(
      status: UserStatus.fromRaw(widget.employee.status),
    );

    return DetailSheetListView(
      scrollController: widget.scrollController,
      showHandle: widget.showHandle,
      bottomPadding: widget.bottomPadding,
      children: [
        if (stackedHeader)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              headerTitle,
              const SizedBox(height: AppSpacing.sp8),
              statusChip,
            ],
          )
        else
          Row(
            children: [
              Expanded(child: headerTitle),
              const SizedBox(width: AppSpacing.sp8),
              statusChip,
            ],
          ),
        const SizedBox(height: AppSpacing.sp16),
        const Divider(height: 1),
        const SizedBox(height: AppSpacing.sp24),
        _DetailField(
          icon: Icons.person_outline,
          label: context.l10n.employees_name,
          value: widget.employee.name,
        ),
        const SizedBox(height: AppSpacing.sp12),
        _DetailField(
          icon: Icons.email_outlined,
          label: context.l10n.common_email,
          value: widget.employee.email,
        ),
        const SizedBox(height: AppSpacing.sp12),
        _DetailField(
          icon: Icons.phone_outlined,
          label: context.l10n.employees_phoneNumber,
          value: widget.employee.phone.isEmpty ? '-' : widget.employee.phone,
        ),
        const SizedBox(height: AppSpacing.sp12),
        _DetailField(
          icon: Icons.shield_outlined,
          label: context.l10n.employees_role,
          value: widget.employee.isAdmin
              ? context.l10n.common_admin
              : context.l10n.common_employeeRoleValue,
        ),
        const SizedBox(height: AppSpacing.sp12),
        _ColorRow(color: widget.employee.color),
        const SizedBox(height: AppSpacing.sp24),
        const Divider(height: 1),
        const SizedBox(height: AppSpacing.sp16),
        _ActionButtons(
          isCurrentUserAdmin: widget.isCurrentUserAdmin,
          isDisabled: isDisabled,
          isDeleting: activity.isDeleting,
          isDisabling: activity.isTogglingStatus,
          onEdit: () => widget.onAction('edit'),
          onToggleStatus: _confirmDisable,
          onDelete: _confirmDelete,
        ),
      ],
    );
  }
}

/// The employee colour swatch row (icon + label + colour dot).
class _ColorRow extends StatelessWidget {
  const _ColorRow({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Padding(
          padding: const EdgeInsets.only(right: AppSpacing.sp12),
          child: Icon(
            Icons.palette_outlined,
            size: 16,
            color: theme.colorScheme.primary,
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.employees_employeeColor,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.sp4),
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: theme.colorScheme.outlineVariant),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Edit / (admin) Disable-or-Enable / Delete action stack for the detail view.
class _ActionButtons extends StatelessWidget {
  const _ActionButtons({
    required this.isCurrentUserAdmin,
    required this.isDisabled,
    required this.isDeleting,
    required this.isDisabling,
    required this.onEdit,
    required this.onToggleStatus,
    required this.onDelete,
  });

  final bool isCurrentUserAdmin;
  final bool isDisabled;
  final bool isDeleting;
  final bool isDisabling;
  final VoidCallback onEdit;
  final VoidCallback onToggleStatus;
  final VoidCallback onDelete;

  static const _fullWidthButton = Size(double.infinity, 48);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed: onEdit,
          icon: const Icon(Icons.edit_outlined, size: 18),
          label: Text(context.l10n.common_edit),
          style: FilledButton.styleFrom(minimumSize: _fullWidthButton),
        ),
        if (isCurrentUserAdmin) ...[
          const SizedBox(height: AppSpacing.sp8),
          FilledButton.icon(
            onPressed: isDisabling ? null : onToggleStatus,
            icon: BusyButtonIcon(
              isBusy: isDisabling,
              icon: isDisabled
                  ? Icons.lock_open_outlined
                  : Icons.block_outlined,
              spinnerSize: 16,
              color: isDisabled
                  ? theme.colorScheme.onPrimary
                  : theme.colorScheme.onError,
            ),
            label: Text(
              isDisabled
                  ? context.l10n.employees_enableEmployee
                  : context.l10n.employees_disableEmployee,
            ),
            style: FilledButton.styleFrom(
              minimumSize: _fullWidthButton,
              backgroundColor: isDisabled ? null : theme.colorScheme.error,
              foregroundColor: isDisabled ? null : theme.colorScheme.onError,
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.sp8),
        OutlinedButton.icon(
          onPressed: isDeleting ? null : onDelete,
          icon: BusyButtonIcon(
            isBusy: isDeleting,
            icon: Icons.delete_outline,
            spinnerSize: 16,
            color: theme.colorScheme.error,
          ),
          label: Text(context.l10n.employees_deleteEmployee),
          style: OutlinedButton.styleFrom(
            minimumSize: _fullWidthButton,
            foregroundColor: theme.colorScheme.error,
            side: BorderSide(color: theme.colorScheme.error),
          ),
        ),
      ],
    );
  }
}

class _DetailField extends StatelessWidget {
  const _DetailField({required this.label, required this.value, this.icon});

  final String label;
  final String value;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (icon != null)
          Padding(
            padding: const EdgeInsets.only(top: 2, right: AppSpacing.sp12),
            child: Icon(icon, size: 16, color: theme.colorScheme.primary),
          ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value.isEmpty ? '-' : value,
                softWrap: true,
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

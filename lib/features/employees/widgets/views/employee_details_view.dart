import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/core/notices/notice_service.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/features/employees/application/employees_providers.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/feedback/status_chip.dart';
import 'package:scheduling/shared/widgets/sheets/sheet_widgets.dart';

typedef EmployeeDetailsAction = void Function(String action);

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
  final EmployeeDetailsAction onAction;
  final ScrollController? scrollController;
  final bool showHandle;
  final double bottomPadding;

  @override
  ConsumerState<EmployeeDetailsView> createState() =>
      _EmployeeDetailsViewState();
}

class _EmployeeDetailsViewState extends ConsumerState<EmployeeDetailsView> {
  bool _isDeleting = false;
  bool _isDisabling = false;

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.l10n.employees_deleteEmployee),
        content: Text(ctx.l10n.employees_areYouSureYouWantToDeleteThisEmployee),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(ctx.l10n.common_cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ctx.l10n.common_delete),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    setState(() => _isDeleting = true);
    try {
      await ref
          .read(employeesRepositoryProvider)
          .deleteEmployee(widget.employee.id);
      if (!mounted) return;
      widget.onAction('deleted');
    } catch (e, st) {
      ref.read(loggerProvider).warn('deleteEmployee failed', e, st);
      if (!mounted) return;
      setState(() => _isDeleting = false);
      ref.read(noticeServiceProvider).error(context.l10n.error_somethingWentWrong);
    }
  }

  Future<void> _confirmDisable() async {
    final isDisabled = widget.employee.isDisabled;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          isDisabled ? ctx.l10n.employees_enableEmployee : ctx.l10n.employees_disableEmployee,
        ),
        content: Text(
          isDisabled
              ? ctx.l10n.employees_enableEmployeeConfirmBody
              : ctx.l10n.employees_disableEmployeeConfirmBody,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(ctx.l10n.common_cancel),
          ),
          FilledButton(
            style: isDisabled
                ? null
                : FilledButton.styleFrom(
                    backgroundColor: Theme.of(ctx).colorScheme.error,
                    foregroundColor: Theme.of(ctx).colorScheme.onError,
                  ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              isDisabled ? ctx.l10n.employees_enableEmployee : ctx.l10n.employees_disableEmployee,
            ),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    setState(() => _isDisabling = true);
    try {
      final repo = ref.read(employeesRepositoryProvider);
      if (isDisabled) {
        await repo.reactivateEmployee(widget.employee.id);
      } else {
        await repo.deactivateEmployee(widget.employee.id);
      }
      if (!mounted) return;
      widget.onAction(isDisabled ? 'enabled' : 'disabled');
    } catch (e, st) {
      ref.read(loggerProvider).warn('toggleEmployeeStatus failed', e, st);
      if (!mounted) return;
      setState(() => _isDisabling = false);
      ref.read(noticeServiceProvider).error(context.l10n.error_somethingWentWrong);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDisabled = widget.employee.isDisabled;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return ListView(
      controller: widget.scrollController,
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: bottomInset + widget.bottomPadding,
      ),
      children: [
        if (widget.showHandle) const SheetHandle(),
        if (widget.showHandle) const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: Text(
                context.l10n.employees_employeeDetails,
                style: theme.textTheme.headlineLarge,
              ),
            ),
            const SizedBox(width: 8),
            StatusChip(
              status: isDisabled
                  ? AppointmentStatus.disabled
                  : AppointmentStatus.active,
            ),
          ],
        ),
        const SizedBox(height: 16),
        const Divider(height: 1),
        const SizedBox(height: 20),
        _DetailField(
          icon: Icons.person_outline,
          label: context.l10n.employees_name,
          value: widget.employee.name,
        ),
        const SizedBox(height: 12),
        _DetailField(
          icon: Icons.email_outlined,
          label: context.l10n.common_email,
          value: widget.employee.email,
        ),
        const SizedBox(height: 12),
        _DetailField(
          icon: Icons.phone_outlined,
          label: context.l10n.employees_phoneNumber,
          value: widget.employee.phone.isEmpty ? '-' : widget.employee.phone,
        ),
        const SizedBox(height: 12),
        _DetailField(
          icon: Icons.shield_outlined,
          label: context.l10n.employees_role,
          value: widget.employee.isAdmin
              ? context.l10n.common_admin
              : context.l10n.common_employeeRoleValue,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
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
                const SizedBox(height: 4),
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: widget.employee.color,
                    shape: BoxShape.circle,
                    border: Border.all(color: theme.colorScheme.outlineVariant),
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 24),
        const Divider(height: 1),
        const SizedBox(height: 16),

        FilledButton.icon(
          onPressed: () => widget.onAction('edit'),
          icon: const Icon(Icons.edit_outlined, size: 18),
          label: Text(context.l10n.common_edit),
          style: FilledButton.styleFrom(
            minimumSize: const Size(double.infinity, 48),
          ),
        ),
        if (widget.isCurrentUserAdmin) ...[
          const SizedBox(height: AppSpacing.sp8),
          FilledButton.icon(
            onPressed: _isDisabling ? null : _confirmDisable,
            icon: _isDisabling
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: isDisabled
                          ? theme.colorScheme.onPrimary
                          : theme.colorScheme.onError,
                    ),
                  )
                : Icon(
                    isDisabled
                        ? Icons.lock_open_outlined
                        : Icons.block_outlined,
                    size: 18,
                  ),
            label: Text(
              isDisabled
                  ? context.l10n.employees_enableEmployee
                  : context.l10n.employees_disableEmployee,
            ),
            style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 48),
              backgroundColor: isDisabled ? null : theme.colorScheme.error,
              foregroundColor: isDisabled ? null : theme.colorScheme.onError,
            ),
          ),
        ],
        // TODO(pre-ship): Remove the SizedBox and OutlinedButton below — testing only.
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _isDeleting ? null : _confirmDelete,
          icon: _isDeleting
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: theme.colorScheme.error,
                  ),
                )
              : const Icon(Icons.delete_outline, size: 18),
          label: Text(context.l10n.employees_deleteEmployee),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(double.infinity, 48),
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
            padding: const EdgeInsets.only(top: 2, right: 12),
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

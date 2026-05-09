import 'package:flutter/material.dart';

import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/core/utils/l10n_extensions.dart';
import 'package:scheduling/features/employees/models/employee_record.dart';
import 'package:scheduling/features/employees/services/user_service.dart';
import 'package:scheduling/shared/widgets/sheet_widgets.dart';
import 'package:scheduling/shared/widgets/status_chip.dart';

class EmployeeDetailsSheet extends StatefulWidget {
  const EmployeeDetailsSheet({super.key, required this.employee});
  final EmployeeRecord employee;

  @override
  State<EmployeeDetailsSheet> createState() => _EmployeeDetailsSheetState();
}

class _EmployeeDetailsSheetState extends State<EmployeeDetailsSheet> {
  final _userService = UserService();
  bool _isLoading = false;

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.l10n.deleteEmployee),
        content: Text(ctx.l10n.areYouSureYouWantToDeleteThisEmployee),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(ctx.l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ctx.l10n.delete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _isLoading = true);
    try {
      await _userService.deleteEmployee(widget.employee.id);
      if (mounted) Navigator.pop(context, 'deleted');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _toggleStatus() async {
    setState(() => _isLoading = true);
    try {
      if (widget.employee.isDisabled) {
        await _userService.reactivateEmployee(widget.employee.id);
      } else {
        await _userService.deactivateEmployee(widget.employee.id);
      }
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDisabled = widget.employee.isDisabled;

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
            Row(
              children: [
                Expanded(
                  child: Text(
                    context.l10n.employeeDetails,
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
              label: context.l10n.name2,
              value: widget.employee.name,
            ),
            const SizedBox(height: 12),
            _DetailField(
              icon: Icons.email_outlined,
              label: context.l10n.email,
              value: widget.employee.email,
            ),
            const SizedBox(height: 12),
            _DetailField(
              icon: Icons.phone_outlined,
              label: context.l10n.phoneNumber,
              value: widget.employee.phone.isEmpty ? '-' : widget.employee.phone,
            ),
            const SizedBox(height: 12),
            _DetailField(
              icon: Icons.shield_outlined,
              label: context.l10n.role,
              value: widget.employee.isAdmin
                  ? context.l10n.admin
                  : context.l10n.employeeRoleValue,
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Icon(Icons.palette_outlined, size: 16, color: AppColors.primary),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.employeeColor2,
                      style: theme.textTheme.labelSmall?.copyWith(color: AppColors.muted),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: widget.employee.color,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.outline),
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
              onPressed: () => Navigator.pop(context, 'edit'),
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: Text(context.l10n.edit),
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
              ),
            ),
            const SizedBox(height: 10),

            OutlinedButton.icon(
              onPressed: _isLoading ? null : _confirmDelete,
              icon: const Icon(Icons.delete_outline, size: 18, color: AppColors.error),
              label: Text(context.l10n.delete, style: const TextStyle(color: AppColors.error)),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
                side: const BorderSide(color: AppColors.error),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.r8),
                ),
              ),
            ),
            const SizedBox(height: 8),

            // Enable / Disable toggle button (admin-only feature)
            if (!widget.employee.isAdmin) ...[
              const Divider(),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: isDisabled
                    ? FilledButton.icon(
                        onPressed: _isLoading ? null : _toggleStatus,
                        icon: _isLoading
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.check_circle_outline, size: 18),
                        label: Text(context.l10n.enableEmployee),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          minimumSize: const Size(double.infinity, 48),
                        ),
                      )
                    : OutlinedButton.icon(
                        onPressed: _isLoading ? null : _toggleStatus,
                        icon: _isLoading
                            ? SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.error,
                                ),
                              )
                            : const Icon(
                                Icons.block_outlined,
                                size: 18,
                                color: AppColors.error,
                              ),
                        label: Text(
                          context.l10n.disableEmployee,
                          style: const TextStyle(color: AppColors.error),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppColors.error),
                          minimumSize: const Size(double.infinity, 48),
                        ),
                      ),
              ),
            ],
          ],
        );
      },
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
            child: Icon(icon, size: 16, color: AppColors.primary),
          ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(color: AppColors.muted),
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

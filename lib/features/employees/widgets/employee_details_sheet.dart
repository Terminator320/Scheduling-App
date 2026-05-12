import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'; // TODO(pre-ship): Remove (only needed for delete)

import 'package:scheduling/core/utils/l10n_extensions.dart';
import 'package:scheduling/features/employees/application/employees_providers.dart'; // TODO(pre-ship): Remove (only needed for delete)
import 'package:scheduling/features/employees/domain/models/employee_record.dart';
import 'package:scheduling/shared/widgets/sheet_widgets.dart';
import 'package:scheduling/shared/widgets/status_chip.dart';

// TODO(pre-ship): Revert to StatefulWidget / State once delete is removed.
class EmployeeDetailsSheet extends ConsumerStatefulWidget {
  const EmployeeDetailsSheet({required this.employee, super.key});
  final EmployeeRecord employee;

  @override
  ConsumerState<EmployeeDetailsSheet> createState() =>
      _EmployeeDetailsSheetState();
}

class _EmployeeDetailsSheetState extends ConsumerState<EmployeeDetailsSheet> {
  // TODO(pre-ship): Remove _isDeleting, _confirmDelete, and the delete button below.
  bool _isDeleting = false;

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
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ctx.l10n.delete),
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
      Navigator.pop(context, 'deleted');
    } catch (_) {
      if (!mounted) return;
      setState(() => _isDeleting = false);
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
                      context.l10n.employeeColor2,
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
                        border: Border.all(
                          color: theme.colorScheme.outlineVariant,
                        ),
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
              label: Text(context.l10n.deleteEmployee),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
                foregroundColor: theme.colorScheme.error,
                side: BorderSide(color: theme.colorScheme.error),
              ),
            ),
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

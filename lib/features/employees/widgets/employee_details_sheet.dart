import 'package:flutter/material.dart';

import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/core/utils/l10n_extensions.dart';
import 'package:scheduling/features/employees/models/employee_record.dart';
import 'package:scheduling/shared/widgets/sheet_widgets.dart';
import 'package:scheduling/shared/widgets/status_chip.dart';

class EmployeeDetailsSheet extends StatefulWidget {
  const EmployeeDetailsSheet({super.key, required this.employee});
  final EmployeeRecord employee;

  @override
  State<EmployeeDetailsSheet> createState() => _EmployeeDetailsSheetState();
}

class _EmployeeDetailsSheetState extends State<EmployeeDetailsSheet> {
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

            //Deleting Account (Apple maybe needs this)
            // OutlinedButton.icon(
            //   onPressed: _isLoading ? null : _confirmDelete,
            //   icon: const Icon(Icons.delete_outline, size: 18, color: AppColors.error),
            //   label: Text(context.l10n.delete, style: const TextStyle(color: AppColors.error)),
            //   style: OutlinedButton.styleFrom(
            //     minimumSize: const Size(double.infinity, 48),
            //     side: const BorderSide(color: AppColors.error),
            //     shape: RoundedRectangleBorder(
            //       borderRadius: BorderRadius.circular(AppRadius.r8),
            //     ),
            //   ),
            // ),
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

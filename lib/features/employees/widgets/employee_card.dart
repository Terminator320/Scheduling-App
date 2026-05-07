import 'package:flutter/material.dart';

import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/core/utils/l10n_extensions.dart';
import 'package:scheduling/features/employees/models/employee_record.dart';
import 'package:scheduling/shared/widgets/app_avatar.dart';
import 'package:scheduling/shared/widgets/status_chip.dart';

/// List-row card for a single employee with tap / edit / delete affordances.
class EmployeeCard extends StatelessWidget {
  const EmployeeCard({
    super.key,
    required this.employee,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  final EmployeeRecord employee;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    Widget card = Material(
      color: theme.cardColor,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppAvatar(
                name: employee.name,
                color: employee.isDisabled ? AppColors.disabled : employee.color,
                size: AvatarSize.md,
              ),
              const SizedBox(width: 12),
              Expanded(child: _EmployeeSummary(employee: employee)),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined, size: 20),
                  ),
                  IconButton(
                    onPressed: onDelete,
                    icon: Icon(
                      Icons.delete_outline,
                      size: 20,
                      color: scheme.error,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (employee.isDisabled) {
      card = Opacity(opacity: 0.65, child: card);
    }

    return card;
  }
}

class _EmployeeSummary extends StatelessWidget {
  const _EmployeeSummary({required this.employee});

  final EmployeeRecord employee;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          employee.name.isEmpty
              ? context.l10n.employeeName
              : employee.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        if (employee.email.isNotEmpty)
          Text(
            employee.email,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium,
          ),
        if (employee.phone.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            employee.phone,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            StatusChip(
              status: employee.isActive
                  ? AppointmentStatus.active
                  : employee.isDisabled
                      ? AppointmentStatus.disabled
                      : AppointmentStatus.invited,
            ),
            if (employee.isAdmin)
              _StatusChip(
                label: context.l10n.admin,
                color: scheme.tertiary,
              ),
          ],
        ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withAlpha(28),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

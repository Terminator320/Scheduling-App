import 'package:flutter/material.dart';

import '../../models/employee_record.dart';
import '../../utils/app_text.dart';

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

    return Material(
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
            children: [
              _EmployeeAvatar(employee: employee),
              const SizedBox(width: 12),
              Expanded(child: _EmployeeSummary(employee: employee)),
              IconButton(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined, size: 20),
              ),
              IconButton(
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline, size: 20),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmployeeSummary extends StatelessWidget {
  const _EmployeeSummary({required this.employee});

  final EmployeeRecord employee;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final statusLabel = employee.isActive
        ? tr(context, 'Active')
        : employee.status.isEmpty
            ? tr(context, 'Invited')
            : employee.status;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          employee.name.isEmpty
              ? tr(context, 'Employee name')
              : employee.name,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        if (employee.email.isNotEmpty)
          Text(employee.email, style: theme.textTheme.bodyMedium),
        if (employee.phone.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(employee.phone, style: theme.textTheme.bodySmall),
        ],
        const SizedBox(height: 6),
        Row(
          children: [
            _StatusChip(
              label: statusLabel,
              color: employee.isActive ? Colors.green : scheme.primary,
            ),
            if (employee.isAdmin) ...[
              const SizedBox(width: 8),
              _StatusChip(
                label: tr(context, 'Admin'),
                color: scheme.tertiary,
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _EmployeeAvatar extends StatelessWidget {
  const _EmployeeAvatar({required this.employee});

  final EmployeeRecord employee;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: employee.color.withAlpha(40),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          employee.initials,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: employee.color,
              ),
        ),
      ),
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

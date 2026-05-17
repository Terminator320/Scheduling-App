import 'package:flutter/material.dart';

import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';
import 'package:scheduling/shared/widgets/app_avatar.dart';
import 'package:scheduling/shared/widgets/status_chip.dart';

class EmployeeCard extends StatelessWidget {
  const EmployeeCard({required this.employee, required this.onTap, super.key});

  final EmployeeRecord employee;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    Widget row = InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sp16,
          vertical: AppSpacing.sp12,
        ),
        child: Row(
          children: [
            AppAvatar(
              name: employee.name.isEmpty ? '?' : employee.name,
              color: employee.isDisabled
                  ? scheme.outlineVariant
                  : employee.color,
            ),
            const SizedBox(width: AppSpacing.sp12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    employee.name.isEmpty ? '—' : employee.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (employee.email.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      employee.email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sp8),
            StatusChip(
              status: employee.isActive
                  ? AppointmentStatus.active
                  : employee.isDisabled
                  ? AppointmentStatus.disabled
                  : AppointmentStatus.invited,
            ),
            const SizedBox(width: AppSpacing.sp8),
            Icon(Icons.chevron_right, size: 18, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );

    if (employee.isDisabled) {
      row = Opacity(opacity: 0.65, child: row);
    }

    return row;
  }
}

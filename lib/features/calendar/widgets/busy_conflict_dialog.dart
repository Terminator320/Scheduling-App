import 'package:flutter/material.dart';

import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/core/utils/date_utils_helper.dart';
import 'package:scheduling/core/utils/l10n_extensions.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';

/// Confirmation dialog shown when assigning employees who already have a
/// conflicting appointment in the chosen window. Returns `true` if the user
/// chooses to schedule anyway, `false` (or `null`) on cancel.
Future<bool> showBusyConflictDialog(
  BuildContext context, {
  required List<EmployeeRecord> busyEmployees,
  required DateTime start,
  required DateTime end,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogCtx) {
      final theme = Theme.of(dialogCtx);
      final scheme = theme.colorScheme;
      return Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.r16),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sp24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: scheme.tertiaryContainer,
                  borderRadius: BorderRadius.circular(AppRadius.r12),
                ),
                child: Icon(
                  Icons.warning_amber_rounded,
                  color: scheme.onTertiaryContainer,
                  size: 22,
                ),
              ),
              const SizedBox(height: AppSpacing.sp16),
              Text(
                context.l10n.scheduleConflict,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.sp4),
              Text(
                '${DateUtilsHelper.formatDate(start)} · '
                '${DateUtilsHelper.formatTime(start)} – '
                '${DateUtilsHelper.formatTime(end)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.sp16),
              Text(
                context.l10n.alreadyBookedThisSlot,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: AppSpacing.sp12),
              ...busyEmployees.map(
                (e) => _BusyEmployeeRow(employee: e),
              ),
              const Divider(height: AppSpacing.sp24),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Icon(
                      Icons.info_outline_rounded,
                      size: 14,
                      color: scheme.onTertiaryContainer,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sp8),
                  Expanded(
                    child: Text(
                      context.l10n.doubleBookingWarning,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onTertiaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sp24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 44),
                      ),
                      onPressed: () => Navigator.pop(dialogCtx, false),
                      child: Text(context.l10n.cancel),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sp12),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(double.infinity, 44),
                        backgroundColor: scheme.tertiary,
                        foregroundColor: scheme.onTertiary,
                      ),
                      onPressed: () => Navigator.pop(dialogCtx, true),
                      child: Text(context.l10n.scheduleAnyway),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
  return result ?? false;
}

class _BusyEmployeeRow extends StatelessWidget {
  const _BusyEmployeeRow({required this.employee});

  final EmployeeRecord employee;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sp8),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: employee.color,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                employee.initials,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sp12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  employee.name,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (employee.email.isNotEmpty)
                  Text(
                    employee.email,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

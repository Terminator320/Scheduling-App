import 'package:flutter/material.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/core/utils/date_utils_helper.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/primitives/app_avatar.dart';

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
                context.l10n.calendar_scheduleConflict,
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
                context.l10n.calendar_alreadyBookedThisSlot,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: AppSpacing.sp12),
              ...busyEmployees.map((e) => _BusyEmployeeRow(employee: e)),
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
                      context.l10n.calendar_doubleBookingWarning,
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
                      child: Text(context.l10n.common_cancel),
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
                      child: Text(context.l10n.calendar_scheduleAnyway),
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
          AppAvatar(
            name: employee.name,
            color: employee.color,
            size: AvatarSize.sm,
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

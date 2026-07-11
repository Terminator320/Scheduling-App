import 'package:flutter/material.dart';

import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/core/utils/date_utils_helper.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/dashboard/domain/assignee_names.dart';
import 'package:scheduling/features/dashboard/domain/dashboard_stats.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/feedback/status_chip.dart';
import 'package:scheduling/shared/widgets/primitives/section_label.dart';

/// Today's upcoming visits as a timeline with a time rail.
class UpcomingTodaySection extends StatelessWidget {
  const UpcomingTodaySection({
    required this.ops,
    required this.colorMap,
    required this.nameMap,
    super.key,
  });

  final TodayOps ops;
  final Map<String, Color> colorMap;
  final Map<String, String> nameMap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel(l10n.dashboard_upcomingToday),
        const SizedBox(height: AppSpacing.sp8),
        if (ops.upcoming.isEmpty)
          Text(
            l10n.dashboard_noVisitsToday,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        else
          Container(
            decoration: appCardDecoration(
              theme,
              color: theme.colorScheme.surface,
            ),
            padding: const EdgeInsets.all(AppSpacing.sp16),
            child: Column(
              children: [
                for (var i = 0; i < ops.upcoming.length; i++)
                  _TimelineRow(
                    appointment: ops.upcoming[i],
                    isLast: i == ops.upcoming.length - 1,
                    colorMap: colorMap,
                    nameMap: nameMap,
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.appointment,
    required this.isLast,
    required this.colorMap,
    required this.nameMap,
  });

  final AppointmentRecord appointment;
  final bool isLast;
  final Map<String, Color> colorMap;
  final Map<String, String> nameMap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dotColor = appointment.employeeIds.isNotEmpty
        ? colorMap[appointment.employeeIds.first] ?? scheme.outlineVariant
        : scheme.outlineVariant;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 64,
            child: Text(
              DateUtilsHelper.formatTime(appointment.startTime),
              textAlign: TextAlign.right,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: scheme.onSurface,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sp8),
          Column(
            children: [
              Container(
                width: 10,
                height: 10,
                margin: const EdgeInsets.only(top: 3),
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(width: 2, color: scheme.outlineVariant),
                ),
            ],
          ),
          const SizedBox(width: AppSpacing.sp12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : AppSpacing.sp12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          appointment.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sp8),
                      StatusChip(
                        status: AppointmentStatus.fromRaw(
                          appointment.displayStatus,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    resolveAssigneeNames(appointment, nameMap) ??
                        context.l10n.dashboard_unassigned,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

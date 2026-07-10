import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/core/utils/date_utils_helper.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/dashboard/domain/dashboard_stats.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/feedback/status_chip.dart';
import 'package:scheduling/shared/widgets/primitives/section_label.dart';

/// Pending-soon and never-closed visits as compact severity-striped rows.
class AttentionFlagsSection extends StatelessWidget {
  const AttentionFlagsSection({
    required this.flags,
    required this.nameMap,
    super.key,
  });

  final AttentionFlags flags;
  final Map<String, String> nameMap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColors = theme.statusColors;
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel(l10n.dashboard_attentionFlags),
        const SizedBox(height: AppSpacing.sp8),
        if (flags.isAllClear)
          Row(
            children: [
              Icon(
                Icons.check_circle_rounded,
                size: 18,
                color: statusColors.success,
              ),
              const SizedBox(width: AppSpacing.sp8),
              Expanded(
                child: Text(
                  l10n.dashboard_allClear,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          )
        else ...[
          if (flags.pendingSoon.isNotEmpty)
            _FlagGroup(
              title: l10n.dashboard_pendingSoonHeader(flags.pendingSoon.length),
              appointments: flags.pendingSoon,
              stripeColor: statusColors.warning,
              nameMap: nameMap,
            ),
          if (flags.pendingSoon.isNotEmpty && flags.overdueOpen.isNotEmpty)
            const SizedBox(height: AppSpacing.sp16),
          if (flags.overdueOpen.isNotEmpty)
            _FlagGroup(
              title: l10n.dashboard_overdueOpenHeader(flags.overdueOpen.length),
              appointments: flags.overdueOpen,
              stripeColor: theme.colorScheme.error,
              nameMap: nameMap,
            ),
        ],
      ],
    );
  }
}

class _FlagGroup extends StatelessWidget {
  const _FlagGroup({
    required this.title,
    required this.appointments,
    required this.stripeColor,
    required this.nameMap,
  });

  final String title;
  final List<AppointmentRecord> appointments;
  final Color stripeColor;
  final Map<String, String> nameMap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.sp8),
        for (final appointment in appointments)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sp8),
            child: _AlertRow(
              appointment: appointment,
              stripeColor: stripeColor,
              nameMap: nameMap,
            ),
          ),
      ],
    );
  }
}

class _AlertRow extends StatelessWidget {
  const _AlertRow({
    required this.appointment,
    required this.stripeColor,
    required this.nameMap,
  });

  final AppointmentRecord appointment;
  final Color stripeColor;
  final Map<String, String> nameMap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // Flagged visits can be days away or days old — the date matters.
    final dateLabel = DateFormat.MMMEd(
      Localizations.localeOf(context).toString(),
    ).format(appointment.startTime);
    final timeLabel = DateUtilsHelper.formatTime(appointment.startTime);
    final who =
        _assigneeNames(appointment) ?? context.l10n.dashboard_unassigned;
    return Container(
      decoration: appCardDecoration(theme, color: scheme.surface),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 3, color: stripeColor),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.sp12),
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
                    const SizedBox(height: AppSpacing.sp4),
                    Text(
                      '$dateLabel · $timeLabel · $who',
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
      ),
    );
  }

  String? _assigneeNames(AppointmentRecord appointment) {
    final names = [
      for (final id in appointment.employeeIds)
        if (nameMap[id] != null) nameMap[id]!,
    ];
    if (names.isNotEmpty) return names.join(', ');
    if (appointment.employeeNames.isNotEmpty) {
      return appointment.employeeNames.join(', ');
    }
    return null;
  }
}

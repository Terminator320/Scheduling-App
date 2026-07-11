import 'package:flutter/material.dart';

import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/core/utils/date_utils_helper.dart';
import 'package:scheduling/features/dashboard/domain/dashboard_aggregator.dart';
import 'package:scheduling/features/dashboard/domain/dashboard_stats.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/feedback/status_chip.dart';

/// Hero summary band: today's total, the date, a proportional status bar
/// with legend, and the unassigned warning pill.
class DashboardHero extends StatelessWidget {
  const DashboardHero({required this.ops, required this.now, super.key});

  final TodayOps ops;
  final DateTime now;

  // On-primary data hues, deliberately theme-invariant: the hero ground is
  // scheme.primary in BOTH themes (appBarTheme), and ColorScheme has no
  // "data color on primary" role. The legend text carries the meaning.
  static const Color _inProgressSegment = Color(0xFF00A6F4);
  static const Color _overdueSegment = Color(0xFFF54A00);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final statusColors = theme.statusColors;
    final l10n = context.l10n;
    final segments = [
      (AppointmentStatus.inProgress, _inProgressSegment),
      (AppointmentStatus.overdue, _overdueSegment),
      (AppointmentStatus.pending, statusColors.warning),
      (AppointmentStatus.done, statusColors.success),
      (AppointmentStatus.cancelled, scheme.error),
    ];
    // Resolve each segment's count once (the bar and legend both need it), and
    // keep only the non-zero ones so the two views can't drift out of sync.
    final visible = [
      for (final (status, color) in segments)
        if ((ops.statusCounts[DashboardAggregator.statusCountKey(status)] ??
                0) >
            0)
          (
            status,
            color,
            ops.statusCounts[DashboardAggregator.statusCountKey(status)]!,
          ),
    ];
    final total = ops.total;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sp16,
        AppSpacing.sp4,
        AppSpacing.sp16,
        AppSpacing.sp16,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            scheme.primary,
            Color.alphaBlend(
              Colors.black.withValues(alpha: 0.2),
              scheme.primary,
            ),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(
              text: '$total ',
              style: theme.textTheme.headlineLarge?.copyWith(
                color: scheme.onPrimary,
                fontWeight: FontWeight.w800,
              ),
              children: [
                TextSpan(
                  text: l10n.dashboard_visitsToday(total),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onPrimary.withValues(alpha: 0.85),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Text(
            DateUtilsHelper.formatDayHeader(now),
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onPrimary.withValues(alpha: 0.85),
            ),
          ),
          const SizedBox(height: AppSpacing.sp12),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.rFull),
            child: SizedBox(
              height: 8,
              width: double.infinity,
              child: total == 0
                  ? ColoredBox(
                      color: scheme.onPrimary.withValues(alpha: 0.18),
                    )
                  : Row(
                      children: [
                        for (final (_, color, count) in visible)
                          Expanded(
                            flex: count,
                            child: ColoredBox(color: color),
                          ),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: AppSpacing.sp8),
          Wrap(
            spacing: AppSpacing.sp12,
            runSpacing: AppSpacing.sp4,
            children: [
              // Only non-zero statuses appear, mirroring the bar above (same
              // `visible` list) — an absent status adds no legend clutter.
              for (final (status, color, count) in visible)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sp4),
                    Text(
                      '$count ${statusLabel(l10n, status)}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onPrimary,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          if (ops.unassignedCount > 0) ...[
            const SizedBox(height: AppSpacing.sp12),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sp12,
                vertical: AppSpacing.sp4,
              ),
              decoration: BoxDecoration(
                color: scheme.onPrimary.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(AppRadius.rFull),
                border: Border.all(
                  color: scheme.onPrimary.withValues(alpha: 0.25),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.person_off_rounded,
                    size: 14,
                    color: statusColors.warning,
                  ),
                  const SizedBox(width: AppSpacing.sp8),
                  Flexible(
                    child: Text(
                      l10n.dashboard_unassignedCount(ops.unassignedCount),
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: scheme.onPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/errors/error_cause.dart';
import 'package:scheduling/core/layout/breakpoints.dart';
import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/core/notices/notice_service.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/features/dashboard/application/dashboard_providers.dart';
import 'package:scheduling/features/dashboard/domain/dashboard_stats.dart';
import 'package:scheduling/features/dashboard/widgets/sections/attention_flags_section.dart';
import 'package:scheduling/features/dashboard/widgets/sections/business_trends_section.dart';
import 'package:scheduling/features/dashboard/widgets/sections/dashboard_hero.dart';
import 'package:scheduling/features/dashboard/widgets/sections/employee_workload_section.dart';
import 'package:scheduling/features/dashboard/widgets/sections/upcoming_today_section.dart';
import 'package:scheduling/features/employees/application/employees_providers.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/routes/hub_shell.dart';
import 'package:scheduling/shared/widgets/app_bars/app_top_bar.dart';
import 'package:scheduling/shared/widgets/feedback/skeleton_loader.dart';

/// Admin-only at-a-glance view of the business. Reached only from admin
/// surfaces (settings drawer / Settings screen) as a plain pushed route.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(dashboardStatsProvider);
    ref.listen<AsyncValue<DashboardStats>>(dashboardStatsProvider, (
      previous,
      next,
    ) {
      if (!next.hasError || (previous?.hasError ?? false)) return;
      ref
          .read(loggerProvider)
          .warn('DASH-LOAD dashboard failed', next.error, next.stackTrace);
      ref
          .read(noticeServiceProvider)
          .error(
            composeErrorNotice(
              context,
              intro: context.l10n.error_introLoadDashboard,
              tag: 'DASH-LOAD',
              error: next.error!,
            ),
          );
    });

    return Scaffold(
      appBar: AppTopBar(
        title: context.l10n.dashboard_title,
        compact: context.isLandscape,
        onBack: () {
          // Return to the calendar tab specifically (not whatever tab was
          // showing when the dashboard was opened), then pop this route.
          HubShell.liveState?.showCalendar();
          Navigator.pop(context);
        },
      ),
      body: switch (stats) {
        AsyncData(:final value) => _StatsList(stats: value),
        AsyncError() => const _ErrorBody(),
        _ => const _LoadingList(),
      },
    );
  }
}

class _StatsList extends ConsumerWidget {
  const _StatsList({required this.stats});

  final DashboardStats stats;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorMap = ref.watch(employeeColorMapProvider);
    final nameMap = ref.watch(employeeNameMapProvider);
    final now = ref.watch(dashboardClockProvider)();
    // Zero list padding so the hero bleeds edge-to-edge; the sections carry
    // their own sp16 inset.
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        DashboardHero(ops: stats.todayOps, now: now),
        Padding(
          padding: const EdgeInsets.all(AppSpacing.sp16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              UpcomingTodaySection(
                ops: stats.todayOps,
                colorMap: colorMap,
                nameMap: nameMap,
              ),
              const SizedBox(height: AppSpacing.sp24),
              EmployeeWorkloadSection(workload: stats.workload),
              const SizedBox(height: AppSpacing.sp24),
              BusinessTrendsSection(
                buckets: stats.weekBuckets,
                busiestWeekday: stats.busiestWeekday,
              ),
              const SizedBox(height: AppSpacing.sp24),
              AttentionFlagsSection(
                flags: stats.flags,
                colorMap: colorMap,
                nameMap: nameMap,
              ),
              const SizedBox(height: AppSpacing.sp16),
            ],
          ),
        ),
      ],
    );
  }
}

class _LoadingList extends StatelessWidget {
  const _LoadingList();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.sp16),
      children: [for (var i = 0; i < 8; i++) const SkeletonAppointmentRow()],
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sp24),
        child: Text(
          context.l10n.error_introLoadDashboard,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

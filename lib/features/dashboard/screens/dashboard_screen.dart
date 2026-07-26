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
import 'package:scheduling/features/settings/widgets/views/settings_drawer.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/routes/hub_shell.dart';
import 'package:scheduling/shared/widgets/app_bars/app_top_bar.dart';
import 'package:scheduling/shared/widgets/feedback/centered_error_text.dart';
import 'package:scheduling/shared/widgets/feedback/skeleton_loader.dart';

/// Business overview for admins only, reached from the settings drawer.
class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({
    required this.isAdmin,
    required this.employeeId,
    super.key,
    this.userName,
    this.email,
  });

  final bool isAdmin;
  final String employeeId;
  final String? userName;
  final String? email;

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  // Key for the end drawer, matching the pattern used by the hub screens.
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
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
      key: _scaffoldKey,
      appBar: AppTopBar(
        title: context.l10n.dashboard_title,
        compact: context.isLandscape,
        onBack: () {
          // Return to calendar tab, then pop.
          HubShell.liveState?.showCalendar();
          Navigator.pop(context);
        },
        actions: [
          // Split layout shows a nav rail instead, so there's no drawer to open here.
          if (!context.isSplitLayout)
            IconButton(
              icon: Icon(Icons.menu, color: scheme.onPrimary),
              tooltip: context.l10n.calendar_openMenuTooltip,
              onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
            ),
        ],
      ),
      endDrawer: SettingsDrawer.endDrawerFor(
        context,
        isAdmin: widget.isAdmin,
        employeeId: widget.employeeId,
        userName: widget.userName,
        email: widget.email,
      ),
      body: switch (stats) {
        AsyncData(:final value) => _StatsList(
          stats: value,
          isAdmin: widget.isAdmin,
        ),
        AsyncError() => CenteredErrorText(
          message: context.l10n.error_introLoadDashboard,
        ),
        _ => const _LoadingList(),
      },
    );
  }
}

class _StatsList extends ConsumerWidget {
  const _StatsList({required this.stats, required this.isAdmin});

  final DashboardStats stats;

  /// Gates the admin-only actions on the appointment sheets these cards open.
  final bool isAdmin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorMap = ref.watch(employeeColorMapProvider);
    final nameMap = ref.watch(employeeNameMapProvider);
    final now = ref.watch(dashboardClockProvider)();
    // List padding is zero so the hero bleeds edge-to-edge — the sections
    // below add their own sp16 inset.
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
                isAdmin: isAdmin,
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
                isAdmin: isAdmin,
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

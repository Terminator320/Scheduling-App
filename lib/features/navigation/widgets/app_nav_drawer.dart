import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scheduling/core/navigation/app_destination.dart';
import 'package:scheduling/core/navigation/hub_shell_scope.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/core/utils/current_day_provider.dart';
import 'package:scheduling/core/utils/date_utils_helper.dart';
import 'package:scheduling/features/auth/application/account_status_provider.dart';
import 'package:scheduling/features/calendar/application/appointments_providers.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/navigation/domain/drawer_catalog.dart';
import 'package:scheduling/features/presence/application/live_map_providers.dart';
import 'package:scheduling/features/presence/domain/live_map_aggregator.dart';
import 'package:scheduling/features/settings/application/app_info_provider.dart';
import 'package:scheduling/features/settings/domain/role_label.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/branding/brand_logo.dart';
import 'package:scheduling/shared/widgets/primitives/app_avatar.dart';

const double _kDrawerWidth = 284;

/// The right-anchored navigation drawer — the app's only nav surface at
/// every screen size. Rows are grouped by when you would reach for them.
///
/// A closed drawer's child is never built (`_DrawerControllerState`
/// short-circuits to `SizedBox.shrink()` while dismissed), so the count
/// providers watched below subscribe only while it is open. Do not add an
/// "is open" flag to work around a cost that does not exist.
class AppNavDrawer extends ConsumerWidget {
  const AppNavDrawer({
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
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = context.l10n;
    final groups = drawerGroups(isAdmin: isAdmin);

    return Drawer(
      width: _kDrawerWidth,
      backgroundColor: scheme.surface,
      shape: const RoundedRectangleBorder(),
      child: DecoratedBox(
        decoration: BoxDecoration(boxShadow: theme.cardStyle.drawerShadow),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(isAdmin: isAdmin, userName: userName, email: email),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 14, 12, 20),
                children: [
                  for (final (index, group) in groups.indexed) ...[
                    if (index > 0) const SizedBox(height: AppSpacing.sp16),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(13, 0, 13, 7),
                      child: Text(
                        group.title(l10n),
                        style: theme.monoType.groupLabel.copyWith(
                          color: theme.palette.textMuted,
                        ),
                      ),
                    ),
                    for (final destination in group.rows)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: _NavRow(
                          destination: destination,
                          isAdmin: isAdmin,
                          employeeId: employeeId,
                          userName: userName,
                          email: email,
                        ),
                      ),
                  ],
                ],
              ),
            ),
            const _VersionFooter(),
          ],
        ),
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({required this.isAdmin, this.userName, this.email});

  final bool isAdmin;
  final String? userName;
  final String? email;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // Both derive from the app-wide currentUserDocProvider, so no new stream.
    final docName = ref.watch(currentUserNameProvider);
    final displayName = (userName?.isNotEmpty ?? false)
        ? userName!
        : (docName.isNotEmpty
              ? docName
              : (FirebaseAuth.instance.currentUser?.displayName ?? ''));

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: scheme.outline)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
          child: Row(
            children: [
              AppAvatar(name: displayName, size: AvatarSize.lg),
              const SizedBox(width: AppSpacing.sp12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      displayName.isNotEmpty ? displayName : ' ',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: kFontSans,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface,
                      ),
                    ),
                    Text(
                      // brandName is a proper noun — never localized.
                      '${roleLabel(context.l10n, isAdmin: isAdmin)} · '
                      '$brandName',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: kFontSans,
                        fontSize: 12,
                        color: theme.palette.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavRow extends ConsumerWidget {
  const _NavRow({
    required this.destination,
    required this.isAdmin,
    required this.employeeId,
    this.userName,
    this.email,
  });

  final AppDestination destination;
  final bool isAdmin;
  final String employeeId;
  final String? userName;
  final String? email;

  bool _isActive(BuildContext context) => switch (destination) {
    final HubTab tab => HubShellScope.readCurrentOf(context) == tab,
    final PushedDestination pushed =>
      ModalRoute.settingsOf(context)?.name ==
          destinationRoute(
            pushed,
            isAdmin: isAdmin,
            employeeId: employeeId,
          ).route,
  };

  void _go(BuildContext context) {
    Scaffold.of(context).closeEndDrawer();
    // Calendar routes through goHome so it also collapses any pushed stack —
    // no screen is a dead end.
    if (destination == HubTab.calendar) {
      goHomeToCalendar(context);
      return;
    }
    navigateToDestination(
      context,
      destination,
      isAdmin: isAdmin,
      employeeId: employeeId,
      userName: userName ?? '',
      userEmail: email ?? '',
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isActive = _isActive(context);
    final count = _countFor(ref);

    return Material(
      color: isActive ? scheme.primaryContainer : Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadius.rRow),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _go(context),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: crewColorOf(
                      theme,
                      drawerDotColor(destination).toARGB32(),
                    ),
                    borderRadius: BorderRadius.circular(AppRadius.rThumb),
                  ),
                ),
                const SizedBox(width: AppSpacing.sp12),
                Expanded(
                  child: Text(
                    drawerRowLabel(context.l10n, destination),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: kFontSans,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: isActive
                          ? scheme.onPrimaryContainer
                          : scheme.onSurface,
                    ),
                  ),
                ),
                // An absent count renders nothing — the empty-omitted rule.
                if (count != null) ...[
                  const SizedBox(width: AppSpacing.sp8),
                  Text('$count', style: theme.monoType.data),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Only two rows carry a count today. Time off joins in P6.
  int? _countFor(WidgetRef ref) => switch (destination) {
    HubTab.calendar => _todayJobCount(ref),
    HubTab.liveMap => _onTheClockCount(ref),
    _ => null,
  };

  int? _todayJobCount(WidgetRef ref) {
    // currentDayProvider so the bucket re-derives at midnight rather than
    // waiting for a write to re-emit the stream.
    final today = ref.watch(currentDayProvider).dateOnly;
    final range = AppointmentDateRange(
      start: today,
      end: today.add(const Duration(days: 1)),
    );
    final jobs = isAdmin
        ? ref.watch(appointmentsInRangeProvider(range))
        : ref.watch(
            myAppointmentsProvider((employeeId: employeeId, range: range)),
          );
    return jobs.value?.length;
  }

  int? _onTheClockCount(WidgetRef ref) {
    final points = ref.watch(liveMapPointsProvider).value;
    if (points == null) return null;
    ref.watch(liveMapTickProvider); // recompute every 30 s
    final now = ref.watch(liveMapClockProvider)();
    return points
        .where((p) => !LiveMapAggregator.isStale(p.updatedAt, now))
        .length;
  }
}

class _VersionFooter extends ConsumerWidget {
  const _VersionFooter();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final info = ref.watch(appInfoProvider).value;
    if (info == null) return const SizedBox.shrink();
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(25, 0, 25, 12),
        child: Text(
          'v${info.version} (${info.buildNumber})',
          style: theme.monoType.micro.copyWith(color: theme.palette.textFaint),
        ),
      ),
    );
  }
}

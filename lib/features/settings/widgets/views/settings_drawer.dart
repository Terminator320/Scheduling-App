import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scheduling/core/navigation/app_destination.dart';
import 'package:scheduling/core/navigation/hub_shell_scope.dart';
import 'package:scheduling/core/layout/breakpoints.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/features/auth/application/account_status_provider.dart';
import 'package:scheduling/features/settings/domain/role_label.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/routes/app_routes.dart';
import 'package:scheduling/shared/widgets/primitives/app_avatar.dart';

class SettingsDrawer extends ConsumerStatefulWidget {
  const SettingsDrawer({
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

  /// Helper for [Scaffold.endDrawer] — returns null when the nav rail is
  /// showing, or a [SettingsDrawer] otherwise.
  static Widget? endDrawerFor(
    BuildContext context, {
    required bool isAdmin,
    required String employeeId,
    String? userName,
    String? email,
  }) {
    if (context.isSplitLayout) return null;
    return SettingsDrawer(
      isAdmin: isAdmin,
      employeeId: employeeId,
      userName: userName,
      email: email,
    );
  }

  @override
  ConsumerState<SettingsDrawer> createState() => _SettingsDrawerState();
}

class _SettingsDrawerState extends ConsumerState<SettingsDrawer> {
  String _resolveName() {
    final docName = ref.watch(currentUserNameProvider);
    if (docName.isNotEmpty) return docName;
    return FirebaseAuth.instance.currentUser?.displayName ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final displayName = (widget.userName?.isNotEmpty ?? false)
        ? widget.userName!
        : _resolveName();
    final displayEmail = (widget.email?.isNotEmpty ?? false)
        ? widget.email!
        : (FirebaseAuth.instance.currentUser?.email ?? '');

    final scheme = Theme.of(context).colorScheme;

    return Drawer(
      backgroundColor: scheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(
          left: Radius.circular(AppRadius.r24),
        ),
      ),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          _buildHeader(context, displayName, displayEmail),
          ..._buildNavItems(context, displayName, displayEmail),
        ],
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    String displayName,
    String displayEmail,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final statusBarHeight = MediaQuery.of(context).padding.top;
    final role = roleLabel(context.l10n, isAdmin: widget.isAdmin);

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        AppSpacing.sp24,
        statusBarHeight + AppSpacing.sp24,
        AppSpacing.sp24,
        AppSpacing.sp24,
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
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: scheme.onPrimary.withValues(alpha: 0.25),
              shape: BoxShape.circle,
            ),
            child: AppAvatar(
              name: displayName,
              color: scheme.onPrimaryContainer,
              size: AvatarSize.lg,
            ),
          ),
          const SizedBox(height: AppSpacing.sp12),
          Text(
            displayName.isNotEmpty ? displayName : ' ',
            style: TextStyle(
              color: scheme.onPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: AppSpacing.sp8),
          Wrap(
            spacing: AppSpacing.sp8,
            runSpacing: AppSpacing.sp8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sp8,
                  vertical: AppSpacing.sp4,
                ),
                decoration: BoxDecoration(
                  color: scheme.onPrimary.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(AppRadius.rFull),
                ),
                child: Text(
                  role,
                  style: TextStyle(
                    color: scheme.onPrimary,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              if (displayEmail.isNotEmpty)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 220),
                  child: Text(
                    displayEmail,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: scheme.onPrimary.withValues(alpha: 0.75),
                      fontSize: 11,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _buildNavItems(
    BuildContext context,
    String displayName,
    String displayEmail,
  ) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final statusColors = theme.statusColors;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    void go(AppDestination destination) =>
        _goTo(context, destination, displayName, displayEmail);

    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.sp12,
          AppSpacing.sp8,
          AppSpacing.sp12,
          0,
        ),
        child: _NavItem(
          icon: Icons.calendar_today_rounded,
          iconColor: scheme.primary,
          label: context.l10n.common_calendar,
          onTap: () => go(HubTab.calendar),
        ),
      ),
      if (widget.isAdmin) ...[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sp12),
          child: _NavItem(
            icon: Icons.people_rounded,
            iconColor: statusColors.success,
            label: context.l10n.common_clients,
            onTap: () => go(HubTab.clients),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sp12),
          child: _NavItem(
            icon: Icons.badge_rounded,
            iconColor: statusColors.accent,
            label: context.l10n.common_employees,
            onTap: () => go(HubTab.employees),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sp12),
          child: _NavItem(
            icon: Icons.history_rounded,
            iconColor: statusColors.warning,
            label: context.l10n.common_history,
            onTap: () => go(PushedDestination.history),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sp12),
          child: _NavItem(
            icon: Icons.map_rounded,
            iconColor: scheme.primary,
            label: context.l10n.common_liveMap,
            onTap: () => go(HubTab.liveMap),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sp12),
          child: _NavItem(
            icon: Icons.insights_rounded,
            iconColor: scheme.secondary,
            label: context.l10n.dashboard_title,
            onTap: () {
              Navigator.pop(context);
              Navigator.pushNamed(
                context,
                AppRoutes.dashboard,
                arguments: DashboardArgs(
                  isAdmin: widget.isAdmin,
                  employeeId: widget.employeeId,
                  userName: widget.userName,
                  email: widget.email,
                ),
              );
            },
          ),
        ),
      ],
      const SizedBox(height: AppSpacing.sp8),
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: AppSpacing.sp12),
        child: Divider(height: 1),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.sp12,
          AppSpacing.sp4,
          AppSpacing.sp12,
          0,
        ),
        child: _NavItem(
          icon: Icons.settings_rounded,
          iconColor: scheme.onSurfaceVariant,
          label: context.l10n.common_settings,
          onTap: () => go(PushedDestination.settings),
        ),
      ),
      SizedBox(height: bottomPadding + 4),
    ];
  }

  void _goTo(
    BuildContext context,
    AppDestination destination,
    String displayName,
    String displayEmail,
  ) {
    Navigator.pop(context);
    final target = destinationRoute(
      destination,
      isAdmin: widget.isAdmin,
      employeeId: widget.employeeId,
      userName: displayName,
      userEmail: displayEmail,
    );
    // The calendar is the root screen - replace it instead of stacking.
    if (destination == HubTab.calendar) {
      Navigator.pushReplacementNamed(
        context,
        target.route,
        arguments: target.arguments,
      );
    } else {
      Navigator.pushNamed(context, target.route, arguments: target.arguments);
    }
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.r12),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sp8,
          vertical: AppSpacing.sp8,
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: iconColor.withValues(
                  alpha: theme.cardStyle.iconChipAlpha,
                ),
                borderRadius: BorderRadius.circular(AppRadius.r8),
              ),
              child: Icon(icon, size: 19, color: iconColor),
            ),
            const SizedBox(width: AppSpacing.sp16),
            Expanded(
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface,
                  fontSize: 15,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

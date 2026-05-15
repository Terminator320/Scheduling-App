import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/core/theme/theme_notifier.dart';
import 'package:scheduling/core/utils/l10n_extensions.dart';
import 'package:scheduling/features/employees/application/employees_providers.dart';
import 'package:scheduling/routes/app_routes.dart';
import 'package:scheduling/shared/widgets/app_avatar.dart';

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

  @override
  ConsumerState<SettingsDrawer> createState() => _SettingsDrawerState();
}

class _SettingsDrawerState extends ConsumerState<SettingsDrawer> {
  String _displayName = '';
  String _displayEmail = '';

  @override
  void initState() {
    super.initState();
    _resolveUser();
  }

  Future<void> _resolveUser() async {
    // Short-circuit when both values are already injected via props.
    if (widget.userName != null && widget.email != null) {
      if (mounted) {
        setState(() {
          _displayName = widget.userName!;
          _displayEmail = widget.email!;
        });
      }
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Email is always available from Auth
    final email = widget.email ?? user.email ?? '';

    // Name: prefer the passed-in value, then Auth displayName, then Firestore
    var name = widget.userName ?? user.displayName ?? '';
    if (name.isEmpty) {
      final doc = await ref
          .read(employeesRepositoryProvider)
          .findUserByUid(user.uid);
      if (!mounted) return;
      name = (doc?.data['name'] ?? '').toString();
    }

    if (!mounted) return;
    setState(() {
      _displayName = name;
      _displayEmail = email;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Drawer(
      backgroundColor: scheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(left: Radius.circular(24)),
      ),
      child: Column(
        children: [
          _buildHeader(context),
          Expanded(child: _buildNav(context)),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final statusBarHeight = MediaQuery.of(context).padding.top;
    final roleLabel = widget.isAdmin
        ? context.l10n.admin
        : context.l10n.employeeRoleValue;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(20, statusBarHeight + 24, 20, 22),
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
          // Avatar with translucent ring
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: scheme.onPrimary.withValues(alpha: 0.25),
              shape: BoxShape.circle,
            ),
            child: AppAvatar(
              name: _displayName,
              color: scheme.onPrimaryContainer,
              size: AvatarSize.lg,
            ),
          ),
          const SizedBox(height: 12),
          // Name
          Text(
            _displayName.isNotEmpty ? _displayName : ' ',
            style: TextStyle(
              color: scheme.onPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 7),
          // Role badge + email
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: scheme.onPrimary.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(AppRadius.rFull),
                ),
                child: Text(
                  roleLabel,
                  style: TextStyle(
                    color: scheme.onPrimary,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              if (_displayEmail.isNotEmpty) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    _displayEmail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: scheme.onPrimary.withValues(alpha: 0.75),
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNav(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final statusColors = theme.statusColors;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        children: [
          // ── Main navigation ─────────────────────────────────────────
          _NavItem(
            icon: Icons.calendar_today_rounded,
            iconColor: scheme.primary,
            label: context.l10n.calendar,
            onTap: () => _goToCalendar(context),
          ),
          if (widget.isAdmin) ...[
            _NavItem(
              icon: Icons.people_rounded,
              iconColor: statusColors.success,
              label: context.l10n.clients,
              onTap: () => _goToClients(context),
            ),
            _NavItem(
              icon: Icons.badge_rounded,
              iconColor: statusColors.accent,
              label: context.l10n.employees,
              onTap: () => _goToEmployees(context),
            ),
            _NavItem(
              icon: Icons.history_rounded,
              iconColor: statusColors.warning,
              label: context.l10n.history,
              onTap: () => _goToHistory(context),
            ),
          ],
          const Spacer(),

          // ── Settings pinned at bottom ───────────────────────────────
          const Divider(height: 1),
          const SizedBox(height: 4),
          _NavItem(
            icon: Icons.settings_rounded,
            iconColor: scheme.onSurfaceVariant,
            label: context.l10n.settings,
            onTap: () => _goToSettings(context),
          ),
          SizedBox(height: bottomPadding + 4),
        ],
      ),
    );
  }

  void _goToCalendar(BuildContext context) {
    Navigator.pop(context);
    Navigator.pushReplacementNamed(
      context,
      AppRoutes.mainCalendar,
      arguments: MainCalendarArgs(
        isAdmin: widget.isAdmin,
        employeeId: widget.employeeId,
      ),
    );
  }

  void _goToClients(BuildContext context) {
    Navigator.pop(context);
    Navigator.pushNamed(
      context,
      AppRoutes.clients,
      arguments: ClientsListArgs(
        mode: 'Clients',
        isAdmin: widget.isAdmin,
        employeeId: widget.employeeId,
      ),
    );
  }

  void _goToEmployees(BuildContext context) {
    Navigator.pop(context);
    Navigator.pushNamed(
      context,
      AppRoutes.employees,
      arguments: MainCalendarArgs(
        isAdmin: widget.isAdmin,
        employeeId: widget.employeeId,
      ),
    );
  }

  void _goToHistory(BuildContext context) {
    Navigator.pop(context);
    Navigator.pushNamed(
      context,
      AppRoutes.clients,
      arguments: ClientsListArgs(
        mode: 'Appointments',
        isAdmin: widget.isAdmin,
        employeeId: widget.employeeId,
      ),
    );
  }

  void _goToSettings(BuildContext context) {
    Navigator.pop(context);
    Navigator.pushNamed(
      context,
      AppRoutes.settings,
      arguments: SettingsArgs(
        name: _displayName,
        email: _displayEmail,
        role: widget.isAdmin ? 'admin' : 'employee',
      ),
    );
  }
}

// ── Nav Item ──────────────────────────────────────────────────────────────────

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
    final isDark = ThemeNotifier.of(context).isDark;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.r12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: isDark ? 0.15 : 0.10),
                borderRadius: BorderRadius.circular(AppRadius.r8),
              ),
              child: Icon(icon, size: 19, color: iconColor),
            ),
            const SizedBox(width: 14),
            Text(
              label,
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

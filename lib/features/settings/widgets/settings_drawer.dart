import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/core/utils/l10n_extensions.dart';
import 'package:scheduling/routes/app_routes.dart';
import 'package:scheduling/shared/widgets/app_avatar.dart';

class SettingsDrawer extends StatelessWidget {
  final bool isAdmin;
  final String employeeId;
  final String? userName;
  final String? email;

  const SettingsDrawer({
    super.key,
    required this.isAdmin,
    required this.employeeId,
    this.userName,
    this.email,
  });

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
          Expanded(child: _buildNavList(context, scheme)),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    final displayEmail =
        email ?? FirebaseAuth.instance.currentUser?.email ?? '';
    final statusBarHeight = MediaQuery.of(context).padding.top;
    final roleLabel =
        isAdmin ? context.l10n.admin : context.l10n.employeeRoleValue;

    return Container(
      padding: EdgeInsets.fromLTRB(20, statusBarHeight + 20, 20, 18),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColors.outline),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppAvatar(
            name: userName ?? '?',
            color: AppColors.primary,
            size: AvatarSize.lg,
          ),
          const SizedBox(height: 10),
          Text(
            userName ?? '…',
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.primaryTint,
                  borderRadius: BorderRadius.circular(AppRadius.rFull),
                ),
                child: Text(
                  roleLabel,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primaryDark,
                  ),
                ),
              ),
              if (displayEmail.isNotEmpty) ...[
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    displayEmail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.subtle,
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

  Widget _buildNavList(BuildContext context, ColorScheme scheme) {
    final textTheme = Theme.of(context).textTheme;

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        _DrawerItem(
          icon: Icons.calendar_today_outlined,
          label: context.l10n.calendar,
          textTheme: textTheme,
          scheme: scheme,
          onTap: () => _goToCalendar(context),
        ),
        if (isAdmin) ...[
          _DrawerItem(
            icon: Icons.people_outline,
            label: context.l10n.clients,
            textTheme: textTheme,
            scheme: scheme,
            onTap: () => _goToClients(context),
          ),
          _DrawerItem(
            icon: Icons.badge_outlined,
            label: context.l10n.employees,
            textTheme: textTheme,
            scheme: scheme,
            onTap: () => _goToEmployees(context),
          ),
        ],
        _DrawerItem(
          icon: Icons.history_outlined,
          label: context.l10n.history,
          textTheme: textTheme,
          scheme: scheme,
          onTap: () => _goToHistory(context),
        ),
        const Divider(height: 1),
        _DrawerItem(
          icon: Icons.settings_outlined,
          label: context.l10n.settings,
          textTheme: textTheme,
          scheme: scheme,
          onTap: () => _goToSettings(context),
        ),
      ],
    );
  }

  void _goToCalendar(BuildContext context) {
    Navigator.pop(context);
    Navigator.pushReplacementNamed(
      context,
      AppRoutes.mainCalendar,
      arguments: MainCalendarArgs(isAdmin: isAdmin, employeeId: employeeId),
    );
  }

  void _goToClients(BuildContext context) {
    Navigator.pop(context);
    Navigator.pushNamed(
      context,
      AppRoutes.clients,
      arguments: ClientsListArgs(
        mode: 'Clients',
        isAdmin: true,
        employeeId: employeeId,
      ),
    );
  }

  void _goToEmployees(BuildContext context) {
    Navigator.pop(context);
    Navigator.pushNamed(
      context,
      AppRoutes.employees,
      arguments: MainCalendarArgs(isAdmin: isAdmin, employeeId: employeeId),
    );
  }

  void _goToHistory(BuildContext context) {
    Navigator.pop(context);
    Navigator.pushNamed(
      context,
      AppRoutes.clients,
      arguments: ClientsListArgs(
        mode: 'Appointments',
        isAdmin: true,
        employeeId: employeeId,
      ),
    );
  }

  void _goToSettings(BuildContext context) {
    Navigator.pop(context);
    Navigator.pushNamed(context, AppRoutes.settings);
  }

}

class _DrawerItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final TextTheme textTheme;
  final ColorScheme scheme;
  final VoidCallback onTap;

  const _DrawerItem({
    required this.icon,
    required this.label,
    required this.textTheme,
    required this.scheme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: Icon(icon, color: scheme.onSurface, size: 20),
      title: Text(label, style: textTheme.bodyLarge?.copyWith(color: scheme.onSurface)),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.r8),
      ),
      onTap: onTap,
    );
  }
}

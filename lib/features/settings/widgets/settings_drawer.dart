import 'package:flutter/material.dart';

import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/core/utils/l10n_extensions.dart';
import 'package:scheduling/features/auth/services/auth_service.dart';
import 'package:scheduling/routes/app_routes.dart';
import 'package:scheduling/shared/widgets/app_avatar.dart';

class SettingsDrawer extends StatelessWidget {
  final bool isAdmin;
  final String employeeId;
  final String? userName;

  const SettingsDrawer({
    super.key,
    required this.isAdmin,
    required this.employeeId,
    this.userName,
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
    return UserAccountsDrawerHeader(
      decoration: const BoxDecoration(color: AppColors.primary),
      accountName: Text(
        userName ?? '…',
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
      ),
      accountEmail: Text(
        isAdmin ? context.l10n.admin : context.l10n.employeeRoleValue,
        style: const TextStyle(fontSize: 12, color: AppColors.primaryTint),
      ),
      currentAccountPicture: AppAvatar(
        name: userName ?? '?',
        color: AppColors.primaryDark,
        size: AvatarSize.lg,
      ),
    );
  }

  Widget _buildNavList(BuildContext context, ColorScheme scheme) {
    final textTheme = Theme.of(context).textTheme;

    return ListView(
      padding: EdgeInsets.zero,
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
          _DrawerItem(
            icon: Icons.history_outlined,
            label: context.l10n.history,
            textTheme: textTheme,
            scheme: scheme,
            onTap: () => _goToHistory(context),
          ),
        ],
        const Divider(),
        _DrawerItem(
          icon: Icons.settings_outlined,
          label: context.l10n.settings,
          textTheme: textTheme,
          scheme: scheme,
          onTap: () => _goToSettings(context),
        ),
        _DrawerItem(
          icon: Icons.logout,
          label: context.l10n.logOut,
          textTheme: textTheme,
          scheme: scheme,
          isDestructive: true,
          onTap: () => _signOut(context),
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

  Future<void> _signOut(BuildContext context) async {
    Navigator.pop(context);
    await AuthService().signOut();
    if (!context.mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, AppRoutes.login, (_) => false);
  }
}

class _DrawerItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final TextTheme textTheme;
  final ColorScheme scheme;
  final VoidCallback onTap;
  final bool isDestructive;

  const _DrawerItem({
    required this.icon,
    required this.label,
    required this.textTheme,
    required this.scheme,
    required this.onTap,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = isDestructive ? scheme.error : scheme.onSurface;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 24),
      leading: Icon(icon, color: color, size: 22),
      title: Text(label, style: textTheme.bodyLarge?.copyWith(color: color)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      onTap: onTap,
    );
  }
}

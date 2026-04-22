import 'package:flutter/material.dart';
import 'package:scheduling/views/login.dart';
import '../utils/theme_notifier.dart';
import '../views/employees.dart';
import '../views/informationList.dart';
import '../services/auth_service.dart';
import '../utils/theme_notifier.dart';
import '../views/employees.dart';
import '../views/login.dart';

class SettingsDrawer extends StatefulWidget {
  final bool isAdmin;

  const SettingsDrawer({super.key, required this.isAdmin});

  @override
  State<SettingsDrawer> createState() => _SettingsDrawerState();
}

class _SettingsDrawerState extends State<SettingsDrawer> {
  bool _showSettings = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Drawer(
      backgroundColor: scheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(left: Radius.circular(24)),
      ),
      child: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          child: _showSettings
              ? _buildSettingsView(scheme, textTheme)
              : _buildMenuView(scheme, textTheme),
        ),
      ),
    );
  }

  Widget _buildMenuView(ColorScheme scheme, TextTheme textTheme) {
    return Padding(
      key: const ValueKey('menu'),
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text('Menu', style: textTheme.headlineLarge),
          ),
          const SizedBox(height: 24),
          _DrawerItem(
            icon: Icons.calendar_month_outlined,
            label: 'Calendar',
            textTheme: textTheme,
            scheme: scheme,
            onTap: () {
              // TODO: navigate to calendar page
            },
          ),
          if (widget.isAdmin) ...[
            _DrawerItem(
              icon: Icons.badge_outlined,
              label: 'Employees',
              textTheme: textTheme,
              scheme: scheme,
              onTap: () {
                Navigator.push(context, MaterialPageRoute(builder: (context) =>
                    AddEmployeePage(),
                ));
              },
            ),
            _DrawerItem(
              icon: Icons.people_outline,
              label: 'Clients',
              textTheme: textTheme,
              scheme: scheme,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        ListInformation(mode: 'Clients', isAdmin: true),
                  ),
                );
              },
            ),
            _DrawerItem(
              icon: Icons.assignment_outlined,
              label: 'Appointments',
              textTheme: textTheme,
              scheme: scheme,
              onTap: () {
                Navigator.push(context, MaterialPageRoute(builder: (context) => ListInformation(mode: 'Appointments', isAdmin: true)));
              },
            ),
          ],
          _DrawerItem(
            icon: Icons.settings_outlined,
            label: 'Settings',
            textTheme: textTheme,
            scheme: scheme,
            onTap: () => setState(() => _showSettings = true),
          ),
          const Spacer(),
          const Divider(height: 1),
          _DrawerItem(
            icon: Icons.logout,
            label: 'Log out',
            textTheme: textTheme,
            scheme: scheme,
            isDestructive: true,
            onTap: () {
              // TODO: handle logout
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => Login()),
            onTap: () async {
              Navigator.pop(context);
              await AuthService().signOut();
              if (!context.mounted) return;
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const Login()),
                (_) => false,
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsView(ColorScheme scheme, TextTheme textTheme) {
    return Padding(
      key: const ValueKey('settings'),
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 12, right: 24),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                  onPressed: () => setState(() => _showSettings = false),
                ),
                const SizedBox(width: 8),
                Text('Settings', style: textTheme.headlineLarge),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Divider(height: 1),
          const SizedBox(height: 8),
          _DrawerItem(
            icon: Icons.text_fields_outlined,
            label: 'Font Size',
            textTheme: textTheme,
            scheme: scheme,
            onTap: () {
              // TODO: font size settings
            },
          ),
          Builder(
            builder: (ctx) {
              final themeNotifier = ThemeNotifier.of(ctx);
              final isDark = themeNotifier.isDark;
              return _DrawerItem(
                icon: isDark
                    ? Icons.light_mode_outlined
                    : Icons.dark_mode_outlined,
                label: isDark ? 'Light Mode' : 'Dark Mode',
                textTheme: textTheme,
                scheme: scheme,
                onTap: themeNotifier.toggleTheme,
              );
            },
          ),
          _DrawerItem(
            icon: Icons.language_outlined,
            label: 'Language',
            textTheme: textTheme,
            scheme: scheme,
            onTap: () {
              // TODO: language settings
            },
          ),
        ],
      ),
    );
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

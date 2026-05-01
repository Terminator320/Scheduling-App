import 'package:flutter/material.dart';

import 'package:scheduling/core/theme/theme_notifier.dart';
import 'package:scheduling/core/utils/app_language.dart';
import 'package:scheduling/features/auth/services/auth_service.dart';
import 'package:scheduling/routes/app_routes.dart';

class SettingsDrawer extends StatefulWidget {
  final bool isAdmin;
  final String employeeId;

  const SettingsDrawer({
    super.key,
    required this.isAdmin,
    required this.employeeId,
  });

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
              Navigator.pop(context);
              Navigator.pushReplacementNamed(
                context,
                AppRoutes.mainCalendar,
                arguments: MainCalendarArgs(
                  isAdmin: widget.isAdmin,
                  employeeId: widget.employeeId,
                ),
              );
            },
          ),
          if (widget.isAdmin) ...[
            _DrawerItem(
              icon: Icons.badge_outlined,
              label: 'Employees',
              textTheme: textTheme,
              scheme: scheme,
              onTap: () {
                Navigator.pop(context);
                Navigator.pushNamed(
                  context,
                  AppRoutes.employees,
                  arguments: MainCalendarArgs(
                    isAdmin: widget.isAdmin,
                    employeeId: widget.employeeId,
                  ),
                );
              },
            ),
            _DrawerItem(
              icon: Icons.people_outline,
              label: 'Clients',
              textTheme: textTheme,
              scheme: scheme,
              onTap: () {
                Navigator.pop(context);
                Navigator.pushNamed(
                  context,
                  AppRoutes.clients,
                  arguments: ClientsListArgs(
                    mode: 'Clients',
                    isAdmin: true,
                    employeeId: widget.employeeId,
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
                Navigator.pop(context);
                Navigator.pushNamed(
                  context,
                  AppRoutes.clients,
                  arguments: ClientsListArgs(
                    mode: 'Appointments',
                    isAdmin: true,
                    employeeId: widget.employeeId,
                  ),
                );
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

            onTap: () async {
              Navigator.pop(context);
              await AuthService().signOut();
              if (!context.mounted) return;
              Navigator.pushNamedAndRemoveUntil(
                context,
                AppRoutes.login,
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
          Builder(
            builder: (ctx) {
              final themeNotifier = ThemeNotifier.of(ctx);

              return _DrawerItem(
                icon: Icons.text_fields_outlined,
                label: 'Text Size',
                textTheme: textTheme,
                scheme: scheme,
                onTap: () {
                  double tempScale = themeNotifier.textScale;

                  showDialog(
                    context: context,
                    builder: (dialogContext) {
                      return StatefulBuilder(
                        builder: (context, setDialogState) {
                          return AlertDialog(
                            title: const Text('Text Size'),
                            content: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                MediaQuery(
                                  // Preview the new scale inside the dialog before applying it globally.
                                  data: MediaQuery.of(context).copyWith(
                                    textScaler: TextScaler.linear(tempScale),
                                  ),
                                  child: const Text('Preview text'),
                                ),
                                const SizedBox(height: 16),
                                Slider(
                                  value: tempScale,
                                  min: 0.8,
                                  max: 1.4,
                                  divisions: 6,
                                  label: tempScale.toStringAsFixed(1),
                                  onChanged: (value) {
                                    setDialogState(() {
                                      tempScale = value;
                                    });
                                  },
                                ),
                              ],
                            ),
                            actions: [
                              TextButton(
                                onPressed: () {
                                  // Apply text scale once when the user confirms the preview.
                                  themeNotifier.setTextScale(tempScale);
                                  Navigator.pop(dialogContext);
                                },
                                child: const Text('Done'),
                              ),
                            ],
                          );
                        },
                      );
                    },
                  );
                },
              );
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
          Builder(
            builder: (ctx) {
              final themeNotifier = ThemeNotifier.of(ctx);
              final langController = AppLanguageScope.of(ctx);
              return _DrawerItem(
                icon: Icons.language_outlined,
                label: 'Language',
                textTheme: textTheme,
                scheme: scheme,
                onTap: () {
                  String selected = langController.value;
                  showDialog(
                    context: context,
                    builder: (dialogContext) {
                      return StatefulBuilder(
                        builder: (context, setDialogState) {
                          return AlertDialog(
                            title: const Text('Language'),
                            content: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                RadioListTile<String>(
                                  title: const Text('English'),
                                  value: 'en',
                                  groupValue: selected,
                                  onChanged: (value) {
                                    setDialogState(() => selected = value!);
                                  },
                                ),
                                RadioListTile<String>(
                                  title: const Text('Français'),
                                  value: 'fr',
                                  groupValue: selected,
                                  onChanged: (value) {
                                    setDialogState(() => selected = value!);
                                  },
                                ),
                              ],
                            ),
                            actions: [
                              TextButton(
                                onPressed: () {
                                  // Apply language once when the user confirms the selection.
                                  themeNotifier.setLanguage(selected);
                                  Navigator.pop(dialogContext);
                                },
                                child: const Text('Done'),
                              ),
                            ],
                          );
                        },
                      );
                    },
                  );
                },
              );
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

import 'package:flutter/material.dart';

import 'package:scheduling/core/theme/theme_notifier.dart';
import 'package:scheduling/core/utils/app_language.dart';
import 'package:scheduling/core/utils/l10n_extensions.dart';
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
            child: Text(context.l10n.menu, style: textTheme.headlineLarge),
          ),
          const SizedBox(height: 24),
          _DrawerItem(
            icon: Icons.calendar_month_outlined,
            label: context.l10n.calendar,
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
              label: context.l10n.employees,
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
              label: context.l10n.clients,
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
              label: context.l10n.appointments,
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
            label: context.l10n.settings,
            textTheme: textTheme,
            scheme: scheme,
            onTap: () => setState(() => _showSettings = true),
          ),
          const Spacer(),
          const Divider(height: 1),
          _DrawerItem(
            icon: Icons.logout,
            label: context.l10n.logOut,
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
                Text(context.l10n.settings, style: textTheme.headlineLarge),
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
                label: context.l10n.textSize,
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
                            title: Text(context.l10n.textSize),
                            content: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(context.l10n.previewText),
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

                                    themeNotifier.setTextScale(value);
                                  },
                                ),
                              ],
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(dialogContext),
                                child: Text(context.l10n.done),
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
                label: isDark
                    ? context.l10n.lightMode
                    : context.l10n.darkMode,
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
                label: context.l10n.language,
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
                            title: Text(context.l10n.language),
                            content: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                RadioListTile<String>(
                                  title: Text(context.l10n.english),
                                  value: 'en',
                                  groupValue: selected,
                                  onChanged: (value) {
                                    setDialogState(() => selected = value!);
                                    themeNotifier.setLanguage(value!);
                                  },
                                ),
                                RadioListTile<String>(
                                  title: Text(context.l10n.french),
                                  value: 'fr',
                                  groupValue: selected,
                                  onChanged: (value) {
                                    setDialogState(() => selected = value!);
                                    themeNotifier.setLanguage(value!);
                                  },
                                ),
                              ],
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(dialogContext),
                                child: Text(context.l10n.done),
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

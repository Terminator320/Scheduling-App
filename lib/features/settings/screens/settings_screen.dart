import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/core/theme/theme_notifier.dart';
import 'package:scheduling/core/utils/l10n_extensions.dart';
import 'package:scheduling/features/auth/services/auth_service.dart';
import 'package:scheduling/features/settings/screens/text_size_screen.dart';
import 'package:scheduling/features/settings/widgets/settings_tiles.dart';
import 'package:scheduling/routes/app_routes.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.name = '', this.email = '', this.role});

  final String name;
  final String email;
  final String? role;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String get _displayName => widget.name.isNotEmpty
      ? widget.name
      : FirebaseAuth.instance.currentUser?.displayName ?? '';

  String get _email => widget.email.isNotEmpty
      ? widget.email
      : FirebaseAuth.instance.currentUser?.email ?? '';

  static String _textScaleLabel(double scale) {
    if (scale <= 0.85) return 'Small';
    if (scale <= 1.05) return 'Medium';
    if (scale <= 1.25) return 'Large';
    return 'XL';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final notifier = ThemeNotifier.of(context);
    final isDark = notifier.isDark;
    final langCode = Localizations.localeOf(context).languageCode;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          context.l10n.settings,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.sp16),
        children: [
          SettingsProfileCard(
            name: _displayName,
            email: _email,
            role: widget.role,
          ),
          const SizedBox(height: AppSpacing.sp24),
          SettingsSectionHeader(label: context.l10n.appearance.toUpperCase()),
          SettingsSectionCard(
            child: Column(
              children: [
                SettingsTile(
                  iconBg: scheme.primaryContainer,
                  icon: isDark
                      ? Icons.dark_mode_rounded
                      : Icons.light_mode_rounded,
                  iconColor: scheme.primary,
                  label: context.l10n.darkMode,
                  trailing: Switch.adaptive(
                    value: isDark,
                    onChanged: (_) => notifier.toggleTheme(),
                    activeTrackColor: scheme.primary,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                const SettingsTileDivider(),
                SettingsTile(
                  iconBg: scheme.tertiaryContainer,
                  icon: Icons.text_fields_rounded,
                  iconColor: scheme.tertiary,
                  label: context.l10n.textSize,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SettingsTrailingPill(
                        label: _textScaleLabel(notifier.textScale),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 18,
                        color: scheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                  onTap: () async {
                    await Navigator.push<void>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const TextSizeScreen(),
                      ),
                    );
                    if (mounted) setState(() {});
                  },
                ),
                const SettingsTileDivider(),
                SettingsTile(
                  iconBg: scheme.secondaryContainer,
                  icon: Icons.language_rounded,
                  iconColor: scheme.secondary,
                  label: context.l10n.language,
                  trailing: LanguageToggle(
                    currentCode: langCode,
                    onChanged: notifier.setLanguage,
                  ),
                  isLast: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sp24),
          SettingsSectionHeader(label: context.l10n.account.toUpperCase()),
          SettingsSectionCard(
            child: SettingsTile(
              iconBg: scheme.errorContainer,
              icon: Icons.logout_rounded,
              iconColor: scheme.error,
              label: context.l10n.logOut,
              labelColor: scheme.error,
              isLast: true,
              onTap: _signOut,
            ),
          ),
          const SizedBox(height: AppSpacing.sp32),
        ],
      ),
    );
  }

  Future<void> _signOut() async {
    await AuthService().signOut();
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, AppRoutes.login, (_) => false);
  }
}

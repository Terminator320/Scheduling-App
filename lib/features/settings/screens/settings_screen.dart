import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/core/theme/theme_notifier.dart';
import 'package:scheduling/core/utils/l10n_extensions.dart';
import 'package:scheduling/features/auth/services/auth_service.dart';
import 'package:scheduling/routes/app_routes.dart';
import 'package:scheduling/shared/widgets/app_avatar.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _auth = FirebaseAuth.instance;

  String get _displayName => _auth.currentUser?.displayName ?? 'User';
  String get _email => _auth.currentUser?.email ?? '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final themeNotifier = ThemeNotifier.of(context);
    final isDark = themeNotifier.isDark;

    // Determine current language label from locale
    final langCode = Localizations.localeOf(context).languageCode;
    final langLabel = langCode == 'fr' ? context.l10n.francais : context.l10n.english;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
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
        children: [
          // Profile card
          Container(
            color: scheme.surface,
            padding: const EdgeInsets.all(AppSpacing.sp16),
            child: Row(
              children: [
                AppAvatar(
                  name: _displayName,
                  color: AppColors.primaryDark,
                  size: AvatarSize.lg,
                ),
                const SizedBox(width: AppSpacing.sp16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_displayName, style: theme.textTheme.titleMedium),
                      const SizedBox(height: 2),
                      Text(
                        _email,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          const SizedBox(height: AppSpacing.sp16),

          // Appearance section header
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sp16,
              vertical: AppSpacing.sp8,
            ),
            child: Text(
              context.l10n.appearance.toUpperCase(),
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                letterSpacing: 0.6,
              ),
            ),
          ),

          // Appearance section body
          Container(
            color: scheme.surface,
            child: Column(
              children: [
                SwitchListTile(
                  title: Text(
                    context.l10n.darkMode,
                    style: theme.textTheme.bodyLarge,
                  ),
                  value: isDark,
                  onChanged: (_) => themeNotifier.toggleTheme(),
                  activeThumbColor: AppColors.primary,
                ),
                const Divider(height: 1, indent: 16),
                ListTile(
                  title: Text(
                    context.l10n.language,
                    style: theme.textTheme.bodyLarge,
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        langLabel,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.chevron_right,
                        color: scheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                  onTap: _showLanguagePicker,
                ),
                const Divider(height: 1, indent: 16),
                ListTile(
                  title: Text(
                    context.l10n.textSize,
                    style: theme.textTheme.bodyLarge,
                  ),
                  subtitle: Slider(
                    value: themeNotifier.textScale,
                    min: 0.8,
                    max: 1.4,
                    divisions: 6,
                    activeColor: AppColors.primary,
                    label: themeNotifier.textScale.toStringAsFixed(1),
                    onChanged: (v) => themeNotifier.setTextScale(v),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sp16),

          // Account section header
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sp16,
              vertical: AppSpacing.sp8,
            ),
            child: Text(
              context.l10n.account.toUpperCase(),
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                letterSpacing: 0.6,
              ),
            ),
          ),

          // Account section body
          Container(
            color: scheme.surface,
            child: ListTile(
              leading: Icon(Icons.logout, color: AppColors.error),
              title: Text(
                context.l10n.logOut,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: AppColors.error,
                ),
              ),
              onTap: _signOut,
            ),
          ),
          const SizedBox(height: AppSpacing.sp32),
        ],
      ),
    );
  }

  void _showLanguagePicker() {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final notifier = ThemeNotifier.of(ctx);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              title: Text(context.l10n.english),
              onTap: () {
                Navigator.pop(ctx);
                notifier.setLanguage('en');
              },
            ),
            ListTile(
              title: Text(context.l10n.francais),
              onTap: () {
                Navigator.pop(ctx);
                notifier.setLanguage('fr');
              },
            ),
            const SizedBox(height: 8),
          ],
        );
      },
    );
  }

  Future<void> _signOut() async {
    await AuthService().signOut();
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(
      context,
      AppRoutes.login,
      (_) => false,
    );
  }
}

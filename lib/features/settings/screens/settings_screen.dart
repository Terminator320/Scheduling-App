import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/core/theme/theme_notifier.dart';
import 'package:scheduling/core/utils/l10n_extensions.dart';
import 'package:scheduling/features/auth/services/auth_service.dart';
import 'package:scheduling/features/employees/services/user_service.dart';
import 'package:scheduling/features/settings/screens/text_size_screen.dart';
import 'package:scheduling/routes/app_routes.dart';
import 'package:scheduling/shared/widgets/app_avatar.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String? _role;

  @override
  void initState() {
    super.initState();
    _fetchRole();
  }

  Future<void> _fetchRole() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final userDoc = await UserService().findUserByUid(uid);
    if (!mounted || userDoc == null) return;
    final data = userDoc.data();
    setState(() => _role = (data['role'] ?? 'employee').toString());
  }

  String get _displayName {
    try {
      return FirebaseAuth.instance.currentUser?.displayName ?? 'User';
    } catch (_) {
      return 'User';
    }
  }

  String get _email {
    try {
      return FirebaseAuth.instance.currentUser?.email ?? '';
    } catch (_) {
      return '';
    }
  }

  static String _textScaleLabel(double scale) {
    if (scale <= 0.85) return 'Small';
    if (scale <= 1.05) return 'Medium';
    if (scale <= 1.25) return 'Large';
    return 'Extra Large';
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
      backgroundColor: AppColors.background,
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.sp16),
        children: [
          // ── Profile card ──────────────────────────────────────────
          _SectionCard(
            child: Row(
              children: [
                AppAvatar(
                  name: _displayName,
                  color: AppColors.primary,
                  size: AvatarSize.lg,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _displayName,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _email.isNotEmpty ? _email : '—',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      if (_role != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          _role == 'admin'
                              ? context.l10n.admin
                              : context.l10n.employeeRoleValue,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sp16),

          // ── Appearance header ─────────────────────────────────────
          _SectionHeader(label: context.l10n.appearance.toUpperCase()),

          // ── Appearance card ───────────────────────────────────────
          _SectionCard(
            child: Column(
              children: [
                // Dark Mode
                _SettingsTile(
                  iconBg: AppColors.primarySurface,
                  icon: isDark
                      ? Icons.dark_mode_outlined
                      : Icons.light_mode_outlined,
                  iconColor: AppColors.primary,
                  label: context.l10n.darkMode,
                  trailing: Switch(
                    value: isDark,
                    onChanged: (_) => notifier.toggleTheme(),
                    activeThumbColor: AppColors.primary,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                const Divider(height: 1, color: AppColors.outline),

                // Text Size
                _SettingsTile(
                  iconBg: const Color(0xFFF3E8FF),
                  icon: Icons.text_fields_outlined,
                  iconColor: AppColors.accent,
                  label: context.l10n.textSize,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _textScaleLabel(notifier.textScale),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.chevron_right,
                          size: 18, color: scheme.onSurfaceVariant),
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
                const Divider(height: 1, color: AppColors.outline),

                // Language
                _SettingsTile(
                  iconBg: const Color(0xFFECFDF5),
                  icon: Icons.language_outlined,
                  iconColor: AppColors.success,
                  label: context.l10n.language,
                  trailing: _LangToggle(
                    currentCode: langCode,
                    onChanged: (code) => notifier.setLanguage(code),
                  ),
                  isLast: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sp16),

          // ── Account header ────────────────────────────────────────
          _SectionHeader(label: context.l10n.account.toUpperCase()),

          // ── Account card ──────────────────────────────────────────
          _SectionCard(
            child: _SettingsTile(
              label: context.l10n.logOut,
              labelColor: AppColors.error,
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

// ── Private helpers ────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.r12),
      ),
      padding: const EdgeInsets.all(14),
      child: child,
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 7),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          letterSpacing: 0.8,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    this.iconBg,
    this.icon,
    this.iconColor,
    required this.label,
    this.labelColor,
    this.trailing,
    this.onTap,
    this.isLast = false,
  });

  final Color? iconBg;
  final IconData? icon;
  final Color? iconColor;
  final String label;
  final Color? labelColor;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.r8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            if (icon != null && iconBg != null && iconColor != null) ...[
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(AppRadius.r8),
                ),
                child: Icon(icon, size: 18, color: iconColor),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w500,
                  color: labelColor,
                ),
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}

class _LangToggle extends StatelessWidget {
  const _LangToggle({required this.currentCode, required this.onChanged});

  final String currentCode;
  final void Function(String code) onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(AppRadius.r8),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _LangBtn(
            code: 'en',
            label: 'EN',
            isActive: currentCode == 'en',
            onTap: () => onChanged('en'),
          ),
          const SizedBox(width: 2),
          _LangBtn(
            code: 'fr',
            label: 'FR',
            isActive: currentCode == 'fr',
            onTap: () => onChanged('fr'),
          ),
        ],
      ),
    );
  }
}

class _LangBtn extends StatelessWidget {
  const _LangBtn({
    required this.code,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  final String code;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppDuration.fast,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isActive ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          boxShadow: isActive
              ? [
                  const BoxShadow(
                    color: Color(0x1A000000),
                    blurRadius: 3,
                    offset: Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: isActive ? AppColors.primary : AppColors.subtle,
          ),
        ),
      ),
    );
  }
}

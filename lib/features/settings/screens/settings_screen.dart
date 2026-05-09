import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/core/theme/theme_notifier.dart';
import 'package:scheduling/core/utils/l10n_extensions.dart';
import 'package:scheduling/features/auth/services/auth_service.dart';
import 'package:scheduling/features/settings/screens/text_size_screen.dart';
import 'package:scheduling/routes/app_routes.dart';
import 'package:scheduling/shared/widgets/app_avatar.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    this.name = '',
    this.email = '',
    this.role,
  });

  final String name;
  final String email;
  final String? role;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String get _displayName =>
      widget.name.isNotEmpty
          ? widget.name
          : FirebaseAuth.instance.currentUser?.displayName ?? '';

  String get _email =>
      widget.email.isNotEmpty
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
    final scheme = Theme.of(context).colorScheme;
    final notifier = ThemeNotifier.of(context);
    final isDark = notifier.isDark;
    final langCode = Localizations.localeOf(context).languageCode;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
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
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.background,
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.sp16),
        children: [
          // ── Profile hero ─────────────────────────────────────────────
          _ProfileCard(name: _displayName, email: _email, role: widget.role),
          const SizedBox(height: AppSpacing.sp24),

          // ── Appearance ───────────────────────────────────────────────
          _SectionHeader(label: context.l10n.appearance.toUpperCase()),
          _SectionCard(
            child: Column(
              children: [
                // Dark Mode — icon/bg depend on current mode, computed here
                _SettingsTile(
                  iconBg: isDark
                      ? AppColors.darkPrimaryTint
                      : AppColors.primarySurface,
                  icon: isDark
                      ? Icons.dark_mode_rounded
                      : Icons.light_mode_rounded,
                  iconColor: AppColors.primary,
                  label: context.l10n.darkMode,
                  trailing: Switch.adaptive(
                    value: isDark,
                    onChanged: (_) => notifier.toggleTheme(),
                    activeTrackColor: AppColors.primary,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                const _TileDivider(),

                // Text Size
                _SettingsTile(
                  iconBg: isDark
                      ? const Color(0xFF2D1B4E)
                      : const Color(0xFFF3E8FF),
                  icon: Icons.text_fields_rounded,
                  iconColor: AppColors.accent,
                  label: context.l10n.textSize,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _TrailingPill(label: _textScaleLabel(notifier.textScale)),
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
                const _TileDivider(),

                // Language
                _SettingsTile(
                  iconBg: isDark
                      ? const Color(0xFF052E16)
                      : const Color(0xFFECFDF5),
                  icon: Icons.language_rounded,
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
          const SizedBox(height: AppSpacing.sp24),

          // ── Account ──────────────────────────────────────────────────
          _SectionHeader(label: context.l10n.account.toUpperCase()),
          _SectionCard(
            child: _SettingsTile(
              iconBg: AppColors.errorTint,
              icon: Icons.logout_rounded,
              iconColor: AppColors.error,
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

// ── Profile Card ──────────────────────────────────────────────────────────────

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.name, required this.email, required this.role});

  final String name;
  final String email;
  final String? role;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = ThemeNotifier.of(context).isDark;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.r16),
        boxShadow: isDark ? null : AppShadow.card,
        border: isDark ? Border.all(color: AppColors.darkSurfaceAlt) : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.r16),
        child: ColoredBox(
          color: scheme.surface,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Gradient header band
              Container(
                height: 72,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppColors.primary, AppColors.primaryDark],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Align(
                  alignment: Alignment.bottomRight,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 20, bottom: 10),
                    child: Icon(
                      Icons.water_drop_outlined,
                      size: 44,
                      color: Colors.white.withValues(alpha: 0.12),
                    ),
                  ),
                ),
              ),
              // Profile info row
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
                child: Row(
                  children: [
                    AppAvatar(
                      name: name,
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
                            name.isNotEmpty ? name : '—',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 5),
                          Row(
                            children: [
                              if (role != null) ...[
                                _RoleBadge(role: role!),
                                if (email.isNotEmpty) const SizedBox(width: 6),
                              ],
                              if (email.isNotEmpty)
                                Flexible(
                                  child: Text(
                                    email,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoleBadge extends StatelessWidget {
  const _RoleBadge({required this.role});

  final String role;

  @override
  Widget build(BuildContext context) {
    final isDark = ThemeNotifier.of(context).isDark;
    final label = role == 'admin'
        ? context.l10n.admin
        : context.l10n.employeeRoleValue;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkPrimaryTint : AppColors.primaryTint,
        borderRadius: BorderRadius.circular(AppRadius.rFull),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: isDark ? AppColors.darkPrimaryOnDark : AppColors.primaryDark,
        ),
      ),
    );
  }
}

// ── Section Card ──────────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isDark = ThemeNotifier.of(context).isDark;
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.r12),
        boxShadow: isDark ? null : AppShadow.card,
        border: isDark ? Border.all(color: AppColors.darkSurfaceAlt) : null,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: child,
    );
  }
}

// ── Section Header ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final isDark = ThemeNotifier.of(context).isDark;
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8, top: 2),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: isDark ? AppColors.darkSubtle : AppColors.subtle,
          letterSpacing: 1.0,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

// ── Tile Divider ──────────────────────────────────────────────────────────────

class _TileDivider extends StatelessWidget {
  const _TileDivider();

  @override
  Widget build(BuildContext context) {
    final isDark = ThemeNotifier.of(context).isDark;
    return Divider(
      height: 1,
      color: isDark ? AppColors.darkSurfaceAlt : AppColors.outline,
    );
  }
}

// ── Trailing Pill ─────────────────────────────────────────────────────────────

class _TrailingPill extends StatelessWidget {
  const _TrailingPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final isDark = ThemeNotifier.of(context).isDark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurfaceAlt : AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(AppRadius.rFull),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: isDark ? AppColors.darkSubtle : AppColors.subtle,
        ),
      ),
    );
  }
}

// ── Settings Tile ─────────────────────────────────────────────────────────────

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
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            if (icon != null && iconBg != null && iconColor != null) ...[
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(AppRadius.r8),
                ),
                child: Icon(icon, size: 18, color: iconColor),
              ),
              const SizedBox(width: 13),
            ],
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w500,
                  color: labelColor,
                  fontSize: 15,
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

// ── Language Toggle ───────────────────────────────────────────────────────────

class _LangToggle extends StatelessWidget {
  const _LangToggle({required this.currentCode, required this.onChanged});

  final String currentCode;
  final void Function(String code) onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.r8),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _LangBtn(
            label: 'EN',
            isActive: currentCode == 'en',
            onTap: () => onChanged('en'),
          ),
          const SizedBox(width: 2),
          _LangBtn(
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
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  final String label;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppDuration.fast,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isActive ? scheme.surface : Colors.transparent,
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
            color: isActive ? AppColors.primary : scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

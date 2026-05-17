import 'package:flutter/material.dart';

import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/core/utils/l10n_extensions.dart';
import 'package:scheduling/shared/widgets/app_avatar.dart';

class SettingsSectionCard extends StatelessWidget {
  const SettingsSectionCard({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.r12),
        boxShadow: isDark ? null : AppShadow.card,
        border: isDark ? Border.all(color: scheme.outlineVariant) : null,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: child,
    );
  }
}

class SettingsSectionHeader extends StatelessWidget {
  const SettingsSectionHeader({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8, top: 2),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: scheme.onSurfaceVariant,
          letterSpacing: 1,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class SettingsTileDivider extends StatelessWidget {
  const SettingsTileDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      color: Theme.of(context).colorScheme.outlineVariant,
    );
  }
}

class SettingsTrailingPill extends StatelessWidget {
  const SettingsTrailingPill({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.rFull),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class SettingsTile extends StatelessWidget {
  const SettingsTile({
    required this.label,
    this.iconBg,
    this.icon,
    this.iconColor,
    this.labelColor,
    this.trailing,
    this.onTap,
    this.isLast = false,
    super.key,
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

class LanguageToggle extends StatelessWidget {
  const LanguageToggle({
    required this.currentCode,
    required this.onChanged,
    super.key,
  });

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
              ? const [
                  BoxShadow(
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
            color: isActive ? scheme.primary : scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class SettingsProfileCard extends StatelessWidget {
  const SettingsProfileCard({
    required this.name,
    required this.email,
    required this.role,
    super.key,
  });

  final String name;
  final String email;
  final String? role;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.r16),
        boxShadow: isDark ? null : AppShadow.card,
        border: isDark ? Border.all(color: scheme.outlineVariant) : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.r16),
        child: ColoredBox(
          color: scheme.surface,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                height: 72,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [scheme.primary, scheme.primary.withValues(alpha: 0.8)],
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
                      color: scheme.onPrimary.withValues(alpha: 0.12),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
                child: Row(
                  children: [
                    AppAvatar(
                      name: name,
                      color: scheme.primary,
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
    final scheme = Theme.of(context).colorScheme;
    final label = role == 'admin'
        ? context.l10n.admin
        : context.l10n.employeeRoleValue;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(AppRadius.rFull),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: scheme.onPrimaryContainer,
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:scheduling/core/layout/breakpoints.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/features/settings/domain/role_label.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/primitives/app_avatar.dart';

class SettingsSectionCard extends StatelessWidget {
  const SettingsSectionCard({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: appCardDecoration(theme, color: theme.colorScheme.surface),
      // A transparent Material sits between the opaque card decoration and the
      // child so a descendant ListTile paints its ink/background on a Material
      // in front of the card fill (otherwise it paints on the Scaffold behind
      // the decoration and Flutter asserts "ink splashes may be invisible").
      child: Material(
        type: MaterialType.transparency,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sp16),
          child: child,
        ),
      ),
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
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sp8,
        vertical: AppSpacing.sp4,
      ),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.rFull),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
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
    final narrowOrLarge = context.isCompact;

    final Widget? leading = icon != null && iconBg != null && iconColor != null
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(AppRadius.r8),
                ),
                child: Icon(icon, size: 18, color: iconColor),
              ),
              const SizedBox(width: AppSpacing.sp12),
            ],
          )
        : null;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.r8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sp12),
        child: narrowOrLarge
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ?leading,
                      Expanded(
                        child: Text(
                          label,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w500,
                            color: labelColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (trailing != null) ...[
                    const SizedBox(height: AppSpacing.sp8),
                    Align(alignment: Alignment.centerLeft, child: trailing),
                  ],
                ],
              )
            : Row(
                children: [
                  ?leading,
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
      child: Wrap(
        spacing: 2,
        runSpacing: 2,
        children: [
          _LangBtn(
            label: 'EN',
            isActive: currentCode == 'en',
            onTap: () => onChanged('en'),
          ),
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

  /// Minimum tap-target side (Apple HIG / Material a11y): the old
  /// text-sized GestureDetector was ~24x17px and easy to miss.
  static const double _minTapTarget = 44;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: isActive,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.r8),
          child: AnimatedContainer(
            duration: AppDuration.fast,
            constraints: const BoxConstraints(
              minWidth: _minTapTarget,
              minHeight: _minTapTarget,
            ),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sp8),
            decoration: BoxDecoration(
              color: isActive ? scheme.surface : Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadius.r8),
              boxShadow: isActive ? AppShadow.pill : null,
            ),
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: isActive ? scheme.primary : scheme.onSurfaceVariant,
              ),
            ),
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
    final narrowOrLarge = context.isCompact;

    final avatar = AppAvatar(
      name: name,
      color: scheme.primary,
      size: AvatarSize.lg,
    );

    final identity = Column(
      crossAxisAlignment: narrowOrLarge
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          name.isNotEmpty ? name : '—',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: narrowOrLarge ? TextAlign.center : TextAlign.start,
        ),
        const SizedBox(height: AppSpacing.sp4),
        Wrap(
          alignment: narrowOrLarge ? WrapAlignment.center : WrapAlignment.start,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: AppSpacing.sp8,
          runSpacing: AppSpacing.sp4,
          children: [
            if (role != null) _RoleBadge(role: role!),
            if (email.isNotEmpty)
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: narrowOrLarge ? 260 : 220,
                ),
                child: Text(
                  email,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: narrowOrLarge ? TextAlign.center : TextAlign.start,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ],
    );

    return Container(
      decoration: appCardDecoration(theme, radius: AppRadius.r16),
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
                    colors: [
                      scheme.primary,
                      scheme.primary.withValues(alpha: 0.8),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Align(
                  alignment: Alignment.bottomRight,
                  child: Padding(
                    padding: const EdgeInsets.only(
                      right: AppSpacing.sp24,
                      bottom: AppSpacing.sp12,
                    ),
                    child: FaIcon(
                      FontAwesomeIcons.droplet,
                      size: 40,
                      color: scheme.onPrimary.withValues(alpha: 0.12),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.sp16),
                child: narrowOrLarge
                    ? Column(
                        children: [
                          avatar,
                          const SizedBox(height: AppSpacing.sp12),
                          identity,
                        ],
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          avatar,
                          const SizedBox(width: AppSpacing.sp16),
                          Expanded(child: identity),
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
    final label = roleLabel(context.l10n, isAdmin: role == 'admin');
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sp8,
        vertical: AppSpacing.sp4,
      ),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(AppRadius.rFull),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w600,
          color: scheme.onPrimaryContainer,
        ),
      ),
    );
  }
}

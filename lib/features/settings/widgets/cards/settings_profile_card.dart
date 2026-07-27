import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:scheduling/core/layout/breakpoints.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/features/settings/domain/role_label.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/primitives/app_avatar.dart';

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

    final identity = _ProfileIdentity(
      name: name,
      email: email,
      role: role,
      narrowOrLarge: narrowOrLarge,
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
              const _ProfileHeaderBanner(),
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

class _ProfileIdentity extends StatelessWidget {
  const _ProfileIdentity({
    required this.name,
    required this.email,
    required this.role,
    required this.narrowOrLarge,
  });

  final String name;
  final String email;
  final String? role;
  final bool narrowOrLarge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
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
  }
}

class _ProfileHeaderBanner extends StatelessWidget {
  const _ProfileHeaderBanner();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
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

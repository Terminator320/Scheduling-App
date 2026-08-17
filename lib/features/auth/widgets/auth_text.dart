import 'package:flutter/material.dart';

import 'package:scheduling/core/animations/app_animation_constants.dart';
import 'package:scheduling/core/theme/design_tokens.dart';

/// The auth screens' typographic and transition pieces — the form/success
/// switcher, the section heading and the icon badge above it.

/// Animates between form and success state via fade + slide.
class AuthFormSwitcher extends StatelessWidget {
  const AuthFormSwitcher({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: AppAnimationDurations.banner,
      switchInCurve: AppAnimationCurves.entrance,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.04),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

/// Centered headline + subtitle for auth forms, centered full-width below the brand mark.
class AuthHeaderText extends StatelessWidget {
  const AuthHeaderText({
    required this.title,
    required this.subtitle,
    super.key,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: double.infinity,
      child: Column(
        children: [
          Text(
            title,
            style: theme.textTheme.headlineLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.sp4),
          Text(
            subtitle,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// 44×44 rounded square holding a centered icon, defaulting to primary brand colors.
class AuthIconBadge extends StatelessWidget {
  const AuthIconBadge({
    required this.icon,
    this.background,
    this.foreground,
    super.key,
  });

  final IconData icon;
  final Color? background;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: background ?? scheme.primary,
        borderRadius: BorderRadius.circular(AppRadius.r12),
      ),
      child: Icon(icon, color: foreground ?? scheme.onPrimary, size: 22),
    );
  }
}

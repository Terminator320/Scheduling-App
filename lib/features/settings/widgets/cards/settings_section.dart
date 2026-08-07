import 'package:flutter/material.dart';

import 'package:scheduling/core/theme/design_tokens.dart';

class SettingsSectionCard extends StatelessWidget {
  const SettingsSectionCard({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: appCardDecoration(theme, color: theme.colorScheme.surface),
      // Transparent Material between card decoration and child so ListTile ink paints correctly.
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
      padding: const EdgeInsets.only(
        left: AppSpacing.sp4,
        bottom: AppSpacing.sp8,
        top: 2,
      ),
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

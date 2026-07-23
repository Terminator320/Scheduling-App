import 'package:flutter/material.dart';

import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/l10n/l10n.dart';

/// Small chip reflecting Wave sync state; renders nothing when empty/unknown.
class WaveSyncBadge extends StatelessWidget {
  const WaveSyncBadge({
    required this.syncState,
    super.key,
    this.syncError,
  });

  final String syncState;

  /// Raw error string from waveSyncError; exposed as Semantics label when error.
  final String? syncError;

  @override
  Widget build(BuildContext context) {
    final config = _badgeConfig(context);
    if (config == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final semanticsLabel = syncState == 'error' && syncError != null
        ? '${config.label}: $syncError'
        : config.label;

    return Semantics(
      label: semanticsLabel,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sp8,
          vertical: AppSpacing.sp4,
        ),
        decoration: BoxDecoration(
          color: config.background,
          borderRadius: BorderRadius.circular(AppRadius.rFull),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(config.icon, size: 12, color: config.foreground),
            const SizedBox(width: AppSpacing.sp4),
            Text(
              config.label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: config.foreground,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  _BadgeConfig? _badgeConfig(BuildContext context) {
    final sc = Theme.of(context).statusColors;
    final scheme = Theme.of(context).colorScheme;

    switch (syncState) {
      case 'synced':
        return _BadgeConfig(
          label: context.l10n.wave_syncedWithWave,
          icon: Icons.check_circle_outline_rounded,
          background: sc.successContainer,
          foreground: sc.onSuccessContainer,
        );
      case 'pending':
        return _BadgeConfig(
          label: context.l10n.wave_syncPending,
          icon: Icons.sync_rounded,
          background: scheme.surfaceContainerHighest,
          foreground: scheme.onSurfaceVariant,
        );
      case 'error':
        return _BadgeConfig(
          label: context.l10n.wave_syncError,
          icon: Icons.error_outline_rounded,
          background: scheme.errorContainer,
          foreground: scheme.onErrorContainer,
        );
      default:
        return null;
    }
  }
}

class _BadgeConfig {
  const _BadgeConfig({
    required this.label,
    required this.icon,
    required this.background,
    required this.foreground,
  });

  final String label;
  final IconData icon;
  final Color background;
  final Color foreground;
}

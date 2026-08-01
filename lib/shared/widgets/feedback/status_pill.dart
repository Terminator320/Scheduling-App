import 'package:flutter/material.dart';
import 'package:scheduling/core/theme/design_tokens.dart';

/// Rounded label pill shared by `StatusChip` and `UserStatusChip` so they don't
/// duplicate the container shape and text-scale cap.
class StatusPill extends StatelessWidget {
  const StatusPill({
    required this.label,
    required this.background,
    required this.foreground,
    super.key,
    this.radius = AppRadius.rFull,
  });

  final String label;
  final Color background;
  final Color foreground;

  /// Corner radius. Fully rounded for status chips; the client-type pill on the
  /// list tile uses the softer [AppRadius.r8] the design draws it with.
  final double radius;

  static const double _maxLabelScale = 1.3;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final userScale = MediaQuery.textScalerOf(context).scale(1);
    final cappedScaler = TextScaler.linear(
      userScale < _maxLabelScale ? userScale : _maxLabelScale,
    );
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sp8 + 2,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Text(
        label,
        textScaler: cappedScaler,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        softWrap: false,
        style: theme.textTheme.labelSmall?.copyWith(
          color: foreground,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

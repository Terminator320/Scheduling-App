import 'package:flutter/material.dart';
import 'package:scheduling/core/theme/design_tokens.dart';

/// The rounded label pill shared by `StatusChip` and `UserStatusChip`. Owns the
/// container shape and the user-text-scale cap so the two chips don't duplicate
/// it — each caller just supplies the resolved label and its background /
/// foreground colors.
class StatusPill extends StatelessWidget {
  const StatusPill({
    required this.label,
    required this.background,
    required this.foreground,
    super.key,
  });

  final String label;
  final Color background;
  final Color foreground;

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
        borderRadius: BorderRadius.circular(AppRadius.rFull),
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

import 'package:flutter/material.dart';

import 'package:scheduling/core/theme/design_tokens.dart';

/// An amber info box: leading icon plus a wrapping caption, on the warning
/// container fill.
///
/// This is the "heads up, but nothing failed" surface — a caveat attached to an
/// action that succeeded. A real failure uses `AuthBanner`/`composeErrorNotice`
/// instead. The icon reads `onWarningContainer`, the same token as the text
/// beside it, so both keep contrast against the fill in either theme.
class WarningNote extends StatelessWidget {
  const WarningNote({
    required this.message,
    this.icon = Icons.info_outline_rounded,
    this.radius = AppRadius.r12,
    this.filled = true,
    super.key,
  });

  final String message;
  final IconData icon;
  final double radius;

  /// Unfilled drops the container and shrinks the icon: the caption already
  /// sits inside a bordered surface (a dialog, a form section), where a second
  /// amber panel reads as a nested box rather than a caveat. Same tokens
  /// either way, so the two spellings can't drift the way the hand-rolled
  /// copies did.
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = theme.statusColors;
    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(top: filled ? 0 : 1),
          child: Icon(
            icon,
            size: filled ? 16 : 14,
            color: status.onWarningContainer,
          ),
        ),
        const SizedBox(width: AppSpacing.sp8),
        Expanded(
          child: Text(
            message,
            style: theme.textTheme.bodySmall?.copyWith(
              color: status.onWarningContainer,
            ),
          ),
        ),
      ],
    );
    if (!filled) return row;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sp12),
      decoration: BoxDecoration(
        color: status.warningContainer,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: row,
    );
  }
}

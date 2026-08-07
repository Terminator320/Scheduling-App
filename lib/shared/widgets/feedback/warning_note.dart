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
    super.key,
  });

  final String message;
  final IconData icon;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = theme.statusColors;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sp12),
      decoration: BoxDecoration(
        color: status.warningContainer,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: status.onWarningContainer),
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
      ),
    );
  }
}

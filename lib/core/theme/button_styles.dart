import 'package:flutter/material.dart';

import 'package:scheduling/core/theme/design_tokens.dart';

/// Shared [TextButton] style for the tinted accent pill that opens an edit
/// sheet from a detail header — the client detail's and the team profile
/// card's are the same control and must stay that way.
ButtonStyle accentPillButtonStyle(BuildContext context) {
  final palette = Theme.of(context).palette;
  return TextButton.styleFrom(
    backgroundColor: palette.primaryAccent.withValues(alpha: 0.10),
    foregroundColor: palette.primaryAccent,
    padding: const EdgeInsets.symmetric(
      horizontal: 14,
      vertical: AppSpacing.sp8,
    ),
    // Design draws this smaller, but a tap target stays >= 48.
    minimumSize: const Size(0, 48),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.r12),
    ),
  );
}

/// Shared [OutlinedButton] style for destructive actions with error-colored foreground and border.
ButtonStyle destructiveOutlinedButtonStyle(
  BuildContext context, {
  Size? minimumSize,
}) {
  final scheme = Theme.of(context).colorScheme;
  return OutlinedButton.styleFrom(
    minimumSize: minimumSize,
    foregroundColor: scheme.error,
    side: BorderSide(color: scheme.error),
  );
}

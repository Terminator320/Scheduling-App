import 'package:flutter/material.dart';

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

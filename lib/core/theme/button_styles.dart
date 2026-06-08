import 'package:flutter/material.dart';

/// Shared [OutlinedButton] style for destructive actions (delete / cancel):
/// an error-colored foreground and border. Pass [minimumSize] for the
/// full-width variant used in action bars and edit forms.
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

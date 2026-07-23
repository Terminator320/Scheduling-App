import 'package:flutter/material.dart';
import 'package:scheduling/core/theme/design_tokens.dart';

/// Standard error SnackBar; used by sites bypassing the notice overlay.
SnackBar errorSnackBar(
  BuildContext context,
  String message, {
  SnackBarAction? action,
}) {
  final scheme = Theme.of(context).colorScheme;
  return SnackBar(
    backgroundColor: scheme.errorContainer,
    action: action,
    content: Row(
      children: [
        Icon(Icons.error_outline, color: scheme.onErrorContainer, size: 20),
        const SizedBox(width: AppSpacing.sp12),
        Expanded(
          child: Text(
            message,
            style: TextStyle(color: scheme.onErrorContainer),
          ),
        ),
      ],
    ),
  );
}

import 'package:flutter/material.dart';
import 'package:scheduling/core/theme/design_tokens.dart';

/// The app's standard error [SnackBar]: an error-container background with a
/// leading error icon and the [message], plus an optional trailing [action].
///
/// Used by the few feedback sites that must use a SnackBar instead of the
/// notice overlay (account-disabled, photo-upload, map-launch) — see the
/// notices rule for why those bypass `NoticeService`.
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

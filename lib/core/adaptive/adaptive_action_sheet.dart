import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:scheduling/core/adaptive/adaptive.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/l10n/l10n.dart';

/// One selectable option in [showAdaptiveActionSheet].
class AdaptiveSheetAction<T> {
  const AdaptiveSheetAction({
    required this.value,
    required this.label,
    this.icon,
    this.isDestructive = false,
  });

  /// Returned from the sheet when this action is chosen.
  final T value;
  final String label;

  /// Leading glyph on the Android bottom-sheet row (ignored on iOS).
  final IconData? icon;

  /// Renders the iOS action (and the Android row) in the error colour.
  final bool isDestructive;
}

/// Platform-adaptive chooser — a `CupertinoActionSheet` on iOS, the app's
/// Material `showModalBottomSheet` list on Android — returning the chosen
/// action's value, or null if dismissed/cancelled.
Future<T?> showAdaptiveActionSheet<T>(
  BuildContext context, {
  required List<AdaptiveSheetAction<T>> actions,
  String? title,
  String? message,
}) {
  if (context.isCupertino) {
    return showCupertinoModalPopup<T>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: title == null ? null : Text(title),
        message: message == null ? null : Text(message),
        actions: [
          for (final action in actions)
            CupertinoActionSheetAction(
              isDestructiveAction: action.isDestructive,
              onPressed: () => Navigator.pop(ctx, action.value),
              child: Text(action.label),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDefaultAction: true,
          onPressed: () => Navigator.pop(ctx),
          child: Text(ctx.l10n.common_cancel),
        ),
      ),
    );
  }
  return showModalBottomSheet<T>(
    context: context,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      final error = theme.colorScheme.error;
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null || message != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.sp16,
                  AppSpacing.sp16,
                  AppSpacing.sp16,
                  AppSpacing.sp8,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (title != null)
                      Text(title, style: theme.textTheme.titleMedium),
                    if (message != null)
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.sp4),
                        child: Text(message, style: theme.textTheme.bodySmall),
                      ),
                  ],
                ),
              ),
            for (final action in actions)
              ListTile(
                leading: action.icon == null ? null : Icon(action.icon),
                title: Text(action.label),
                textColor: action.isDestructive ? error : null,
                iconColor: action.isDestructive ? error : null,
                onTap: () => Navigator.pop(ctx, action.value),
              ),
          ],
        ),
      );
    },
  );
}

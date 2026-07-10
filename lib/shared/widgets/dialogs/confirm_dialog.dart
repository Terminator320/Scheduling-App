import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:scheduling/core/adaptive/adaptive.dart';
import 'package:scheduling/l10n/l10n.dart';

/// Cancel/confirm dialog shared by the destructive flows; resolves true only
/// on confirm. Pass [content] instead of [message] for a rich body. Renders a
/// [CupertinoAlertDialog] on iOS and the Material [AlertDialog] on Android.
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String confirmLabel,
  String? message,
  Widget? content,
  bool destructive = true,
}) async {
  assert(message != null || content != null, 'message or content is required');
  final bool? result;
  if (context.isCupertino) {
    result = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(title),
        content: content ?? Text(message!),
        actions: [
          CupertinoDialogAction(
            // Destructive: Cancel is the bold, safe default (iOS convention).
            // Non-destructive: the confirm action is the default instead.
            isDefaultAction: destructive,
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(ctx.l10n.common_cancel),
          ),
          CupertinoDialogAction(
            isDestructiveAction: destructive,
            isDefaultAction: !destructive,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
  } else {
    result = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final scheme = Theme.of(ctx).colorScheme;
        return AlertDialog(
          title: Text(title),
          content: content ?? Text(message!),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(ctx.l10n.common_cancel),
            ),
            FilledButton(
              style: destructive
                  ? FilledButton.styleFrom(
                      backgroundColor: scheme.error,
                      foregroundColor: scheme.onError,
                    )
                  : null,
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(confirmLabel),
            ),
          ],
        );
      },
    );
  }
  final confirmed = result ?? false;
  // Central haptic for every destructive confirmation — matches the buzz the
  // color swatches and notices already give, without scattering
  // HapticFeedback calls across features.
  if (confirmed && destructive) unawaited(HapticFeedback.mediumImpact());
  return confirmed;
}

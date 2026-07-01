import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:scheduling/core/adaptive/adaptive.dart';
import 'package:scheduling/core/theme/button_styles.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/l10n/l10n.dart';

enum SeriesScopeChoice { thisOnly, thisAndFuture }

/// Shared "this visit only / this and future visits" picker for a repeating
/// appointment — used by both the edit and delete flows. [message] states the
/// scope/consequence of the choice (the apply-to-all option touches every
/// future visit, so the copy must say so). Returns null when cancelled.
/// [destructive] styles the actions as a delete (error-filled primary with a
/// delete glyph so the intent isn't carried by colour alone, destructive
/// outline).
Future<SeriesScopeChoice?> showSeriesScopeDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String thisOnlyLabel,
  required String thisAndFutureLabel,
  bool destructive = false,
}) {
  if (context.isCupertino) {
    return showCupertinoModalPopup<SeriesScopeChoice>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: Text(title),
        message: Text(message),
        actions: [
          CupertinoActionSheetAction(
            isDestructiveAction: destructive,
            onPressed: () => Navigator.pop(ctx, SeriesScopeChoice.thisOnly),
            child: Text(thisOnlyLabel),
          ),
          CupertinoActionSheetAction(
            isDestructiveAction: destructive,
            onPressed: () =>
                Navigator.pop(ctx, SeriesScopeChoice.thisAndFuture),
            child: Text(thisAndFutureLabel),
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
  return showDialog<SeriesScopeChoice>(
    context: context,
    builder: (ctx) {
      final l = ctx.l10n;
      final scheme = Theme.of(ctx).colorScheme;
      void choose(SeriesScopeChoice? choice) => Navigator.pop(ctx, choice);
      return AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OutlinedButton(
                style: destructive ? destructiveOutlinedButtonStyle(ctx) : null,
                onPressed: () => choose(SeriesScopeChoice.thisOnly),
                child: Text(thisOnlyLabel),
              ),
              const SizedBox(height: AppSpacing.sp8),
              if (destructive)
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: scheme.error,
                    foregroundColor: scheme.onError,
                  ),
                  onPressed: () => choose(SeriesScopeChoice.thisAndFuture),
                  icon: const Icon(Icons.delete_outline),
                  label: Text(thisAndFutureLabel),
                )
              else
                FilledButton(
                  onPressed: () => choose(SeriesScopeChoice.thisAndFuture),
                  child: Text(thisAndFutureLabel),
                ),
              const SizedBox(height: AppSpacing.sp4),
              TextButton(
                onPressed: () => choose(null),
                child: Text(l.common_cancel),
              ),
            ],
          ),
        ],
      );
    },
  );
}

import 'package:flutter/material.dart';

import 'package:scheduling/core/adaptive/adaptive.dart';
import 'package:scheduling/core/adaptive/adaptive_action_sheet.dart';
import 'package:scheduling/core/theme/button_styles.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/l10n/l10n.dart';

enum SeriesScopeChoice { thisOnly, thisAndFuture }

/// Shared 'this only / this and future' picker for repeating appointments; [destructive] styles as delete.
Future<SeriesScopeChoice?> showSeriesScopeDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String thisOnlyLabel,
  required String thisAndFutureLabel,
  bool destructive = false,
}) {
  if (context.isCupertino) {
    return showAdaptiveActionSheet<SeriesScopeChoice>(
      context,
      title: title,
      message: message,
      actions: [
        AdaptiveSheetAction(
          value: SeriesScopeChoice.thisOnly,
          label: thisOnlyLabel,
          isDestructive: destructive,
        ),
        AdaptiveSheetAction(
          value: SeriesScopeChoice.thisAndFuture,
          label: thisAndFutureLabel,
          isDestructive: destructive,
        ),
      ],
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

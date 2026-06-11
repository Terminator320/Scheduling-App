import 'package:flutter/material.dart';

import 'package:scheduling/core/theme/button_styles.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/l10n/l10n.dart';

enum SeriesScopeChoice { thisOnly, thisAndFuture }

/// Shared "this visit only / this and future visits" picker for a repeating
/// appointment — used by both the edit and delete flows. Returns null when
/// cancelled. [destructive] styles the actions as a delete (error-filled
/// primary, destructive outline).
Future<SeriesScopeChoice?> showSeriesScopeDialog(
  BuildContext context, {
  required String title,
  required String thisOnlyLabel,
  required String thisAndFutureLabel,
  bool destructive = false,
}) {
  return showDialog<SeriesScopeChoice>(
    context: context,
    builder: (ctx) {
      final l = ctx.l10n;
      final scheme = Theme.of(ctx).colorScheme;
      return AlertDialog(
        title: Text(title),
        content: Text(l.calendar_repeatingSeriesMessage),
        actions: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OutlinedButton(
                style: destructive ? destructiveOutlinedButtonStyle(ctx) : null,
                onPressed: () => Navigator.pop(ctx, SeriesScopeChoice.thisOnly),
                child: Text(thisOnlyLabel),
              ),
              const SizedBox(height: AppSpacing.sp8),
              FilledButton(
                style: destructive
                    ? FilledButton.styleFrom(
                        backgroundColor: scheme.error,
                        foregroundColor: scheme.onError,
                      )
                    : null,
                onPressed: () =>
                    Navigator.pop(ctx, SeriesScopeChoice.thisAndFuture),
                child: Text(thisAndFutureLabel),
              ),
              const SizedBox(height: AppSpacing.sp4),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(l.common_cancel),
              ),
            ],
          ),
        ],
      );
    },
  );
}

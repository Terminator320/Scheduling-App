import 'package:flutter/material.dart';

import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/dialogs/confirm_dialog.dart';

enum DeleteAppointmentChoice { thisOnly, thisAndFuture }

/// Delete confirmation for appointments. A repeating visit asks whether to
/// delete this visit only or this and the future visits; null = cancelled.
Future<DeleteAppointmentChoice?> showDeleteAppointmentDialog(
  BuildContext context, {
  required bool isSeries,
}) async {
  if (!isSeries) {
    final confirmed = await showConfirmDialog(
      context,
      title: context.l10n.calendar_deleteAppointment,
      message: context.l10n.calendar_areYouSureYouWantToDeleteThisJob,
      confirmLabel: context.l10n.common_delete,
    );
    return confirmed ? DeleteAppointmentChoice.thisOnly : null;
  }

  return showDialog<DeleteAppointmentChoice>(
    context: context,
    builder: (ctx) {
      final scheme = Theme.of(ctx).colorScheme;
      return AlertDialog(
        title: Text(ctx.l10n.calendar_deleteAppointment),
        content: Text(ctx.l10n.calendar_deleteSeriesMessage),
        actions: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: scheme.error,
                  side: BorderSide(color: scheme.error),
                ),
                onPressed: () =>
                    Navigator.pop(ctx, DeleteAppointmentChoice.thisOnly),
                child: Text(ctx.l10n.calendar_deleteThisVisitOnly),
              ),
              const SizedBox(height: AppSpacing.sp8),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: scheme.error,
                  foregroundColor: scheme.onError,
                ),
                onPressed: () =>
                    Navigator.pop(ctx, DeleteAppointmentChoice.thisAndFuture),
                child: Text(ctx.l10n.calendar_deleteThisAndFutureVisits),
              ),
              const SizedBox(height: AppSpacing.sp4),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(ctx.l10n.common_cancel),
              ),
            ],
          ),
        ],
      );
    },
  );
}

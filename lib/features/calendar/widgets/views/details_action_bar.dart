import 'package:flutter/material.dart';

import 'package:scheduling/core/layout/breakpoints.dart';
import 'package:scheduling/core/theme/button_styles.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/primitives/busy_button_icon.dart';

class DetailsActionBar extends StatelessWidget {
  const DetailsActionBar({
    required this.hasStarted,
    required this.isDone,
    required this.isCancelled,
    required this.isSaving,
    required this.onMarkDone,
    required this.onCancel,
    required this.onEditCompleted,
    super.key,
    this.showCancel = true,
  });

  final bool hasStarted;
  final bool isDone;
  final bool isCancelled;
  final bool isSaving;

  /// Admin gate. Also decides what a completed job offers: an admin gets the
  /// "Edit completed job" button, an employee the plain done indicator.
  final bool showCancel;

  final VoidCallback onMarkDone;
  final VoidCallback onCancel;

  /// Opens the edit form on a finished job. That form owns the status picker,
  /// which is the only way to move a job back off Complete — so for an admin
  /// this replaces the dead indicator rather than sitting beside it.
  final VoidCallback onEditCompleted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final compact = context.isCompact;
    // The design's complete action is a filled GREEN button, so it reads as
    // the success it is rather than as the generic secondary.
    final successFill = theme.statusColors.success;
    final onSuccessFill = contrastingForegroundFor(successFill);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpacing.sp24),
        if (hasStarted && !isDone && !isCancelled)
          FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 48),
              backgroundColor: successFill,
              foregroundColor: onSuccessFill,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.r16),
              ),
            ),
            onPressed: isSaving ? null : onMarkDone,
            child: _ActionButtonContent(
              compact: compact,
              icon: BusyButtonIcon(
                isBusy: isSaving,
                icon: Icons.check,
                color: onSuccessFill,
              ),
              label: context.l10n.calendar_markAsDone,
            ),
          ),
        if (isDone) ...[
          const SizedBox(height: AppSpacing.sp8),
          // A finished job used to end in a DISABLED "Complete" button — a
          // dead control in the one slot the eye goes to, and with Cancel
          // hidden once done, the sheet offered an admin nothing at all. For
          // an admin it is now the way into the edit form (which owns the
          // status picker, so it is also how a mis-tapped "Mark as complete"
          // gets undone). An employee still gets the plain indicator: the
          // rules let an assignee write `status:'done'` and nothing else, so
          // an editable control would only earn them a permission error.
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 48),
              foregroundColor: scheme.secondary,
              side: BorderSide(color: scheme.secondary),
            ),
            onPressed: showCancel && !isSaving ? onEditCompleted : null,
            child: _ActionButtonContent(
              compact: compact,
              icon: Icon(
                showCancel ? Icons.edit_outlined : Icons.check_circle_outline,
                size: 18,
                color: scheme.secondary,
              ),
              label: showCancel
                  ? context.l10n.calendar_editCompletedJob
                  : context.l10n.calendar_completed,
            ),
          ),
        ],
        if (showCancel && !isCancelled && !isDone) ...[
          if (hasStarted) const SizedBox(height: AppSpacing.sp8),
          OutlinedButton(
            style: destructiveOutlinedButtonStyle(
              context,
              minimumSize: const Size(double.infinity, 48),
            ),
            onPressed: isSaving ? null : onCancel,
            child: _ActionButtonContent(
              compact: compact,
              icon: const Icon(Icons.close, size: 15),
              label: context.l10n.calendar_cancelAppointment,
            ),
          ),
          const SizedBox(height: AppSpacing.sp4),
          Center(
            child: Text(
              context.l10n.calendar_cancelledJobsAreSavedToHistory,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ],
    );
  }
}

class _ActionButtonContent extends StatelessWidget {
  const _ActionButtonContent({
    required this.compact,
    required this.icon,
    required this.label,
  });

  final bool compact;
  final Widget icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final text = Text(
      label,
      textAlign: TextAlign.center,
      maxLines: compact ? 3 : 2,
      overflow: TextOverflow.ellipsis,
    );

    if (compact) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          icon,
          const SizedBox(height: AppSpacing.sp4),
          text,
        ],
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        icon,
        const SizedBox(width: AppSpacing.sp8),
        Flexible(child: text),
      ],
    );
  }
}

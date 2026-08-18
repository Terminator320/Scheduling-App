import 'package:flutter/material.dart';

import 'package:scheduling/core/layout/breakpoints.dart';
import 'package:scheduling/core/theme/button_styles.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/primitives/busy_button_icon.dart';

class DetailsActionBar extends StatelessWidget {
  const DetailsActionBar({
    required this.isDone,
    required this.isCancelled,
    required this.isSaving,
    required this.onMarkDone,
    required this.onCancel,
    super.key,
    this.showCancel = true,
    this.onEdit,
  });

  final bool isDone;
  final bool isCancelled;
  final bool isSaving;
  final bool showCancel;
  final VoidCallback onMarkDone;
  final VoidCallback onCancel;

  /// Edit action for a job that is already done. Null on a read-only surface,
  /// which falls back to the inert "Complete" indicator.
  final VoidCallback? onEdit;

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
        // Offered for the whole life of an open job — there is no
        // "has it started yet" gate (owner call, 2026-08-17). A crew that
        // finishes early, or an admin closing a job booked for later today,
        // had no affordance at all until the start time passed, while the
        // rules have always allowed an assignee's `status:'done'` write with
        // no date restriction.
        if (!isDone && !isCancelled)
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
        // A done job has no mark-done or cancel action left, so this slot is
        // where its Edit lives — the read view's top chip is hidden for it.
        // Without an edit callback (a read-only surface) it stays the inert
        // "Complete" indicator it has always been.
        if (isDone) ...[
          const SizedBox(height: AppSpacing.sp8),
          if (onEdit != null)
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
              ),
              onPressed: onEdit,
              child: _ActionButtonContent(
                compact: compact,
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: context.l10n.common_edit,
              ),
            )
          else
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
                foregroundColor: scheme.secondary,
                side: BorderSide(color: scheme.secondary),
              ),
              onPressed: null,
              child: _ActionButtonContent(
                compact: compact,
                icon: Icon(
                  Icons.check_circle_outline,
                  size: 18,
                  color: scheme.secondary,
                ),
                label: context.l10n.calendar_completed,
              ),
            ),
        ],
        if (showCancel && !isCancelled && !isDone) ...[
          // The complete button is always above this on an open job, so the
          // gap is unconditional.
          const SizedBox(height: AppSpacing.sp8),
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

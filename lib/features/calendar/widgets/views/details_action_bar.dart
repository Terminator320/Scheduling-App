import 'package:flutter/material.dart';

import 'package:scheduling/core/theme/button_styles.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/primitives/busy_button_icon.dart';

class DetailsActionBar extends StatelessWidget {
  const DetailsActionBar({
    required this.isToday,
    required this.isDone,
    required this.isCancelled,
    required this.isSaving,
    required this.onMarkDone,
    required this.onCancel,
    super.key,
    this.showCancel = true,
  });

  final bool isToday;
  final bool isDone;
  final bool isCancelled;
  final bool isSaving;
  final bool showCancel;
  final VoidCallback onMarkDone;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final compact =
        MediaQuery.sizeOf(context).width < 360 ||
        MediaQuery.textScalerOf(context).scale(1) > 1.4;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpacing.sp24),
        if (isToday && !isDone && !isCancelled)
          FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 48),
              backgroundColor: scheme.secondary,
              foregroundColor: scheme.onSecondary,
            ),
            onPressed: isSaving ? null : onMarkDone,
            child: _ActionButtonContent(
              compact: compact,
              icon: BusyButtonIcon(
                isBusy: isSaving,
                icon: Icons.check,
                color: scheme.onSecondary,
              ),
              label: context.l10n.calendar_markAsDone,
            ),
          ),
        if (isDone) ...[
          const SizedBox(height: AppSpacing.sp8),
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
        if (showCancel && !isCancelled) ...[
          if (isToday && !isDone) const SizedBox(height: AppSpacing.sp8),
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

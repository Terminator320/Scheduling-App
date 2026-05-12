import 'package:flutter/material.dart';

import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/core/utils/l10n_extensions.dart';

/// View-mode action bar at the bottom of the appointment-details sheet.
/// Shows "Mark as Done" (only for today's bookings), a "Completed" indicator
/// when already done, and "Cancel Appointment" with the cancellation hint
/// — except when the appointment is already cancelled, in which case the
/// whole bar collapses to nothing.
class DetailsActionBar extends StatelessWidget {
  const DetailsActionBar({
    required this.isToday,
    required this.isDone,
    required this.isCancelled,
    required this.isSaving,
    required this.onMarkDone,
    required this.onCancel,
    super.key,
  });

  final bool isToday;
  final bool isDone;
  final bool isCancelled;
  final bool isSaving;
  final VoidCallback onMarkDone;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpacing.sp24),
        if (isToday && !isDone && !isCancelled)
          FilledButton.icon(
            style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 48),
              backgroundColor: scheme.secondary,
              foregroundColor: scheme.onSecondary,
            ),
            onPressed: isSaving ? null : onMarkDone,
            icon: isSaving
                ? SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: scheme.onSecondary,
                    ),
                  )
                : const Icon(Icons.check, size: 18),
            label: Text(context.l10n.markAsDone),
          ),
        if (isDone) ...[
          const SizedBox(height: AppSpacing.sp8),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 44),
              foregroundColor: scheme.secondary,
              side: BorderSide(color: scheme.secondary),
            ),
            onPressed: null,
            icon: const Icon(Icons.check_circle_outline, size: 18),
            label: Text(context.l10n.completed),
          ),
        ],
        if (!isCancelled) ...[
          if (isToday && !isDone) const SizedBox(height: AppSpacing.sp8),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 44),
              foregroundColor: scheme.error,
              side: BorderSide(color: scheme.error),
            ),
            onPressed: isSaving ? null : onCancel,
            icon: const Icon(Icons.close, size: 15),
            label: Text(context.l10n.cancelAppointment),
          ),
          const SizedBox(height: 5),
          Center(
            child: Text(
              context.l10n.cancelledJobsAreSavedToHistory,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

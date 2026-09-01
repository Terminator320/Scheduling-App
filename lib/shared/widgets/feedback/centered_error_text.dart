import 'package:flutter/material.dart';

import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/l10n/l10n.dart';

/// Centered muted error text — reads as an empty state, not an alarm.
///
/// Pass [onRetry] wherever the failure is a LOAD rather than a permanent
/// condition. Without it the screen is inert: the only way out of a transient
/// error was to back out and come in again, and My Details — the one
/// self-service screen an employee has — had four such dead ends. History
/// already did this properly (`appointment_history_view.dart`), which is where
/// the shape comes from.
class CenteredErrorText extends StatelessWidget {
  const CenteredErrorText({required this.message, this.onRetry, super.key});

  final String message;

  /// Re-runs the load. Null renders text alone, for a state a retry cannot fix.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final retry = onRetry;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sp24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (retry != null) ...[
              const SizedBox(height: AppSpacing.sp12),
              TextButton.icon(
                onPressed: retry,
                icon: const Icon(Icons.refresh),
                label: Text(context.l10n.common_retry),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

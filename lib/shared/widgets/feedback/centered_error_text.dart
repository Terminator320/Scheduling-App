import 'package:flutter/material.dart';

import 'package:scheduling/core/theme/design_tokens.dart';

/// Centered muted error text — reads as an empty state, not an alarm.
class CenteredErrorText extends StatelessWidget {
  const CenteredErrorText({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sp24),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

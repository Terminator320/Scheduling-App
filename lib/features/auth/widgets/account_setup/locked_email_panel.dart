import 'package:flutter/material.dart';

import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/l10n/l10n.dart';

/// The sign-in email, presented read-only. Deliberately NOT a disabled
/// [TextField]: there is nothing to focus, autofill must not target it, and a
/// disabled field truncates at large text scale where a wrapping [Text] does
/// not.
class LockedEmailPanel extends StatelessWidget {
  const LockedEmailPanel({required this.email, super.key});

  final String email;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = theme.palette;
    final l10n = context.l10n;

    return Semantics(
      readOnly: true,
      label: l10n.common_email,
      value: email,
      excludeSemantics: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.sp16),
        decoration: BoxDecoration(
          color: palette.lockedPanel,
          borderRadius: BorderRadius.circular(AppRadius.r12),
          border: Border.all(color: palette.lockedPanelBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.common_email, style: theme.textTheme.labelLarge),
            const SizedBox(height: AppSpacing.sp8),
            Text(
              email,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: palette.textBody,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

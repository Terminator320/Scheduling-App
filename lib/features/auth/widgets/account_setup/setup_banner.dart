import 'package:flutter/material.dart';

import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/l10n/l10n.dart';

/// Explains why this screen exists at all: they signed in with a password
/// somebody else chose, and it stops working the moment they finish here.
class SetupBanner extends StatelessWidget {
  const SetupBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sp16),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(AppRadius.r12),
      ),
      child: Text(
        context.l10n.auth_setUpYourAccountBody,
        style: theme.textTheme.bodySmall?.copyWith(
          color: scheme.onPrimaryContainer,
        ),
      ),
    );
  }
}

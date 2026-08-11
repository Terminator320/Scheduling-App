import 'package:flutter/material.dart';

import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/l10n/l10n.dart';

/// Reads SIGNED IN until the address is verified, then VERIFIED. The icon
/// changes with the label, so the state is never signalled by colour alone.
class SignedInChip extends StatelessWidget {
  const SignedInChip({required this.isVerified, super.key});

  final bool isVerified;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = theme.statusColors;
    final background = isVerified
        ? status.successContainer
        : scheme.primaryContainer;
    final foreground = isVerified
        ? status.onSuccessContainer
        : scheme.onPrimaryContainer;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sp8,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.rFull),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isVerified ? Icons.verified_outlined : Icons.lock_outline,
            size: 12,
            color: foreground,
          ),
          const SizedBox(width: AppSpacing.sp4),
          Text(
            isVerified
                ? context.l10n.auth_emailVerified
                : context.l10n.auth_signedInAs,
            style: theme.monoType.micro.copyWith(color: foreground),
          ),
        ],
      ),
    );
  }
}

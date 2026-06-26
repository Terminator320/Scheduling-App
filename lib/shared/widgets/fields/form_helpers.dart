import 'package:flutter/material.dart';

import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/l10n/l10n.dart';

Widget formLabel(
  BuildContext context,
  String text, {
  bool optional = false,
  bool required = false,
}) {
  final baseStyle = Theme.of(context).textTheme.labelLarge;
  return Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.sp8),
    child: Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      runSpacing: 2,
      children: [
        Text(text, style: baseStyle),
        if (required)
          Text(
            ' *',
            style: baseStyle?.copyWith(
              color: Theme.of(context).colorScheme.error,
            ),
          ),
        if (optional)
          Text(
            ' (${context.l10n.common_optional})',
            style: baseStyle?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    ),
  );
}

InputDecoration formInputDecoration(BuildContext context, String hint) {
  return InputDecoration(
    hintText: hint,
    contentPadding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.sp16,
      vertical: AppSpacing.sp12,
    ),
  );
}

Widget formRemoveButton(BuildContext context) {
  return Container(
    padding: const EdgeInsets.all(2),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.scrim.withValues(alpha: 0.54),
      shape: BoxShape.circle,
    ),
    child: const Icon(Icons.close, size: 14, color: Colors.white),
  );
}

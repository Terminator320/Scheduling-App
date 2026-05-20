import 'package:flutter/material.dart';

import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/l10n/l10n.dart';

Widget formLabel(
  BuildContext context,
  String text, {
  bool optional = false,
  bool required = false,
}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      children: [
        Text(text, style: Theme.of(context).textTheme.labelLarge),
        if (required)
          Text(
            ' *',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.error,
            ),
          ),
        if (optional)
          Text(
            ' (${context.l10n.optional})',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    ),
  );
}

Widget formSectionLabel(BuildContext context, String text) {
  return Text(
    text.toUpperCase(),
    style: Theme.of(context).textTheme.labelMedium?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
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

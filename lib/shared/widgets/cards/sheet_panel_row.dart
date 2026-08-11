import 'package:flutter/material.dart';

import 'package:scheduling/core/theme/design_tokens.dart';

/// One labelled row inside a `SheetPanel` that is NOT a value picker.
///
/// The sibling of `SheetFieldRow`: that one is label-over-value for dates and
/// times, this one is label-over-arbitrary-child (a chip strip) or
/// label-beside-control (a switch). A `SheetFieldRow` with an empty value would
/// render a blank second line where the value belongs.
///
/// Shared rather than private to a sheet because the AVAILABILITY panel now
/// appears on two screens — the admin's edit-person sheet and the employee's My
/// details — and the two must not drift on padding or label style. Do not use a
/// `ListTile` family widget here: a `SheetPanel` paints its own decoration, and
/// `ListTile` asserts when its background sits inside a `DecoratedBox`.
class SheetPanelRow extends StatelessWidget {
  const SheetPanelRow({
    required this.label,
    this.child,
    this.trailing,
    super.key,
  }) : assert(
         child != null || trailing != null,
         'a row needs either a child or a trailing control',
       );

  final String label;

  /// Rendered UNDER the label. Ignored when [trailing] is given.
  final Widget? child;

  /// Rendered BESIDE the label, right-aligned.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelText = Text(
      label,
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sp16,
        vertical: AppSpacing.sp12,
      ),
      child: trailing != null
          ? Row(
              children: [
                Expanded(child: labelText),
                const SizedBox(width: AppSpacing.sp8),
                trailing!,
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                labelText,
                const SizedBox(height: AppSpacing.sp8),
                child!,
              ],
            ),
    );
  }
}

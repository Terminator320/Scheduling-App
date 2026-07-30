import 'package:flutter/material.dart';

import 'package:scheduling/core/theme/design_tokens.dart';

/// A white panel of divided rows — the container every form-sheet section uses
/// (`06-sheets-and-dialogs.md`). Rows supply their own padding.
class SheetPanel extends StatelessWidget {
  const SheetPanel({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: appCardDecoration(
        theme,
        radius: AppRadius.r16,
        color: theme.palette.sheetRow,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.r16),
        child: Column(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0)
                Divider(height: 1, color: theme.colorScheme.outlineVariant),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}

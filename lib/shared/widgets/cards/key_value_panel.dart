import 'package:flutter/material.dart';

import 'package:scheduling/core/layout/breakpoints.dart';
import 'package:scheduling/core/theme/design_tokens.dart';

/// One `KEY  value` row. A null [onTap] renders it inert.
class KeyValueRow {
  const KeyValueRow({
    required this.label,
    required this.value,
    this.onTap,
    this.emphasize = false,
    this.semanticLabel,
  });

  /// Already uppercase at the call site, like `SectionLabel`.
  final String label;
  final String value;
  final VoidCallback? onTap;

  /// Renders the value in the accent colour — phone and address rows.
  final bool emphasize;
  final String? semanticLabel;
}

/// The detail sheets' info panel: a fixed mono key column beside its values
/// (`06-sheets-and-dialogs.md`). Rows with an empty value are omitted by the
/// caller — read-only detail bodies never render "None" placeholders.
///
/// Deliberately not a restyled `InfoCard`: that one is shared with the clients
/// feature, which P3 redesigns on its own schedule.
class KeyValuePanel extends StatelessWidget {
  const KeyValuePanel({required this.rows, super.key});

  final List<KeyValueRow> rows;

  static const double _keyColumnWidth = 70;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Below the compact gate the 70px key column starves the value, so the
    // label moves above it.
    final stacked = context.isCompact;

    return DecoratedBox(
      decoration: appCardDecoration(
        theme,
        radius: AppRadius.rPanel,
        color: theme.palette.sheetRow,
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0)
              Divider(height: 1, color: theme.colorScheme.outlineVariant),
            _Row(row: rows[i], stacked: stacked),
          ],
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.row, required this.stacked});

  final KeyValueRow row;
  final bool stacked;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final valueStyle = theme.textTheme.bodyMedium?.copyWith(
      fontWeight: row.emphasize ? FontWeight.w600 : FontWeight.w500,
      color: row.emphasize ? theme.palette.primaryAccent : null,
    );
    final label = Text(row.label, style: theme.monoType.fieldLabel);
    final value = Text(row.value, style: valueStyle);

    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
      child: stacked
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                label,
                const SizedBox(height: AppSpacing.sp4),
                value,
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: KeyValuePanel._keyColumnWidth,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: label,
                  ),
                ),
                Expanded(child: value),
              ],
            ),
    );

    if (row.onTap == null) {
      return Semantics(label: row.semanticLabel, child: content);
    }
    return Semantics(
      button: true,
      label: row.semanticLabel,
      child: InkWell(onTap: row.onTap, child: content),
    );
  }
}

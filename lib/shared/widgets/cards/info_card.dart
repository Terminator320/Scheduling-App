import 'package:flutter/material.dart';

import 'package:scheduling/core/layout/breakpoints.dart';
import 'package:scheduling/core/theme/design_tokens.dart';

/// Bordered card that stacks [rows] with a hairline divider between each pair.
/// Shared by the client and appointment detail views.
class InfoCard extends StatelessWidget {
  const InfoCard({required this.rows, super.key});

  final List<InfoCardRow> rows;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(AppRadius.r16),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.r16),
        child: Column(
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) const Divider(height: 1, indent: 60),
              rows[i],
            ],
          ],
        ),
      ),
    );
  }
}

/// One row inside an [InfoCard]: a tinted icon chip, the value, and an
/// optional trailing affordance. Tappable when [onTap] is non-null.
class InfoCardRow extends StatelessWidget {
  const InfoCardRow({
    required this.icon,
    required this.text,
    this.iconColor,
    this.onTap,
    this.trailingIcon,
    this.emphasize = false,
    this.semanticLabel,
    super.key,
  });

  final IconData icon;
  final String text;
  final Color? iconColor;
  final VoidCallback? onTap;
  final IconData? trailingIcon;

  /// Renders the value as a bold title (used for a contact's name row).
  final bool emphasize;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final chipColor = iconColor ?? scheme.primary;
    final compact = context.isCompact;

    final content = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sp16,
        vertical: AppSpacing.sp12,
      ),
      child: Row(
        crossAxisAlignment: compact
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.center,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: chipColor.withValues(alpha: theme.cardStyle.iconChipAlpha),
              borderRadius: BorderRadius.circular(AppRadius.r8),
            ),
            child: Icon(icon, size: 18, color: chipColor),
          ),
          const SizedBox(width: AppSpacing.sp12),
          Expanded(
            child: Text(
              text,
              style: emphasize
                  ? theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurface,
                    )
                  : theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurface,
                      height: 1.3,
                    ),
            ),
          ),
          if (trailingIcon != null) ...[
            const SizedBox(width: AppSpacing.sp8),
            Padding(
              padding: EdgeInsets.only(top: compact ? 2 : 0),
              child: Icon(
                trailingIcon,
                size: 18,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );

    if (onTap == null) return content;

    return Semantics(
      button: true,
      label: semanticLabel,
      child: InkWell(onTap: onTap, child: content),
    );
  }
}

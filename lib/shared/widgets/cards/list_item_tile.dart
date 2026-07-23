import 'package:flutter/material.dart';

import 'package:scheduling/core/layout/breakpoints.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/shared/widgets/primitives/app_avatar.dart';

/// Shared list row: avatar, title/subtitle, trailing widget, chevron.
class ListItemTile extends StatelessWidget {
  const ListItemTile({
    required this.avatarName,
    required this.title,
    super.key,
    this.subtitle,
    this.avatarColor,
    this.trailing,
    this.onTap,
    this.selected = false,
    this.dimmed = false,
  });

  final String avatarName;
  final String title;
  final String? subtitle;
  final Color? avatarColor;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool selected;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final compact = context.isCompact;

    Widget row = Material(
      color: selected ? scheme.secondaryContainer : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sp16,
            vertical: AppSpacing.sp12,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppAvatar(name: avatarName, color: avatarColor),
              const SizedBox(width: AppSpacing.sp12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: compact ? 2 : 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.sp4),
                      Text(
                        subtitle!,
                        maxLines: compact ? 2 : 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (compact && trailing != null) ...[
                      const SizedBox(height: AppSpacing.sp8),
                      Align(alignment: Alignment.centerLeft, child: trailing),
                    ],
                  ],
                ),
              ),
              if (!compact && trailing != null) ...[
                const SizedBox(width: AppSpacing.sp8),
                trailing!,
              ],
              const SizedBox(width: AppSpacing.sp8),
              Icon(
                Icons.chevron_right,
                size: 18,
                color: scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );

    if (dimmed) {
      row = Opacity(opacity: 0.65, child: row);
    }

    return row;
  }
}

import 'package:flutter/material.dart';
import 'package:scheduling/core/layout/breakpoints.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/shared/widgets/primitives/app_avatar.dart';

class EntityFormHeader extends StatelessWidget {
  const EntityFormHeader({
    required this.name,
    this.avatarColor,
    this.status,
    super.key,
  });

  final String name;
  final Color? avatarColor;
  final Widget? status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final compact = context.isCompact;

    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppAvatar(name: name, color: avatarColor, size: AvatarSize.lg),
          const SizedBox(height: AppSpacing.sp12),
          Text(
            name,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          if (status != null) ...[
            const SizedBox(height: AppSpacing.sp8),
            status!,
          ],
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppAvatar(name: name, color: avatarColor, size: AvatarSize.lg),
        const SizedBox(width: AppSpacing.sp12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (status != null) ...[
                const SizedBox(height: AppSpacing.sp4),
                status!,
              ],
            ],
          ),
        ),
      ],
    );
  }
}

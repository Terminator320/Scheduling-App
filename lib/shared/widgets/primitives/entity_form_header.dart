import 'package:flutter/material.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/shared/widgets/primitives/app_avatar.dart';

/// Horizontal header for an entity edit form: a large [AppAvatar] beside the
/// entity [name], with an optional [status] chip below the name. Shared by the
/// client- and employee-edit forms. [avatarColor] tints the avatar (employees);
/// when null the avatar derives its color from [name].
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
    return Row(
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

import 'package:flutter/material.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/shared/widgets/primitives/name_initials.dart';

enum AvatarSize {
  xs,
  sm,
  md,
  lg;

  /// Painted diameter. Exposed because a caller that has to lay an avatar out
  /// by hand — the appointment card's overlapped crew stack, which can't use
  /// `LayoutBuilder` under `IntrinsicHeight` — must not keep its own copy.
  double get diameter => switch (this) {
    AvatarSize.xs => 20.0,
    AvatarSize.sm => 28.0,
    AvatarSize.md => 36.0,
    AvatarSize.lg => 48.0,
  };
}

class AppAvatar extends StatelessWidget {
  const AppAvatar({
    required this.name,
    super.key,
    this.color,
    this.size = AvatarSize.md,
  });

  final String name;
  final Color? color;
  final AvatarSize size;

  @override
  Widget build(BuildContext context) {
    final diameter = size.diameter;
    final fontSize = switch (size) {
      AvatarSize.xs => 8.0,
      AvatarSize.sm => 10.0,
      AvatarSize.md => 13.0,
      AvatarSize.lg => 17.0,
    };
    final theme = Theme.of(context);
    final initials = nameInitials(name);
    final stored = color ?? _colorFromName(name);
    final background = crewColorOf(theme, stored.toARGB32());
    final foreground = avatarForegroundFor(theme, background);
    return Container(
      constraints: BoxConstraints.tight(Size(diameter, diameter)),
      decoration: BoxDecoration(
        color: background,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: initials == '?'
          ? Icon(Icons.person, color: foreground, size: fontSize + 4)
          : Text(
              initials,
              style: TextStyle(
                color: foreground,
                fontSize: fontSize,
                fontWeight: FontWeight.w700,
              ),
            ),
    );
  }

  static Color _colorFromName(String name) {
    return AppColors.crewPalette[name.hashCode.abs() %
        AppColors.crewPalette.length];
  }
}

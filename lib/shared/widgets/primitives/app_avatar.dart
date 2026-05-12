import 'package:flutter/material.dart';
import 'package:scheduling/core/theme/design_tokens.dart';

enum AvatarSize { xs, sm, md, lg }

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
    final diameter = switch (size) {
      AvatarSize.xs => 20.0,
      AvatarSize.sm => 28.0,
      AvatarSize.md => 36.0,
      AvatarSize.lg => 48.0,
    };
    final fontSize = switch (size) {
      AvatarSize.xs => 8.0,
      AvatarSize.sm => 10.0,
      AvatarSize.md => 13.0,
      AvatarSize.lg => 17.0,
    };
    final initials = _initials(name);
    final background = color ?? _colorFromName(name);
    final foreground = contrastingForegroundFor(background);
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

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  static Color _colorFromName(String name) {
    return AppColors.employeePalette[name.hashCode.abs() %
        AppColors.employeePalette.length];
  }
}

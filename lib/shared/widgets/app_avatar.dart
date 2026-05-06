// lib/shared/widgets/app_avatar.dart
import 'package:flutter/material.dart';
import '../../core/theme/design_tokens.dart';

enum AvatarSize { sm, md, lg }

class AppAvatar extends StatelessWidget {
  const AppAvatar({super.key, required this.name, this.color, this.size = AvatarSize.md});

  final String name;
  final Color? color;
  final AvatarSize size;

  @override
  Widget build(BuildContext context) {
    final diameter = switch (size) {
      AvatarSize.sm => 28.0,
      AvatarSize.md => 36.0,
      AvatarSize.lg => 48.0,
    };
    final fontSize = switch (size) {
      AvatarSize.sm => 10.0,
      AvatarSize.md => 13.0,
      AvatarSize.lg => 17.0,
    };
    return Container(
      constraints: BoxConstraints.tight(Size(diameter, diameter)),
      decoration: BoxDecoration(
        color: color ?? _colorFromName(name),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        _initials(name),
        style: TextStyle(
          color: Colors.white,
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
    return AppColors.employeePalette[name.hashCode.abs() % AppColors.employeePalette.length];
  }
}

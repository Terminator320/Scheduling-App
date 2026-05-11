// lib/shared/widgets/app_search_bar.dart
import 'package:flutter/material.dart';
import 'package:scheduling/core/theme/design_tokens.dart';

class AppSearchBar extends StatelessWidget implements PreferredSizeWidget {
  const AppSearchBar({
    required this.onChanged, super.key,
    this.hintText = 'Search…',
    this.controller,
    this.focusNode,
  });

  final ValueChanged<String> onChanged;
  final String hintText;
  final TextEditingController? controller;
  final FocusNode? focusNode;

  @override
  Size get preferredSize => const Size.fromHeight(52);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sp16,
        vertical: AppSpacing.sp8,
      ),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        onChanged: onChanged,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurface,
        ),
        decoration: InputDecoration(
          hintText: hintText,
          prefixIcon: Icon(
            Icons.search,
            size: 18,
            color: isDark ? AppColors.darkMuted : AppColors.muted,
          ),
          filled: true,
          fillColor: isDark ? AppColors.darkSurfaceAlt : AppColors.surfaceAlt,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.r12),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: AppSpacing.sp8),
        ),
      ),
    );
  }
}

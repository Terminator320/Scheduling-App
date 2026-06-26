import 'package:flutter/material.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/shared/widgets/fields/clear_text_button.dart';

class AppSearchBar extends StatelessWidget implements PreferredSizeWidget {
  const AppSearchBar({
    super.key,
    this.onChanged,
    this.hintText = 'Search...',
    this.controller,
    this.focusNode,
  });

  static const double preferredHeight = 60;

  final ValueChanged<String>? onChanged;
  final String hintText;
  final TextEditingController? controller;
  final FocusNode? focusNode;

  @override
  Size get preferredSize => const Size.fromHeight(preferredHeight);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sp16,
        vertical: AppSpacing.sp8,
      ),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        onChanged: onChanged ?? (_) {},
        maxLines: 1,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: scheme.onSurface,
        ),
        decoration: InputDecoration(
          hintText: hintText,
          prefixIcon: Icon(
            Icons.search,
            size: 18,
            color: scheme.onSurfaceVariant,
          ),
          filled: true,
          fillColor: scheme.surfaceContainerHighest,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.r12),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: AppSpacing.sp12),
          suffixIcon: controller != null
              ? ClearTextButton(
                  controller: controller!,
                  onCleared: () => onChanged?.call(''),
                )
              : null,
        ),
      ),
    );
  }
}

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
    final scheme = Theme.of(context).colorScheme;
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
          contentPadding: const EdgeInsets.symmetric(vertical: AppSpacing.sp8),
          suffixIcon: controller != null
              ? ValueListenableBuilder<TextEditingValue>(
                  valueListenable: controller!,
                  builder: (context, value, child) {
                    final hasText = value.text.isNotEmpty;
                    return IgnorePointer(
                      ignoring: !hasText,
                      child: AnimatedScale(
                        scale: hasText ? 1.0 : 0.0,
                        duration: AppDuration.fast,
                        curve: Curves.easeOut,
                        child: IconButton(
                          icon: Icon(
                            Icons.clear,
                            size: 16,
                            color: scheme.onSurfaceVariant,
                          ),
                          onPressed: () {
                            controller!.clear();
                            onChanged('');
                          },
                        ),
                      ),
                    );
                  },
                )
              : null,
        ),
      ),
    );
  }
}

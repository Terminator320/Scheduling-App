import 'package:flutter/material.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/l10n/l10n.dart';

/// Suffix-slot clear ("x") button; shows placeholder while empty.
class ClearTextButton extends StatelessWidget {
  const ClearTextButton({
    required this.controller,
    super.key,
    this.onCleared,
    this.placeholder,
  });

  final TextEditingController controller;
  final VoidCallback? onCleared;
  final Widget? placeholder;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final hasText = value.text.isNotEmpty;
        if (!hasText && placeholder != null) return placeholder!;
        return IgnorePointer(
          ignoring: !hasText,
          child: AnimatedScale(
            scale: hasText ? 1.0 : 0.0,
            duration: AppDuration.fast,
            curve: Curves.easeOut,
            child: IconButton(
              icon: Icon(Icons.clear, size: 16, color: scheme.onSurfaceVariant),
              tooltip: context.l10n.common_clearText,
              onPressed: () {
                controller.clear();
                onCleared?.call();
              },
            ),
          ),
        );
      },
    );
  }
}

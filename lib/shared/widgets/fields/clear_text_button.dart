import 'package:flutter/material.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/l10n/l10n.dart';

/// Suffix-slot clear ("x") button for a text field. Appears (with a quick
/// scale-in) only while [controller] holds text; tapping it clears the field
/// and fires [onCleared] so the host's state/validation stays in sync.
///
/// [placeholder] renders instead of the button while the field is empty
/// (e.g. a search icon); without it the slot just collapses.
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
